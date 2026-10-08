#!/usr/bin/env python3
"""Source-only checks. This does not parse or execute GDScript."""
from pathlib import Path
import difflib
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
ENGINE = ROOT / "overlay/core/ai_gm_rebuilt/engine.gd"
TEST = ROOT / "overlay/tests/t03_raw_readback/test_save_file.gd"
PROBE = ROOT / "overlay/tests/t03_raw_readback/io_probe.gd"
BASE_SHA = "cb707722b1d28534615257cb9873d1c66ce9924ac2ee5ebdc2d1d2a46b09fdc3"
BASE_METHOD = "func save_file(path: String) -> Dictionary:\n\tif not _initial_error.is_empty(): return ready()\n\tvar temporary := path + \".tmp\"\n\tvar file := FileAccess.open(temporary, FileAccess.WRITE)\n\tif file == null: return C.fail(\"SAVE_FAILED\", \"Cannot write temporary save.\")\n\tvar stored: bool = file.store_string(C.bytes(save_data()))\n\tfile.flush()\n\tvar write_error: Error = file.get_error()\n\tfile.close()\n\tif not stored or write_error != OK: return C.fail(\"SAVE_FAILED\", \"Temporary save write failed.\")\n\tvar renamed: Error = DirAccess.rename_absolute(temporary, path)\n\tif renamed != OK: return C.fail(\"SAVE_FAILED\", \"Atomic save rename failed.\")\n\treturn {\"ok\": true}\n"
EXPECTED_ENGINE_SHA = "f609fbf0bf717568c2429578bf4cde3eecf9a7aa806546c1d75c8dabdb0a4ef5"
EXPECTED_METHOD_SHA = "30cc3607de346361a8073dc689e8d957281f33cbebe7a79683a4c23f5e44bcc7"
checks = []

def check(condition, label):
    checks.append({"check": label, "passed": bool(condition)})
    if not condition:
        raise AssertionError(label)

def sha(value):
    return hashlib.sha256(value).hexdigest()

raw = ENGINE.read_bytes()
source = raw.decode("utf-8")
first = source.index("func save_file(")
last = source.index("\nfunc load_file(", first)
method = source[first:last]
base = source[:first] + BASE_METHOD + source[last:]
test = TEST.read_text("utf-8")
probe = PROBE.read_text("utf-8")
check(sha(raw) == EXPECTED_ENGINE_SHA, "exact candidate engine bytes")
check(sha(method.encode()) == EXPECTED_METHOD_SHA, "exact candidate method bytes")
check(sha(base.encode()) == BASE_SHA, "all production bytes outside save_file unchanged")
check(sha(BASE_METHOD.encode()) == "a67af61429e9d9caef0b16b182682319389eb52600a1de5c85f74564051d811c", "exact existing Raw method preimage")
expected_patch = "".join(difflib.unified_diff(base.splitlines(True), source.splitlines(True), fromfile="a/core/ai_gm_rebuilt/engine.gd", tofile="b/core/ai_gm_rebuilt/engine.gd"))
check((ROOT / "RAW_READBACK.patch").read_text("utf-8") == expected_patch, "patch reproduces this one-method source delta")
with tempfile.TemporaryDirectory(prefix="patch_check_", dir=ROOT) as folder:
    temporary = Path(folder)
    target = temporary / "core/ai_gm_rebuilt/engine.gd"
    target.parent.mkdir(parents=True)
    target.write_bytes(base.encode("utf-8"))
    patched = subprocess.run(["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-i", str(ROOT / "RAW_READBACK.patch")], cwd=temporary, capture_output=True, text=True)
    check(patched.returncode == 0 and "fuzz" not in patched.stdout.lower() and "offset" not in patched.stdout.lower(), "patch applies to exact Raw preimage with zero fuzz and offset")
    check(sha(target.read_bytes()) == EXPECTED_ENGINE_SHA, "patch application produces exact candidate bytes")
check(method.count("C.bytes(save_data())") == 1 and method.index("encoded.to_utf8_buffer()") < method.index("FileAccess.open"), "freeze canonical UTF8 once before opening writer")
check('var stored: bool = file.store_string(encoded)' in method, "existing store bool is retained")
check(method.index("file.get_error()") < method.index("file.close()") < method.index("if not stored or write_error != OK:") < method.index("FileAccess.open(temporary, FileAccess.READ)"), "existing write failure gate and close precede readback")
check('if reader == null: return C.fail("SAVE_FAILED"' in method, "read-open failure refuses before rename")
check(method.count("reader.get_length() == expected.size() and reader.get_error() == OK") == 2, "initial and final exact length plus read-error gates")
check("mini(65536, expected.size() - offset)" in method, "read chunks bounded to 64 KiB")
check("read_error == OK and actual.size() == amount and actual == expected.slice(offset, offset + amount)" in method, "each chunk requires exact length, bytes and no read error")
check(method.index("reader.close()") < method.index("if not verified: return") < method.index("DirAccess.rename_absolute"), "reader closes and failed verification refuses before rename")
check(method.count("DirAccess.rename_absolute") == 1 and "remove_absolute" not in method and "file_exists" not in method, "one unchanged explicit replacement, no cleanup or alternate replacement path")
check("FileAccess.open(path," not in method, "destination is never opened for writing")
check(EXPECTED_ENGINE_SHA in test and EXPECTED_METHOD_SHA in test, "test freezes exact production file and method")
check('.replace("FileAccess.", "ProbeIO.").replace("DirAccess.", "ProbeIO.")' in test, "fault harness substitutes only backend identifiers")
check("const READ := 1" in probe and "const WRITE := 2" in probe, "fake backend models distinct read and write opens")
for label in ["late flush loss with stored true and stale OK", "late close loss with stored true and stale OK", "readback open failure", "staging truncated before readback", "readback length query reports error", "short read with stale OK", "reported read error despite full bytes", "same length content corruption", "length grows during verification", "bounded multi chunk UTF8 success", "tiny canonical object success"]:
    check(label in test, "prepared case: " + label)
check('destination preserved' in test and 'payload unchanged' in test and 'failed temporary retained, never deleted or promoted' in test, "failure cases assert original target, live payload and temporary retention")
check('writer closes on every opened path' in test and 'reader closes on every opened path' in test and 'closed reader before rename' in test, "tests assert both handles close before replacement")
check('read_65536' in test and 'crosses chunk boundary' in test and 'bounded read buffer' in test, "tests assert the multi-chunk boundary and read cap")
check("fsync(" not in source and "DirAccess.make_dir" not in method, "no native durability, lock or staging ownership mechanism added")
for path in [ENGINE, TEST, PROBE, ROOT / "RAW_READBACK.patch"]:
    contents = path.read_bytes()
    check(b"\r" not in contents and not contents.startswith(b"\xef\xbb\xbf"), path.name + ": UTF8/LF without BOM")
credential_pattern = re.compile(rb"(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{32,})")
check(not any(credential_pattern.search(path.read_bytes()) for path in ROOT.rglob("*") if path.is_file()), "no common embedded credential-token or private-key format in package")
check(test.count('\tprobe_case(harness,') == 17 and test.count('\tstart_case(') == 5, "21 prepared cases: 17 injected probes, unready, 3 native happy/open-failure cases")
check(method.startswith("func save_file(path: String) -> Dictionary:"), "public save_file signature unchanged")
report = {"status": "source_static_passed", "checks": len(checks), "engine_sha256": EXPECTED_ENGINE_SHA, "method_sha256": EXPECTED_METHOD_SHA, "base_engine_sha256": BASE_SHA, "prepared_cases": 21, "godot_parse_runs": 0, "godot_test_runs": 0, "native_failure_reproductions": 0, "scope": "literal source and artifact checks only; not GDScript parsing or runtime proof", "results": checks}
print(json.dumps(report, ensure_ascii=False, indent=2))

