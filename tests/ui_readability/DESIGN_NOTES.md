# Typography and button revision · 2026-10-03

The earlier resolution matrix proved geometric containment and actual output pixels. It did not prove good visual typography or button design. This revision is not considered visually accepted until the real control preview and in-game captures have been inspected.

## Observed defects

- A tall pointed decorative texture was compressed into a roughly32px history button; its artwork intruded into the reading plane despite the text technically fitting its control rectangle
- Expanded input stretched the adjacent round turn control into an ellipse
- Reading text and controls shared too much synthetic weight, making the hierarchy weak
- Input and button bevels repeated heavy framing inside already ornate outer containers
- Hover-pressed treatment was not explicit; button interiors and text needed stronger state consistency

## Revised specification

- Body18px regular with approximately28px line rhythm; semibold15px compact labels,16px ordinary buttons,17px speaker,18px primary action and20px history heading
- At1440p, native font sizes are recomputed (body24px); no whole-HUD bitmap enlargement
- Shallow chamfered secondary tablets with14–16px content padding and no internal lines through the glyph band
- Compact icon circles36px; top-level icon circles42px; turn circle88px stays square and vertically centered next to expanded input
- Calm cream writing inset inside the existing fantasy action base
- Teal primary fill has at least4.5:1 contrast against its light label in normal/hover/pressed states; secondary text is higher contrast
- Disabled treatment remains readable but desaturated; keyboard focus uses a separate2px teal ring
- Preserve pale-straw palette, existing outer fantasy morphology, portrait/minimap grouping, world ratio, and white bold world names with soft shadow

## Primary reference sources

- Larian's HUD update emphasizes grouped/hideable action decks, reduced clutter and useful information staying accessible: https://baldursgate3.game/news/community-update-15-absolute-frenzy_49
- Microsoft typography guidance establishes hierarchy through a type ramp, regular body/semibold emphasis and stable left-aligned reading anchors: https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography
- Microsoft button guidance covers clear action labels and predictable button semantics: https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/buttons
- Godot StyleBoxTexture explains actual nine-patch texture/content margins, which must fit the control size: https://docs.godotengine.org/en/stable/classes/class_styleboxtexture.html
- Godot Button exposes separate hover,pressed,hover-pressed,disabled and focus states: https://docs.godotengine.org/en/stable/classes/class_button.html

These are design principles and implementation references. No commercial game's art or code was copied.

## Verification plan

1. Low-memory native2D controls preview: tests/ui_readability/run_controls.sh. Clearly labeled preview, no3D world loaded
2. Inspect glyph centering, actual margins, circle proportions and all states at native pixels
3. Run actual HUD captures at720p and1440p only when the serial queue and memory budget permit
4. Verify long Chinese text, expanded writing, history, small target buttons, and disabled/waiting treatment visually; keep geometric assertions as supporting evidence

## Component review result ·12:06 UTC

The native1280×820 controls sheet was rendered and visually inspected. The component hierarchy, glyph centering, internal padding, circle proportions and four displayed state resources are legible;44/44 supporting checks passed. It exited0 in2.52s, sampled peak childRSS280964KiB, under the owned-process guard reserving512MiB of the verified8GiB cgroup.

This is component style proof only. At that12:06UTC stage, full-world admission hit the memory reserve before the first frame; the later in-world result below supersedes that temporary blocker. Prior resolution passes predate this typography revision and must not be presented as its visual approval. The preview demonstrates actual style resources; its hover column is a static resource preview, not a claim of manual pointer interaction.


## Final in-world review ·12:53UTC

With sufficient cgroup headroom, actual production HUD runs at1280×720 and2560×1440 each passed89/89 checks and exited0 under the owned-PID guard. All six original PNGs were visually reviewed. The first pass revealed that the calm writing field covered too much of the ornamental frame and narration needed more lower breathing room. A final inset correction aligned the reading columns, kept the writing field inside the ornament and removed trailing blank log lines. The rereview confirms clear long text, the visible fantasy frame, and a centered circular two-line turn action in default and expanded-input states.

Final evidence: artifacts/ui_readability_20261003/final_review.json and source_validation_manifest.json. The source manifest includes exact post-run hashes, time-stamped guard logs and an exact-byte proof that the main.gd AA wiring is unchanged from its native snapshot outside append_journal. It explicitly does not pretend that a pre-run source hash file was captured.

Current visual coverage is720p/1440p default, expanded input and long history. Historical1080p/ultrawide/16:10 geometry results predate this final typography revision; physicalDPI, target-GPU performance and broader locale/menu combinations remain separate work. Existing GL texture cleanup warnings remain logged despite exit0.
