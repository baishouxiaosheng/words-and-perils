"""Python/Git-only regression for the two focused display candidate helpers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def describe(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "CRLF": data.count(b"\r\n"), "LF": data.count(b"\n")}


def snapshot(root):
    return {str(p.relative_to(root)): describe(p.read_bytes()) for p in root.rglob("*") if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for suite in ["clock", "focus"]:
        for role in ["v1", "v2", "source"]:
            parser.add_argument("--" + suite + "-" + role, type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True,
                        help="New owned output directory; all replay bytes persist")
    args = parser.parse_args()
    roots = {suite: {role: getattr(args, suite + "_" + role).resolve()
                     for role in ["v1", "v2", "source"]} for suite in ["clock", "focus"]}
    output = args.work_root.absolute()
    assert not output.exists(), "Refuse existing regression output"
    for group in roots.values():
        for root in group.values():
            assert root.is_dir() and not root.is_symlink()
            assert output != root and root not in output.parents and output not in root.parents
    before_inputs = {suite: {role: snapshot(root) for role, root in group.items()}
                     for suite, group in roots.items()}
    output.mkdir(parents=True)
    checks = []

    def check(ok, label):
        checks.append({"name": label, "passed": bool(ok)})
        if not ok:
            raise AssertionError(label)

    # Only these inherited variables are needed; never copy credentials/config secrets.
    env = {k: os.environ[k] for k in
           ["PATH", "SystemRoot", "SYSTEMROOT", "ComSpec", "TEMP", "TMP", "LANG", "LC_ALL"]
           if k in os.environ}
    env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_COUNT": "0",
                "GIT_CONFIG_GLOBAL": str(output / "owned.gitconfig")})
    git_lf = ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf"]
    cases = []
    for config_name, config in [
            ("autocrlf-true-only", "[core]\n\tautocrlf = true\n"),
            ("autocrlf-true-eol-crlf", "[core]\n\tautocrlf = true\n\teol = crlf\n")]:
        (output / "owned.gitconfig").write_bytes(config.encode())
        probe = subprocess.run(["git", "config", "--get", "core.autocrlf"],
                               env=env, cwd=output, capture_output=True)
        check(probe.returncode == 0 and probe.stdout.strip() == b"true", config_name + " owns true config")
        probe = subprocess.run(git_lf + ["config", "--get", "core.autocrlf"],
                               env=env, cwd=output, capture_output=True)
        check(probe.returncode == 0 and probe.stdout.strip() == b"false", config_name + " command override false")
        probe = subprocess.run(git_lf + ["config", "--get", "core.eol"],
                               env=env, cwd=output, capture_output=True)
        check(probe.returncode == 0 and probe.stdout.strip() == b"lf", config_name + " command override LF")
        for suite, group in roots.items():
            v1, v2, source = [group[k] for k in ["v1", "v2", "source"]]
            change = json.loads((v2 / "MANIFEST.json").read_bytes())["changed_files"][0]
            baseline = (source / change["path"]).read_bytes()
            expected = (v2 / change["overlay_path"]).read_bytes()
            patch_bytes = (v2 / "CHANGE.patch").read_bytes()
            prefix = config_name + "/" + suite
            check((v1 / "CHANGE.patch").read_bytes() == patch_bytes, prefix + " production patch unchanged")
            check((v1 / change["overlay_path"]).read_bytes() == expected, prefix + " overlay unchanged")
            evidence = output / config_name / suite
            evidence.mkdir(parents=True)
            (evidence / "before.gd").write_bytes(baseline)
            (evidence / "expected.gd").write_bytes(expected)
            (evidence / "CHANGE.patch").write_bytes(patch_bytes)
            replay = {}
            for fixed in [False, True]:
                name = "fixed" if fixed else "old"
                cwd = evidence / name
                target = cwd / change["path"]
                target.parent.mkdir(parents=True)
                target.write_bytes(baseline)
                commands = []
                for flags in [["--check"], []]:
                    command = (git_lf if fixed else ["git"]) + ["apply"] + flags + [str(evidence / "CHANGE.patch")]
                    run = subprocess.run(command, cwd=cwd, env=env, capture_output=True)
                    check(run.returncode == 0, prefix + " " + name + " Git " + str(flags) + " exit0")
                    commands.append({"argv": command[:-1] + ["HASH_BOUND_PATCH"],
                                     "exit_code": run.returncode,
                                     "stdout": run.stdout.decode("utf-8", errors="replace"),
                                     "stderr": run.stderr.decode("utf-8", errors="replace")})
                actual = target.read_bytes()
                (evidence / (name + "-actual.gd")).write_bytes(actual)
                replay[name] = {**describe(actual), "actual_equals_expected": actual == expected,
                                "commands": commands}
                check((actual == expected) if fixed else (actual != expected and b"\r\n" in actual),
                      prefix + (" fixed exact byte equality" if fixed else " old real CRLF byte mismatch"))
            old = subprocess.run([sys.executable, str(v1 / "check_static.py"), "--restored-root", str(source)],
                                 env=env, cwd=output, capture_output=True)
            check(old.returncode != 0 and b"AssertionError: actual patch replay" in old.stderr,
                  prefix + " original helper actually fails strict replay assertion")
            fixed = subprocess.run([sys.executable, str(v2 / "check_static.py"), "--restored-root", str(source)],
                                   env=env, cwd=output, capture_output=True)
            check(fixed.returncode == 0, prefix + " v2 helper exit0")
            result = json.loads(fixed.stdout)
            check(result["count"] == (24 if suite == "clock" else 20) and
                  all(c["passed"] for c in result["checks"]) and
                  result["godot_parses"] == result["runtime_runs"] == 0,
                  prefix + " original static checks all preserved")
            case = {"case": prefix, "before": describe(baseline), "expected": describe(expected),
                    "patch": describe(patch_bytes), "replay": replay,
                    "original_helper": {"exit_code": old.returncode,
                                        "failure": next(line for line in old.stderr.decode().splitlines()
                                                        if line.startswith("AssertionError:"))},
                    "v2_helper": {"exit_code": fixed.returncode, "result": result}}
            (evidence / "CASE.json").write_text(json.dumps(case, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            cases.append(case)
    # A hash-bound wrong patch is never accepted. Mutate only a disposable candidate copy,
    # retain its actual replay bytes after the helper's TemporaryDirectory has been removed.
    failures = []
    for suite, group in roots.items():
        case_root = output / "strict-negative" / suite
        case_root.mkdir(parents=True)
        copied = case_root / "candidate"
        shutil.copytree(group["v2"], copied)
        patch = copied / "CHANGE.patch"
        old_text, new_text = (("计时说明：", "回放负例：") if suite == "clock"
                              else ("选中地格：", "回放负例："))
        data = patch.read_bytes()
        check(old_text.encode() in data, suite + " negative fixture patch token found")
        patch.write_bytes(data.replace(old_text.encode(), new_text.encode()))
        retained = case_root / "retained"
        retained.mkdir()
        run = subprocess.run([sys.executable, str(copied / "check_static.py"),
                              "--restored-root", str(group["source"]), "--replay-evidence-root", str(retained)],
                             cwd=output, env=env, capture_output=True)
        check(run.returncode != 0 and b"AssertionError: actual patch replay" in run.stderr,
              suite + " v2 still refuses wrong replay by original strict assertion")
        children = list(retained.iterdir())
        check(len(children) == 1 and children[0].is_dir(), suite + " one persistent failure evidence child")
        saved = children[0]
        diagnostic = json.loads((saved / "DIAGNOSIS.json").read_bytes())
        check({p.name for p in saved.iterdir()} ==
              {"before.gd", "expected.gd", "actual.gd", "CHANGE.patch", "DIAGNOSIS.json"},
              suite + " all original failure byte files survive helper exit")
        check(diagnostic["error_type"] == "AssertionError" and
              diagnostic["actual_equals_expected"] is False and
              diagnostic["actual"] == describe((saved / "actual.gd").read_bytes()) and
              diagnostic["expected"] == describe((saved / "expected.gd").read_bytes()) and
              diagnostic["actual"]["CRLF"] == 0 and
              all(c["exit_code"] == 0 for c in diagnostic["commands"]) and
              diagnostic["godot_invocations"] == 0, suite + " retained diagnostic equals exact bytes")
        # Deterministic public evidence location; retain the original owned child as well.
        public_saved = case_root / "evidence"
        shutil.copytree(saved, public_saved)
        failures.append({"suite": suite, "exit_code": run.returncode,
                         "evidence_relative": str(public_saved.relative_to(output)),
                         "diagnostic": diagnostic})
    check(before_inputs == {suite: {role: snapshot(root) for role, root in group.items()}
                            for suite, group in roots.items()}, "all original source/v1/v2 inputs unchanged")
    version = subprocess.run(["git", "--version"], cwd=output, env=env, capture_output=True, check=True)
    result = {"status": "PASSED_PYTHON_GIT_ONLY", "git_version": version.stdout.decode().strip(),
              "platform": sys.platform, "checks": checks, "count": len(checks), "cases": cases,
              "strict_negative_cases": failures, "system_user_config_read_or_written": False,
              "godot_invocations": 0, "frozen_task_retries": 0,
              "original_windows_cause": "unproven: original temporary replay bytes were deleted; cloud reproduction only"}
    (output / "RESULT.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "count": len(checks), "cases": len(cases),
                      "strict_negative_cases": len(failures), "git_version": result["git_version"],
                      "godot_invocations": 0}))


if __name__ == "__main__":
    main()
