"""Derive a read-only evidence inventory from one Git commit (Python 3.10+).

No checkout, network, engine, queue, adoption or evidence mutation. Unknown
relationships stay unknown; source statements are not new test results.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, timeout=60).stdout


def candidate_root(path):
    parts = path.split("/")
    return "/".join(parts[:3]) if len(parts) > 3 and parts[0] == "candidates" else None


def pairs_unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def facts(value, prefix=""):
    """Keep selected scalar claims with JSON paths, never arbitrary log bodies."""
    rows = []
    if isinstance(value, dict):
        for key, child in value.items():
            location = prefix + "/" + key.replace("~", "~0").replace("/", "~1")
            selected = (key in {"task_id", "owner", "owner_run_id", "status", "candidate_adopted",
                                "strict_pass", "runtime_checks", "checks", "passed", "count",
                                "gui_status", "screenshots", "video", "delivery_complete"}
                        or key.endswith("commit") or key in {"formal_source_map_sha256", "formal_main_sha256", "overlay_sha256"})
            if selected and isinstance(child, (str, int, bool)) and len(str(child)) <= 256:
                rows.append({"pointer": location, "value": child})
            elif key in {"functional_headless", "summary", "source_binding"} and isinstance(child, (dict, list)):
                rows.extend(facts(child, location))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            rows.extend(facts(child, prefix + "/" + str(i)))
    return rows


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def selected(path):
    name = path.rsplit("/", 1)[-1].lower()
    return (name.endswith(".json") and
            (any(word in name for word in ("manifest", "receipt")) or
             name in {"result.json", "task.json", "claim.json", "inputs.json", "test_summary.json"}
             or path.startswith("coordination/local-work/inbox/")))


def build(repo, ref):
    commit = git(repo, "rev-parse", "--verify", ref + "^{commit}").decode().strip()
    entries = {}
    for line in git(repo, "ls-tree", "-rz", commit).split(b"\0"):
        if line:
            meta, raw_path = line.split(b"\t", 1)
            mode, kind, oid = meta.decode().split()
            if kind == "blob":
                entries[raw_path.decode("utf-8")] = (mode, oid)
    roots = sorted({root for path in entries if (root := candidate_root(path))})
    records, issues = [], []
    for path, (mode, oid) in sorted(entries.items()):
        if not selected(path):
            continue
        if mode != "100644":
            issues.append({"path": path, "type": "non_regular_metadata"})
            continue
        raw = git(repo, "cat-file", "blob", oid)
        try:
            data = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=pairs_unique,
                              parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite")))
        except (ValueError, UnicodeError):
            issues.append({"path": path, "type": "invalid_json"})
            continue
        references = set()
        for value in strings(data):
            for root in roots:
                if value == root or root + "/" in value:
                    references.add(root)
        task = next((value for value in path.split("/") if value.startswith("WP-")), None)
        if isinstance(data, dict):
            task = data.get("task_id", task)
        records.append({"path": path, "blob": oid, "sha256": hashlib.sha256(raw).hexdigest(),
                        "task_id": task, "candidate_references": sorted(references),
                        "claims": facts(data)})
    candidates = []
    for root in roots:
        related = [r for r in records if r["path"].startswith(root + "/") or root in r["candidate_references"]]
        tasks = sorted({r["task_id"] for r in related if isinstance(r["task_id"], str)})
        task_records = [r for r in records if r["task_id"] in tasks]
        direct = [r for r in related if r["path"].startswith(root + "/")]
        receipts = [r["path"] for r in related if "adoption_receipt" in r["path"].lower()]
        evidence = {r["path"]: r for r in related + task_records}
        def claimed_fields(keys):
            return [{"source": r["path"], **claim} for r in evidence.values() for claim in r["claims"]
                    if claim["pointer"].rsplit("/", 1)[-1] in keys]
        candidates.append({"path": root, "task_ids": tasks,
                           "owners": claimed_fields({"owner", "owner_run_id"}),
                           "source_baselines": claimed_fields({"base_commit", "base_git_commit", "formal_release_commit", "candidate_commit"}),
                           "test_results": [r["path"] for r in evidence.values() if r["path"].rsplit("/", 1)[-1].upper() in {"RESULT.JSON", "TEST_SUMMARY.JSON"}],
                           "missing_fields": "Empty lists mean UNKNOWN, not unowned/untested/unadopted",
                           "metadata": [r["path"] for r in direct],
                           "task_evidence": sorted({r["path"] for r in related + task_records if not r["path"].startswith(root + "/")}),
                           "adoption": "REVIEW_RECEIPT_SCOPE" if receipts else "UNKNOWN_NO_LINKED_ADOPTION_RECEIPT",
                           "adoption_receipts": receipts,
                           "recovery": [p for p in sorted(entries) if p.startswith(root + "/") and
                                        (p.endswith(("prepare.py", "prepare_qa.py", "prepare_driver.py", "apply_candidate.py")) or
                                         "/tools/restore_" in p)]})
    return {"schema": "wp-evidence-index/v1", "source_commit": commit,
            "scope": "Tracked metadata only; candidate roots = candidates/<family>/<revision>; no runtime or adoption inference",
            "candidate_count": len(candidates), "candidates": candidates,
            "release_receipts": [p for p in sorted(entries) if p.startswith("updates/") and p.endswith("adoption_receipt.json")],
            "recovery_entry": "tools/restore_v30.py; read docs/development/WORKFLOW.md before use",
            "records": records, "issues": issues}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", required=True, help="Commit or ref, resolved once")
    parser.add_argument("--output", required=True, type=Path, help="New JSON file; parent must exist")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output already exists; choose a new file")
    result = build(args.repo, args.ref)
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"source_commit": result["source_commit"], "candidates": result["candidate_count"],
                      "records": len(result["records"]), "issues": len(result["issues"])}))
    return 1 if result["issues"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
