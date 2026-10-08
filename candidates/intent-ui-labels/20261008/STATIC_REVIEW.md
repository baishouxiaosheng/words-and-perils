# Intent UI labels candidate

Status: NOT RUNTIME TESTED. Independent source-only checkpoint; not adopted.

## Changes
- Normal action button caption changes from 结束\n回合 to 提交\n意图 in creation and idle refresh. The existing two-line layout is preserved.
- The picker receives a deep display copy of existing choices. For tile rows only, the second segment separated by ` · ` uses the existing `terrain_name` map. For example `(1,2) · forest · 暂不可步行` becomes `(1,2) · 林地 · 暂不可步行`. Unknown terrain names, coordinates, suffixes, non-tile rows, and original choices stay unchanged.

## Static review
- Every frozen source-lock entry and every candidate overlay-manifest entry verified by SHA-256 before editing. Exact counts and hashes are in MANIFEST.json.
- Reversing only the three allowlisted replacements recreates base main.gd byte for byte.
- Existing main action callback, node name, phase branches, dice/confirm/retry captions and picker callback are unchanged. The picker keeps original choice order and selection indices.
- No authoritative game data, source rules, world resources, save data, render code or typography/layout values changed.
- GDScript syntax reviewed as text only. No engine parsing, compilation, scene import, runtime test, native display or visual screenshot validation occurred.
- Frozen restored source and completed backup were not edited. README remains blank and absent from this overlay.

## Known scope limits
Other legacy help/instruction strings still say 结束回合; this minimal candidate does not globally rewrite documentation or tooltips. Existing terrain_name mapping is reused exactly, so unknown terrain tokens remain verbatim.

## Pending runtime acceptance
When the resource guard genuinely permits engine work, apply this overlay only to a new isolated copy of the verified base. Check startup and idle refresh show 提交意图; waiting, completion, dice, retry, enemy and fallen states retain prior behavior; mixed actor/tile overlap rows retain exact selection targets and unknown custom labels; repeated open/close and source-replacement flows retain existing picker behavior. No acceptance pass is claimed here.
