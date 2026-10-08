#!/usr/bin/env python3
"""Read-only bounded artifact checks. Not a Godot parser or runtime test."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / "MANIFEST.json").read_text(encoding="utf-8"))
checks = []

def check(value, name):
    checks.append({"name": name, "ok": bool(value)})

for row in manifest["files"]:
    raw = (ROOT / row["path"]).read_bytes()
    check(len(raw) == row["bytes"] and hashlib.sha256(raw).hexdigest() == row["sha256"], "artifact bytes: " + row["path"])
driver = (ROOT / manifest["new_driver"]).read_text(encoding="utf-8")
check(driver.startswith('extends "res://tests/actor_status_death/frozen_finite_main.gd"'), "inherits exact49 Main helpers")
check("MAX_COMMITS = 8" in driver and "for bottle in range(2)" in driver and "for tick in range(3)" in driver, "bounded two bottles / six actual owner actions")
check(not re.search(r'\b(?:fresh|successful_sequence|successful_self|make_engine|load_data|randi|seed|randomize)\s*\(', driver), "no alternate engine, fabricated save or success search calls")
check(not re.search(r'\.(?:_state|_rng|health|quantity)(?:\.[A-Za-z_][A-Za-z0-9_]*)*\s*=(?!=)|\[\s*[\'\"](?:health|current|quantity)[\'\"]\s*\]\s*=(?!=)', driver), "no direct authority writes")
check('if not F.applied(applied):' in driver and 'inconclusive_reason =' in driver and '3 if outcome == "INCONCLUSIVE"' in driver, "actual RNG non-witness is inconclusive")
check('app.playtest.core.commit(receipt.action_id, receipt.stage_hash)' in driver and driver.count('C.bytes(app.playtest.save_data()) == terminal') >= 5, "real receipt duplication and terminal save-byte assertions")
check('request.get("code") == "ACTOR_DOWNED"' in driver and 'not app.apply_playtest_reply(stale_proposal)' in driver and 'not app.apply_playtest_reply(stale_assessment)' in driver, "death request and late-data rejection assertions")
check('var stored: bool = out.store_string(' in driver and 'var write_error: Error = out.get_error()' in driver and 'var flush_error: Error = out.get_error()' in driver and driver.index('out.flush()') < driver.index('var flush_error:') < driver.index('out.close()') and driver.count('out.close()') == 1 and 'if not stored or write_error != OK or flush_error != OK:' in driver, "report write/flush errors fail before success exit; one close")
check(all(not row.get("deployment_path", "").startswith(("view/", "core/", "main", "README")) for row in manifest["files"]), "test-only deployment paths")
result = {"schema":"status_player_poison_static/v1", "ok":all(row["ok"] for row in checks), "checks":checks, "godot_parse":"NOT_RUN", "runtime":"NOT_RUN", "death_witness":"NOT_RUN"}
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result["ok"] else 1)
