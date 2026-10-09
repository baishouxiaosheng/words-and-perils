#!/usr/bin/env python3
"""Prove the production change is exactly one redundant scope field removal."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE_SHA = "3d63782da2542b533eddd6c18c90ee7185076b51a99977d0f148fce89f8104dd"
before = ROOT / "tests/runtime_ai_budget/baseline_scoped_engine.gd"
after = ROOT / "view/runtime_ai/scoped_engine.gd"
original = before.read_text()
old = '\n\t\t"selection":"All public actors/items/flags/story anchors, changed entities, selected entity, scene-aware actor/item/selection/explicit-coordinate neighborhoods. Negotiated creative context retains exact other-actor/item/settlement footprint/anchor cells without unrelated surrounding rings and omits the duplicate singular settlement alias; complete public cells can be expanded on request. No private source fields or RNG."}'
assert hashlib.sha256(before.read_bytes()).hexdigest() == BASELINE_SHA
assert original.count(old) == 1
expected = original.replace(old, "}").replace('Never guess.",}', 'Never guess."}')
expected = expected.replace('\tscoped["transport_scope"] =', '\t# Do not repeat the selection prose here: the scope policy/omissions below\n\t# describe the same projection. Diagnostic metadata also spends the byte cap.\n\tscoped["transport_scope"] =')
assert after.read_text() == expected, "Production change exceeded the approved metadata-only correction"
wrappers = [
    ("tests/settlement/test_settlement.gd", "settlement_report.json"),
    ("tests/runtime_ai/test_controller.gd", "controller_results.json"),
    ("tests/experimental/ai_gm_rebuilt/test_integration.gd", "integration_report.json"),
    ("tests/creative_actions/test_core.gd", "creative_core_unused.json"),
]
for source, report in wrappers:
    src = ROOT / source
    wrapper = ROOT / "tests/runtime_ai_budget" / ("regression_" + src.name)
    text = src.read_text()
    for old_path in ["res://artifacts/settlement_20261003/rules_report.json", "res://artifacts/runtime_ai_20261003/controller_results.json", "res://artifacts/ai_gm_rebuilt/test_report.json"]:
        text = text.replace(old_path, "res://artifacts/runtime_ai_budget_20261004/" + report)
    if "creative" in source:
        text = text.replace("res://artifacts/creative_actions_20261003", "res://artifacts/runtime_ai_budget_20261004/creative_core")
    assert wrapper.read_text() == text, "Regression assertions changed: " + source

report = {"passed": True, "baseline_sha256": BASELINE_SHA,
          "production_path": "view/runtime_ai/scoped_engine.gd",
          "production_sha256": hashlib.sha256(after.read_bytes()).hexdigest(),
          "runtime_change": "Remove only redundant transport_scope.selection prose; add source comments",
          "transport_delta_bytes": -425, "save_schema_changed": False,
          "cap_bytes": 65536, "regression_wrapper_count": len(wrappers)}
print(json.dumps(report, indent=2))
