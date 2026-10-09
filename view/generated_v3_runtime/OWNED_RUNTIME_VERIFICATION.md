# V3 terrain integration verification · 2026-10-05 China

Accepted in the isolated playable v3 candidate, pending the parent-controlled adoption/package step. Owned runtime is eight files listed in OWNED_RUNTIME_ALLOWLIST.json. Source cleanup and the baseline native builder are preserved; only the final ground shader changed after gameplay admission/save tests.

- Runtime source/mesh/nav gate: 47/47, four seed-726381 cases across radius4/12 and both recipes. Whole mesh positions/indices unchanged by appearance, complete palette attributes, zero-level water and route samples checked.
- Independent geometric oracle: 1,060 anchors and 2,976 undirected edges; exact native buffers/hash, complete dry interval coverage, no admitted wet segment and no omitted dry neighbor segment in these fixtures. Oracle is owned by independent QA.
- Functional Main/save/restart and actual mouse QA are owned by gameplay and QA; this report does not replace their acceptance.
- Final lighting comparison: 28/28, both recipes at overview, normal12 and desert-relief12; six matched before/after pairs, actual1280×800. Exact unchanged source and native vertex/index/normal/COLOR/UV2 buffers. Root and independent QA inspected and accepted the single declared profile.
- Old lighting saturated96.77% and99.99% of native dry vertices for the two recipes. Continuous cool-sky/warm-sun response restores subtle relief, preserves flat-surface palette brightness, and both brightens and darkens slopes. No changed screenshot channel clipped to0 or255.
- Final shader SHA256: a8cc0932dc71e821ec692677ef74be9b501a7bb3581eabab530525b57b7bb231. Its bytes exactly match the shader compiled in the successful native comparison. The prior shader was41218bc80c62aab1f7aa7d35785a7cba099112f71bf90693f9b204529e5e3113.
- Source/save pipeline hashes exclude shaders. Every pinned pipeline file and the other seven owned runtime files remained byte-identical during this one-file adoption; see lighting_adoption_receipt.json.
- Native lighting run:4.4521s, sampled process HWM338,488KiB, total cgroup peak6,644,662,272bytes under the unchanged8GiB/512MiB-reserve guard. Software llvmpipe evidence is not target-hardware FPS acceptance.

Optional chunks remain unaccepted and the board uses the whole mesh. Diagnostics isolated a native normal-repacking delta≤5.79e-5; positions/colors/UV2 stayed exact, with no shared-position attribute conflicts. No runtime chunk change was made.

This is a playable terrain foundation with multiple source biome regions. Repeated structured relief and the angular baseline coast remain visible. No foliage, cities, rendered river channels, river crossings or final-art quality claim is made. The separately frozen contour B is not part of this profile.

Evidence is under artifacts/generated_v3_runtime; runtime_report.json, lighting_report.json, lighting_pixel_metrics.json and lighting_adoption_receipt.json are the primary receipts. Original source cleanup multi-seed evidence and third-party attribution are retained separately. No canonical/default/v2 or old-save migration was performed by this lane.
