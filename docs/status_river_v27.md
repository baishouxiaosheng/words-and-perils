# V27: bounded status gameplay and offline river entry

Based on stable V26. V26 remains the rollback; withdrawn V25 is not a dependency. All files in this adopted project copy are independent ordinary files, including assets/imported resources. The runtime does not depend on a symlink back to V26.

## Gameplay and activation

Launch with `-- --status-gameplay` to start the explicit new Coast status profile. Its trusted world items (poison vial, feather vial and antidote) and landing action still require the ordinary assessment, fixed resolver validation, once-only resolution, preview and atomic commit. There is no direct player status-edit button. Existing/default profiles and old save paths retain their previous rules. The new profile writes an explicit versioned status save; old raw v1 poison data is not silently converted.

Poison/flight are the bounded real gameplay slice: application/removal, readable status details, common movement/passability and save/reopen are connected. The local library contains 168 distinct definitions, but the remaining 166 do not yet have all real gameplay sources, action adapters and displays wired. Multiple-enemy model quality/load tests and broader unified scheduling remain later work.

Flight can pass compatible ground obstructions, never known air-blocking/no-flight/clearance/load checks. This prototype additionally requires an affordable valid landing path. That is an explicitly limited admission boundary while falling, grabbing and rescue consequences are unimplemented, not a universal law forbidding voluntary dangerous flight. Multi-world-step actions currently reject explicitly rather than silently losing ticks; ordered bounded cumulative-time support remains deferred. Clocks are trusted owner-action/world-step events, not an independent combat initiative phase.

## River entry

The advanced menu contains an explicitly offline river test. It uses authored preset assessments, separate progress and the same assess/confirm/commit boundaries. The host journey is parked and restored exactly. Hashes, raw protocol text and detailed technical constraints are inside the collapsed diagnostics section. This entry does not claim connected free-form AI or final art quality. The preserved signed preset strings are not rewritten by the readable display summary.

## Public request budget

New status-mode requests may use `public_dictionary/v2`, a flat public-value table with bounded numeric aliases. Every packed request expands exactly to its original scoped public request; goal/focus stay literal. The codec only sees already-public values and removes no facts; privacy tests include unknown-source NPC status counterexamples. No cap is increased. The public JSON cap remains 65,536 B and Client body cap 4 MiB.

At the tested current full-history boundary (eight real receipts, five whole selected memory records under the original 6/4096 policy), actual 100/300-Chinese-character requests were 64,027/64,627 B, leaving 1,509/909 B. The samples only establish complete request admission, not successful execution of every compound intention. 4 KiB intentions still reject in this context. No real model call, understanding/quality claim or API cost measurement is included.

## Evidence and visual scope

`artifacts/status_river_v27/` contains the exact adoption receipt, source/delivery manifests, independent review and selected small evidence. `artifacts/public_witness.json` is a byte-frozen fixture (SHA256 847462d0375289ed0a0bf7e6c4bd161303a611759a1d52dccf61ace1c37d31f2), not a new action authorization. Use the dictionary test's `--public-witness res://artifacts/public_witness.json` option to reproduce its pure transport measurement.

The six final 1920×1080 images were newly rendered from the actual Main/river tree in a native offscreen viewport; no old screenshot was enlarged. Their method-driven actions are separate from prior OS-input evidence. A known llvmpipe V-Sync warning remains. These checks do not certify long-running GPU resource behavior or finished art.
