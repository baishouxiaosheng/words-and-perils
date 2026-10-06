Selection motion: candidate-only update

Not a runnable game and not runtime- or visually accepted.

Production: one new view/tabletop_interaction/selection_motion.gd and exactly one of six mutually exclusive patches matching your Main SHA. The integration owner must apply the patch; do not overwrite Main with another version. Each patch adds the module after build_ui plus synchronous cancellation at both world-refresh entries. Existing WASD, API and actor behavior are retained.

Feedback: short actor hop, independent item pop and bounded preview-route markers. Existing committed movement/landing/FX are unchanged. Shared environmental instances are never animated; they receive owned marker feedback only. No world/actor root, RNG, costs, turns, health, save or source-identity writes are introduced.

TEST_MANIFEST.json maps four exact small inputs (31,242 bytes) into a separate headless fixture runtime and gives parse-first/finite-run arguments. Do not copy Main, assets or a full project. The 31 assertions have NOT been executed. The source preparation checks are not runtime acceptance.

Headless scope: mesh recovery, duplicate selection, cancel/reparent/free, actual short Tween completion and attention-catalog cache consistency only. Real Main/modal/input integration, source-bound save reload and native user-visible motion remain separate required checks.
