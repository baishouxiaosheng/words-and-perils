"""Reproduce this bounded, read-only audit; paths/types only for privacy findings."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def function_map(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    starts = [(i, re.match(r"(?:static )?func\s+(\w+)", line)[1])
              for i, line in enumerate(lines) if re.match(r"(?:static )?func\s+(\w+)", line)]
    functions = {}
    for j, (i, name) in enumerate(starts):
        end = starts[j + 1][0] if j + 1 < len(starts) else len(lines)
        text = "\n".join(lines[i:end]).strip()
        body = re.sub(r"^(?:static )?func .+?\)\s*(?:->[^:]+)?:", "", text, count=1).strip()
        functions[name] = {"line": i + 1, "span": end - i, "text": text, "body": body}
    return lines, functions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--formal", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    tracked = subprocess.check_output(["git", "-C", str(args.repo), "ls-files", "-z"]).decode().split("\0")[:-1]
    paths = ["main.gd", "view/actor_action_entry/view_adapter.gd", "view/actor_status_entry_v1/view_adapter.gd"]
    metrics, maps = [], []
    for name in paths:
        path = args.formal / name
        lines, functions = function_map(path)
        maps.append(functions)
        metrics.append({"path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "lines": len(lines), "functions": len(functions),
                        "top_level_variables": sum(bool(re.match(r"var ", line)) for line in lines),
                        "largest": [{"name": n, "line": f["line"], "span": f["span"]}
                                    for n, f in sorted(functions.items(), key=lambda item: -item[1]["span"])[:5]]})
    a, b = maps[1:]
    same = sorted(n for n in a.keys() & b.keys() if a[n]["body"] == b[n]["body"])
    whole = sorted(n for n in a.keys() & b.keys() if a[n]["text"] == b[n]["text"])
    findings = []
    for name in tracked:
        path = args.repo / name
        if re.search(r"(^|/)(\.godot|__pycache__|node_modules|bin|obj)(/|$)|\.(pyc|tmp)$", name):
            findings.append({"path": name, "type": "generated_or_cache_path_review"})
        if re.search(r"(^|/)(\.env(?:\..*)?|credentials(?:\.json)?|id_rsa|id_ed25519)$|\.(pfx|pem|key)$", name):
            findings.append({"path": name, "type": "credential_filename_review"})
        if path.suffix.lower() not in {".py", ".ps1", ".json", ".md", ".gd", ".txt", ".log"}:
            continue
        if path.stat().st_size > 2 * 1024 * 1024:
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"[A-Z]:\\\\|/home/|/Users/", content):
            findings.append({"path": name, "type": "machine_path_review"})
        if re.search(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{30,}|\bsk-[A-Za-z0-9_-]{32,}", content):
            findings.append({"path": name, "type": "possible_secret_review"})
    result = {"source_commit": subprocess.check_output(["git", "-C", str(args.repo), "rev-parse", "HEAD"], text=True).strip(),
              "formal_release": "e8ec5db0341f8b4a8aaa0a933e5968c33440c9da",
              "method": "Top-level GDScript function boundaries, spans include trailing blank/comment lines; body strips declaration and outer whitespace, includes inline body. Heuristic privacy scan, not a secret-free certification.",
              "metrics": metrics, "same_named_bodies": len(same),
              "same_body_lines": sum(len(a[n]["body"].splitlines()) for n in same),
              "identical_whole_functions": len(whole),
              "identical_whole_function_lines": sum(len(a[n]["text"].splitlines()) for n in whole),
              "duplicates": [{"function": n, "action_line": a[n]["line"], "status_line": b[n]["line"]} for n in same],
              "tracked_files": len(tracked), "findings": findings,
              "scan_limits": "Tracked files only; content scan limited to listed text extensions <=2 MiB, no credentials or unrelated directories read, no values printed."}
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"same_named_bodies": len(same), "identical_whole_functions": len(whole),
                      "finding_types": {kind: sum(f["type"] == kind for f in findings) for kind in sorted({f["type"] for f in findings})}}))


if __name__ == "__main__":
    main()
