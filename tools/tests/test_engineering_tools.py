"""Offline regression for index provenance, unknown states and path refactor."""
import ast
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("evidence_index", ROOT / "tools/build_evidence_index.py")
index = importlib.util.module_from_spec(spec)
spec.loader.exec_module(index)


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wp-index-test-")
        self.repo = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.run_git("init", "-q")
        self.write("candidates/demo/v1/MANIFEST.json", {"base_commit": "a" * 40, "status": "NOT_ADOPTED"})
        self.write("candidates/orphan/v1/MANIFEST.json", {})
        self.write("coordination/local-work/results/WP-TEST/TASK.json",
                   {"task_id": "WP-TEST", "inputs": [{"path": "candidates/demo/v1/MANIFEST.json"}]})
        self.write("coordination/local-work/results/WP-TEST/CLAIM.json",
                   {"task_id": "WP-TEST", "owner_run_id": "test-owner"})
        self.write("coordination/local-work/results/WP-TEST/attempt-001/RESULT.json",
                   {"task_id": "WP-TEST", "status": "failed", "candidate_adopted": False})
        self.commit()

    def run_git(self, *args):
        return index.git(self.repo, *args)

    def write(self, name, data):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def commit(self):
        self.run_git("add", "--", "candidates", "coordination")
        self.run_git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "-qm", "fixture")

    def test_commit_snapshot_ignores_uncommitted_claim(self):
        before = index.build(self.repo, "HEAD")
        self.write("candidates/demo/v1/MANIFEST.json", {"status": "ADOPTED"})
        self.assertEqual(before, index.build(self.repo, "HEAD"))

    def test_unknown_not_invented_and_result_joined(self):
        result = index.build(self.repo, "HEAD")
        demo, orphan = result["candidates"]
        self.assertEqual(demo["task_ids"], ["WP-TEST"])
        self.assertEqual(orphan["task_ids"], [])
        self.assertEqual(demo["adoption"], "UNKNOWN_NO_LINKED_ADOPTION_RECEIPT")
        self.assertTrue(any(p.endswith("RESULT.json") for p in demo["task_evidence"]))
        record = next(r for r in result["records"] if r["path"].endswith("RESULT.json"))
        self.assertIn({"pointer": "/status", "value": "failed"}, record["claims"])
        self.assertIn({"pointer": "/candidate_adopted", "value": False}, record["claims"])

    def test_receipt_link_does_not_imply_full_adoption(self):
        self.write("candidates/demo/v1/adoption_receipt.json", {"status": "limited"})
        self.commit()
        demo = index.build(self.repo, "HEAD")["candidates"][0]
        self.assertEqual(demo["adoption"], "REVIEW_RECEIPT_SCOPE")

    def test_duplicate_and_invalid_json_are_reported_without_content(self):
        for name, data in [("MANIFEST.json", '{"token":"secret", "token":"duplicate"}'),
                           ("TEST_MANIFEST.json", "not JSON")]:
            (self.repo / "candidates/demo/v1" / name).write_text(data)
        self.commit()
        result = index.build(self.repo, "HEAD")
        self.assertEqual(len(result["issues"]), 2)
        self.assertNotIn("secret", json.dumps(result))

    def test_output_no_overwrite(self):
        output = self.repo / "result.json"
        output.write_bytes(b"keep")
        process = subprocess.run(["python", str(ROOT / "tools/build_evidence_index.py"),
                                  "--repo", str(self.repo), "--ref", "HEAD", "--output", str(output)],
                                 capture_output=True)
        self.assertEqual(process.returncode, 2)
        self.assertEqual(output.read_bytes(), b"keep")


class PathRefactorTests(unittest.TestCase):
    def test_only_loop_extraction_ast_change(self):
        original = ast.parse((ROOT / "candidates/focused-display-path-regression/20261009-cloud-v3/regression.py").read_bytes())
        changed = ast.parse((ROOT / "tools/check_focused_paths.py").read_bytes())
        helper = next(n for n in changed.body if isinstance(n, ast.FunctionDef) and n.name == "check_allowlist_scenarios")
        changed.body.remove(helper)
        original.body.pop(0)
        changed.body.pop(0)
        class Inline(ast.NodeTransformer):
            def visit_Expr(self, node):
                if isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name) and node.value.func.id == helper.name:
                    return helper.body
                return node
        changed = Inline().visit(changed)
        self.assertEqual(ast.dump(original, include_attributes=False), ast.dump(changed, include_attributes=False))

    def test_actual_full_results_equal(self):
        args = []
        for suite, family in [("clock", "status-clock"), ("focus", "focus-location")]:
            for version in ["v2", "v3"]:
                args += ["--" + suite + "-" + version, "candidates/" + family + "-display/20261009-cloud-" + version]
            args += ["--" + suite + "-tests", "candidates/" + family + "-display-tests/20261009-cloud-v3"]
        with tempfile.TemporaryDirectory(prefix="wp-path-regression-") as temp:
            outputs = []
            for i, script in enumerate(["candidates/focused-display-path-regression/20261009-cloud-v3/regression.py",
                                       "tools/check_focused_paths.py"]):
                output = Path(temp) / (str(i) + ".json")
                subprocess.run(["python", script, *args, "--output", str(output)], cwd=ROOT,
                               check=True, capture_output=True, timeout=30)
                outputs.append(output.read_bytes())
            self.assertEqual(outputs[0], outputs[1])
            self.assertEqual(json.loads(outputs[0])["count"], 230)


if __name__ == "__main__":
    unittest.main()
