#!/usr/bin/env python3
"""Read-only, offline checks for the v28 public UI-safety source package.

Requires Python 3.10+ standard library. Run restore_large_assets.py first.
Does not launch Godot or contact a
provider. Static checks cannot establish engine, visual or live-service behavior.
The semantic witnesses below were calculated from the accepted v21 baseline,
omitting only the stated publication-only provenance fields.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FONT_SHA = "b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a"
SETTLEMENT_SAVE_SHA = "d483575a172b21f964a97e3de6c72d5e3b2d3cb73b9a4b2b255367e760a123f5"
SETTLEMENT_SEMANTIC_SHA = "77f072dcd8c233475d280d6c9fd26174df906209d5e528d5a3ec3aeed5d3be7b"
RECEIPT_SEMANTIC_SHA = "4304af49433042c3152632aec72454337917731dff0650c8bb16a78af03c4945"
checks = {}


def check(name, condition):
    checks[name] = bool(condition)
    if not condition:
        raise ValueError(name)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def semantic_sha(value):
    return sha(json.dumps(value, ensure_ascii=False, sort_keys=True,
                          separators=(",", ":")).encode("utf-8"))


def read_json(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def resource(path):
    if not path.startswith("res://"):
        raise ValueError("Expected project resource")
    resolved = (ROOT / path[6:]).resolve()
    if not resolved.is_relative_to(ROOT):
        raise ValueError("Resource escapes project")
    return resolved


def gd_constant(text, name):
    match = re.search(r"^const " + re.escape(name) + r'\s*:?=\s*"([^"]+)"',
                      text, re.MULTILINE)
    if not match:
        raise ValueError("Missing GDScript constant: " + name)
    return match.group(1)


def strip_provenance_paths(value):
    if isinstance(value, dict):
        return {key: strip_provenance_paths(item) for key, item in value.items()
                if key != "path"}
    if isinstance(value, list):
        return [strip_provenance_paths(item) for item in value]
    return value


def run_json_test(relative):
    result = subprocess.run([sys.executable, "-B", str(ROOT / relative)],
                            cwd=ROOT, capture_output=True, text=True,
                            timeout=120, check=True)
    return json.loads(result.stdout)


def verify_binary_resources():
    manifest = read_json("resource_packs/manifest.json")
    check("resource_pack_schema", manifest["schema"] == "words-and-perils-resource-packs/v1")
    combined = hashlib.sha256()
    total, part_names = 0, set()
    for row in manifest["parts"]:
        name = row["path"]
        if name in part_names or not name.startswith("resource_packs/"):
            raise ValueError("Invalid or duplicate resource part")
        part_names.add(name)
        data = resource("res://" + name).read_bytes()
        if len(data) != row["size"] or sha(data) != row["sha256"]:
            raise ValueError("Resource part size/checksum mismatch: " + name)
        combined.update(data)
        total += len(data)
    check("resource_parts_and_combined_archive",
          bool(part_names) and total == manifest["archive_size"]
          and combined.hexdigest() == manifest["archive_sha256"])
    names, restored_bytes = set(), 0
    for row in manifest["files"]:
        name = row["path"]
        if name in names:
            raise ValueError("Duplicate binary resource: " + name)
        names.add(name)
        path = resource("res://" + name)
        if not path.is_file():
            raise ValueError("Resource not restored: " + name
                             + "; run python3 tools/restore_large_assets.py first")
        if path.stat().st_size != row["size"] or sha(path.read_bytes()) != row["sha256"]:
            raise ValueError("Restored binary size/checksum mismatch: " + name)
        restored_bytes += row["size"]
    check("every_restored_binary_matches_manifest", len(names) == 953)
    font_name = "assets/NotoSansCJK-Regular.ttc"
    font_rows = [row for row in manifest["files"] if row["path"] == font_name]
    check("font_accepted_identity", len(font_rows) == 1
          and font_rows[0]["sha256"] == FONT_SHA and font_rows[0]["size"] == 19484784)
    check("restored_font_integrity", sha((ROOT / font_name).read_bytes()) == FONT_SHA)
    helper = ROOT / "tools/restore_large_assets.py"
    compile(helper.read_text(encoding="utf-8"), helper.name, "exec")
    check("restore_helper_syntax", True)
    return {"binary_resources": len(names), "binary_bytes": restored_bytes,
            "resource_parts": len(part_names), "resource_archive_bytes": total}


def verify():
    binary_details = verify_binary_resources()
    fieldbook = read_json("updates/v24/manifest.json")
    check("fieldbook_delta_version", fieldbook.get("version") == "v24-fieldbook-ui")
    canonical_pins = dict(fieldbook["canonical_pins"])
    previous = read_json("updates/v27/manifest.json")
    current = read_json("updates/v28/manifest.json")
    previous_rows = {row["path"]: row for row in previous["files"]}
    current_rows = {row["path"]: row for row in current["files"]}
    check("v27_frozen_production_count", len(previous["production_pins"]) == 50)
    check("v28_frozen_production_count", len(current["production_pins"]) == 20)
    check("v27_only_frozen_main_supersedes_fieldbook",
          set(previous["production_pins"]) & set(canonical_pins) == {"main.gd"}
          and previous_rows["main.gd"]["before_sha256"] == "e346071dd0149805f96ed53d18fda4f28223354b121fb6831f66c1c7b862eec4"
          and previous_rows["main.gd"]["sha256"] == "1db6386f9c53f7f0946f84dae0b81a61b35420447b3b1035896678d86e367c4c")
    check("v28_only_frozen_main_supersedes_v27",
          set(current["production_pins"]) & set(previous["production_pins"]) == {"main.gd"}
          and set(current["production_pins"]) & set(canonical_pins) == {"main.gd"}
          and current_rows["main.gd"]["before_sha256"] == "1db6386f9c53f7f0946f84dae0b81a61b35420447b3b1035896678d86e367c4c"
          and current_rows["main.gd"]["sha256"] == "2b05911a1bcde48b10a54e8d1475ef62c66aea84ff8c7f5b7cdc3052eaf9fc93")
    effective_pins = {}
    for update in [previous, current]:
        rows = {row["path"]: row for row in update["files"]}
        for name, expected in update["production_pins"].items():
            row = rows[name]
            check(update["version"] + "_manifest_pin_" + name, row["sha256"] == expected)
            if name in effective_pins:
                check("v28_exact_superseded_preimage_" + name,
                      row["before_sha256"] == effective_pins[name])
            effective_pins[name] = expected
            if name in canonical_pins:
                check(update["version"] + "_fieldbook_preimage_" + name,
                      row["before_sha256"] == canonical_pins[name])
                canonical_pins[name] = expected
    safety = read_json("updates/v28-ui-safety/manifest.json")
    safety_rows = {row["path"]: row for row in safety["files"]}
    name = "view/generated_natural_coast_entry/view.gd"
    check("public_ui_safety_only_entry_view",
          set(safety["production_pins"]) == {name}
          and safety_rows[name]["before_sha256"] == "c0876b37414ce8e368e771d4352eaf256524331de278332c220d30db180e521c"
          and safety_rows[name]["sha256"] == "0b41c8536c048adc12243972a5cfa81ccaa9c978446fa0c5ce50dc3624ec384f"
          and effective_pins[name] == safety_rows[name]["before_sha256"])
    effective_pins[name] = safety["production_pins"][name]
    authority_source = (ROOT / "view/generated_natural_coast_basic/authority_inputs.gd").read_text()
    authority_paths = re.findall(r'"(res://[^"\n]+)"', authority_source)
    check("public_ui_safety_keeps_all_168_authority_inputs",
          len(authority_paths) == 168 and "res://" + name not in authority_paths
          and set(safety["production_pins"]).isdisjoint({p[6:] for p in authority_paths}))
    check("v27_v28_effective_69_production_pins", len(effective_pins) == 69 and all(
        (ROOT / name).is_file() and sha((ROOT / name).read_bytes()) == expected
        for name, expected in effective_pins.items()))
    check("fieldbook_all_98_current_exact_entries", len(canonical_pins) == 98 and all(
        (ROOT / name).is_file() and sha((ROOT / name).read_bytes()) == expected
        for name, expected in canonical_pins.items()))
    catalog = read_json("data/catalog.json")
    check("status_catalog_168_definitions", catalog.get("schema_version") == "status_catalog/v1"
          and len(catalog.get("definitions", [])) == 168)
    pngs = [name for name in canonical_pins if name.endswith(".png")]
    check("fieldbook_21_png_import_pairs", len(pngs) == 21 and all(
        (ROOT / (name + ".import")).is_file()
        and "process/fix_alpha_border=false" in (ROOT / (name + ".import")).read_text()
        for name in pngs))

    bundle = read_json("artifacts/world_bundle_20261002/manifest.json")
    closure = run_json_test("tests/playable_build/runtime_dependency_closure.py")
    check("runtime_manifest_hash_closure", closure["runtime_files"] == 875)

    receipt_script = (ROOT / "view/integrated_ecology_world/performance_variant/"
                      "source_receipt.gd").read_text(encoding="utf-8")
    receipt_path = gd_constant(receipt_script, "PATH")
    receipt_hash = sha(resource(receipt_path).read_bytes())
    receipt_entry = bundle["runtime"]["historical_ecology_receipt"]
    check("receipt_source_and_bundle_pin", receipt_entry["path"] == receipt_path
          and receipt_entry["sha256"] == receipt_hash
          and gd_constant(receipt_script, "SHA") == receipt_hash)
    receipt = json.loads(resource(receipt_path).read_text(encoding="utf-8"))
    check("receipt_semantics_excluding_provenance_paths",
          semantic_sha(strip_provenance_paths(receipt)) == RECEIPT_SEMANTIC_SHA)

    settlement_script = (ROOT / "view/playable_build/settlement_content.gd").read_text(
        encoding="utf-8")
    settlement_path = resource(gd_constant(settlement_script, "PATH"))
    check("settlement_redacted_file_integrity",
          sha(settlement_path.read_bytes()) == gd_constant(settlement_script, "FILE_SHA"))
    check("settlement_original_save_identity",
          gd_constant(settlement_script, "SHA") == SETTLEMENT_SAVE_SHA
          and 'FileAccess.get_sha256(PATH) != FILE_SHA' in settlement_script
          and '"content_sha256":SHA' in settlement_script
          and 'value.content_sha256!=SHA' in settlement_script)
    settlement = json.loads(settlement_path.read_text(encoding="utf-8"))
    check("settlement_public_provenance_label",
          settlement["scale_policy"].pop("source") == "project-scale-policy")
    check("settlement_semantics_excluding_provenance_label",
          semantic_sha(settlement) == SETTLEMENT_SEMANTIC_SHA)

    city = run_json_test("tests/city_lod/test_asset_contract.py")
    check("city_mesh_hash_and_geometry_contract", city["passed"] and city["checks"] == 129)

    def available(path):
        return path.is_file()

    queue, seen = [ROOT / "main.gd"], set()
    active_resources = {ROOT / "main.tscn"}
    load_pattern = r'(?:preload|load)\(\s*["\'](res://[^"\']+)["\']\s*\)'
    extends_pattern = r'extends\s+["\'](res://[^"\']+)["\']'
    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.add(path)
        source = path.read_text(encoding="utf-8")
        for reference in re.findall(load_pattern, source) + re.findall(extends_pattern, source):
            target = resource(reference)
            active_resources.add(target)
            if not available(target):
                raise ValueError("Missing active resource: " + reference)
            if target.suffix == ".gd":
                queue.append(target)
    check("active_exact_load_preload_extends_closure", len(seen) == 300)
    for face in ("Regular", "Bold"):
        check("dynamic_serif_font_" + face,
              (ROOT / ("assets/fonts/MistbankSerifUI-" + face + ".otf")).is_file())

    imports = list(ROOT.rglob("*.import"))
    for path in imports:
        text = path.read_text(encoding="utf-8")
        sources = re.findall(r'^source_file="(res://[^"]+)"$', text, re.MULTILINE)
        if len(sources) != 1 or not available(resource(sources[0])):
            raise ValueError("Invalid import source: " + str(path.relative_to(ROOT)))
        for reference in re.findall(r'"(res://[^"]+)"', text):
            if not reference.startswith("res://.godot/") and not available(resource(reference)):
                raise ValueError("Missing import dependency: " + reference)
    check("import_source_resource_closure", bool(imports))
    inactive_scene_gaps = []
    for path in list(ROOT.rglob("*.tscn")) + list(ROOT.rglob("*.tres")):
        for reference in re.findall(r'\bpath="(res://[^"]+)"', path.read_text(encoding="utf-8")):
            if not available(resource(reference)):
                if path in active_resources or path.suffix == ".tres":
                    raise ValueError("Missing active scene/resource dependency: " + reference)
                inactive_scene_gaps.append({"scene": str(path.relative_to(ROOT)),
                                            "missing_reference": reference})
    check("active_scene_and_material_exact_paths", True)
    return {"runtime_files": closure["runtime_files"], "runtime_bytes": closure["bytes"],
            "city_asset_assertions": city["checks"], "active_scripts": len(seen),
            "import_files": len(imports), **binary_details,
            "inactive_legacy_scene_gaps": inactive_scene_gaps,
            "additional_C_binary_resources": 21,
            "scope": "offline static checks only; Godot and provider tests not run"}


if __name__ == "__main__":
    try:
        details = verify()
    except (OSError, ValueError, KeyError, TypeError,
            subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "checks": checks, "error": str(error)}, indent=2))
        raise SystemExit(1)
    print(json.dumps({"ok": True, "checks": checks, **details}, indent=2))
