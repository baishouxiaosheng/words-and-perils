Publication note: this is the adopted v26 compatibility repair from v24. Historical candidate states retained in the review describe when each observation was recorded; the later adoption receipt establishes the frozen release. V25 remains withdrawn. Run `python3 tools/restore_repository.py` before Godot import.

# V26 vegetation lifecycle compatibility repair

V26 is an independent repair release based on stable V24. V25 remains withdrawn. Do not apply the withdrawn V25 increment.

V25 edited `whole_canopies.gd` for cache/lifecycle validation. Generated vegetation treats the complete original file SHA as a frozen asset recipe. That SHA also participates in asset-catalog and vegetation-context hashes, layout and stable IDs. Updating or accepting another hash would change old generated worlds. The lifecycle review followed live node consumers and normal coast tests, but missed this serialized hash consumer and the already available real equipment-save gate. The resulting V25 adoption was invalid and was withdrawn.

The repair preserves `whole_canopies.gd` byte-for-byte at V24 SHA `3426c4617148977022d23226ff858684c5b0a329bf72a24fb8129b106f48a86f`. The new `whole_canopies_loader.gd` extends it only for coast loading validation and verified manifest identity. It does not override mesh or LOD methods. Asset validators, catalog/planner, generated IDs and saved contracts are unchanged. Unknown hashes remain rejected; no save rewrite, tolerance or hash whitelist was added.

Verification on the exact production bytes adopted as V26: complete V24 asset catalog and 30 raw native buffers 33/33; lifecycle 63/63; real fallen-tree/support Main 61/61; actual C UI 98/98 and HUD 48/48. Three C UI PNGs and every RGBA pixel match V24. The original four native saves pass the existing 47-item equipment/enemy history gate, and the permanent gate adds four exact historical input SHA checks for 51/51. It preserves full source context, 22 plant IDs/layout, RNG, receipts, equipment history and JSON/disk round-trips, checks a new assessed ordinary swap, and rejects silently upgrading genuine V21 history.

The canonical production files are byte-identical to the independently reviewed candidate. Relabeling is not another engine run. Public evidence is in `artifacts/vegetation_compatibility_v26/adoption_receipt.json`; original and public evidence digests are mapped in `updates/v26/manifest.json`.

Permanent gates:
- `python3 tests/vegetation_compat/check_asset_pins.py .` fails before adoption if any of the four production recipe/material/license pins differ
- `tests/vegetation_compat/test_asset_catalog.gd` compares the complete frozen V24 catalog and thirty raw-buffer hashes; its packaged default also checks the frozen reference snapshot SHA
- `tests/vegetation_compat/test_real_legacy_saves.gd` uses the four exact archived native saves, then reuses the established complete equipment/admission/history gate
- Existing lifecycle, actual fallen/support, C UI and HUD tests remain required for lifecycle changes

Any future geometry recipe revision needs a new explicit versioned recipe and a tested reader/dispatcher while retaining the prior exact decoder. Do not edit a serialized recipe in place or merely update its expected hash. Source-only delivery and normal Godot import requirements remain unchanged. This fix does not establish a new RAM or FPS improvement; original fallback resources remain intentionally retained.
