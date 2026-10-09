"""Exercise the actual helper allowlist expression with Windows/POSIX path semantics."""
import argparse
import ast
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath


def sha(data):
    return hashlib.sha256(data).hexdigest()


def expression(helper):
    tree = ast.parse(helper.read_bytes(), filename=helper.name)
    matches = [n for n in ast.walk(tree) if isinstance(n, ast.Call)
               and isinstance(n.func, ast.Name) and n.func.id == "check"
               and len(n.args) == 2 and isinstance(n.args[1], ast.Constant)
               and n.args[1].value == "patch touches only allowed file"]
    assert len(matches) == 1
    return compile(ast.Expression(matches[0].args[0]), "HASH_BOUND_ALLOWLIST_EXPRESSION", "eval")


class Entry:
    def __init__(self, path, file=True):
        self.path, self.file = path, file

    def relative_to(self, directory):
        return self.path.relative_to(directory)

    def is_file(self):
        return self.file


class Walk:
    def __init__(self, entries):
        self.entries = entries

    def rglob(self, pattern):
        assert pattern == "*"
        return self.entries


def evaluate(compiled, directory, entries, expected):
    namespace = {"Path": lambda _: Walk(entries), "directory": directory,
                 "change": {"path": expected}, "str": str}
    return eval(compiled, namespace)


def relative_function(prepare):
    tree = ast.parse(prepare.read_bytes(), filename=prepare.name)
    matches = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "relative"]
    assert len(matches) == 1
    namespace = {"PurePosixPath": PurePosixPath}
    exec(compile(ast.Module(body=matches, type_ignores=[]), "HASH_BOUND_PREPARE_RELATIVE", "exec"), namespace)
    return namespace["relative"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for suite in ["clock", "focus"]:
        for role in ["v2", "v3", "tests"]:
            parser.add_argument("--" + suite + "-" + role, required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New JSON result file; no overwrite")
    args = parser.parse_args()
    assert not args.output.exists()
    checks, cases, bindings = [], [], []

    def check(ok, name):
        checks.append({"name": name, "passed": bool(ok)})
        if not ok:
            raise AssertionError(name)

    expected = "view/playable_build/player_details.gd"
    scenarios = [
        ("one_allowed", [(expected, True)], True),
        ("allowed_plus_directory", [("view", False), (expected, True)], True),
        ("empty", [], False),
        ("wrong_only", [("view/playable_build/wrong.gd", True)], False),
        ("extra_file", [(expected, True), ("extra.gd", True)], False),
        ("duplicate_file", [(expected, True), (expected, True)], False),
        ("case_mismatch", [("view/playable_build/Player_Details.gd", True)], False),
        ("traversal", [("../view/playable_build/player_details.gd", True)], False),
    ]
    for suite in ["clock", "focus"]:
        old = getattr(args, suite + "_v2") / "check_static.py"
        new = getattr(args, suite + "_v3") / "check_static.py"
        before, after = old.read_bytes(), new.read_bytes()
        check(before.count(b"str(p.relative_to(directory))") == 1 and
              before.replace(b"str(p.relative_to(directory))", b"p.relative_to(directory).as_posix()") == after,
              suite + " exact one-expression-only helper code diff")
        check(b'check(target.read_bytes() == after,' in after and
              b'"core.autocrlf=false", "-c", "core.eol=lf"' in after,
              suite + " original strict byte equality and LF flags retained")
        old_expression, new_expression = expression(old), expression(new)
        for flavor, factory, base in [("windows", PureWindowsPath, "E:/owned/replay"),
                                      ("posix", PurePosixPath, "/owned/replay")]:
            directory = factory(base)
            native = str((directory / expected).relative_to(directory))
            normalized = (directory / expected).relative_to(directory).as_posix()
            check(normalized == expected and (native != expected if flavor == "windows" else native == expected),
                  suite + " " + flavor + " actual PurePath separator semantics")
            for name, entries, allowed in scenarios:
                actual_entries = [Entry(directory / path, file) for path, file in entries]
                old_ok = evaluate(old_expression, directory, actual_entries, expected)
                new_ok = evaluate(new_expression, directory, actual_entries, expected)
                check(new_ok == allowed, suite + " " + flavor + " v3 strict allowlist " + name)
                check(old_ok == (allowed and flavor == "posix"), suite + " " + flavor + " v2 observed allowlist behavior " + name)
                cases.append({"suite": suite, "flavor": flavor, "case": name, "expected_allowed": allowed,
                              "v2_allowed": old_ok, "v3_allowed": new_ok})
        prepare = getattr(args, suite + "_tests") / "prepare.py"
        source = prepare.read_bytes()
        check(b"path = PurePosixPath(value)" in source and b"str(path) != value" in source,
              suite + " preparer already uses platform-independent repository path class")
        relative = relative_function(prepare)
        for path in [expected, "tests/focused/source_binding.json", "data/catalog.json", "project.godot"]:
            check(relative(path).as_posix() == path, suite + " actual preparer accepts exact POSIX path " + path)
        for path in ["", ".", "../escape", "/absolute", "view/../escape", "view//file.gd",
                     "view/./file.gd", "view/file.gd/", "view\\file.gd", "E:\\outside\\file.gd"]:
            try:
                relative(path)
                rejected = False
            except ValueError:
                rejected = True
            check(rejected, suite + " actual preparer retains unsafe/noncanonical rejection " + repr(path))
        package_root = getattr(args, suite + "_tests")
        inputs = json.loads((package_root / "INPUTS.json").read_bytes())
        manifest = json.loads((package_root / "TEST_MANIFEST.json").read_bytes())
        pinned_paths = sorted({pin["path"] for key in ["source_inputs", "candidate_files"] for pin in inputs[key]}
                              | {pin["path"] for pin in manifest["package_files"]}
                              | set(inputs["host_dependency_paths"])
                              | {inputs[key] for key in ["changed_path", "overlay_path", "baseline_peer_path", "prepared_test_path", "test_entry"]}
                              | {"tests/focused/candidate_manifest.json", "tests/focused/source_binding.json",
                                 "project.godot", "PREPARATION_RECEIPT.json"})
        for name in pinned_paths:
            relative_path = relative(name)
            for flavor, factory, base in [("windows", PureWindowsPath, "E:/owned/source"),
                                          ("posix", PurePosixPath, "/owned/source")]:
                directory = factory(base)
                joined = directory / relative_path
                check(joined.relative_to(directory).as_posix() == name,
                      suite + " " + flavor + " actual pinned prepare path stays contained " + name)
        static = getattr(args, suite + "_tests") / "check_static.py"
        static_source = static.read_bytes()
        check(b"snapshot(args.source_root) == source_before and snapshot(args.candidate_root) == candidate_before" in static_source,
              suite + " native snapshot keys compared only before/after on same host")
        bindings.append({"suite": suite, "v2_helper_sha256": sha(before), "v3_helper_sha256": sha(after),
                         "prepare_sha256": sha(source), "tests_check_static_sha256": sha(static_source)})
    result = {"status": "PASSED_PATH_SEMANTICS_ONLY_NOT_NATIVE_WINDOWS_EXECUTION", "count": len(checks),
              "checks": checks, "cases": cases, "bindings": bindings, "godot_invocations": 0,
              "preserved": ["strict single-file list equality", "strict production byte equality", "LF Git flags",
                            "production patch/overlay", "original driver and fixture", "prepare and tests algorithms"],
              "limits": "PureWindowsPath/PurePosixPath semantics plus actual extracted pinned expressions; not Windows filesystem, reparse, symlink privilege, Godot or GUI acceptance"}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "count": len(checks), "cases": len(cases), "Godot": 0}))


if __name__ == "__main__":
    main()
