# Project-local typography fonts

- Long or arbitrary Chinese text uses the existing complete `../NotoSansCJK-Regular.ttc`. `ui_craft.gd` chooses its **Simplified Chinese face, index 2** with `FontVariation`; index 0 is Japanese. It is not replaced, subsetted or repacked.
- Titles and the fixed journal heading use `MistbankSerifUI-Regular.otf` (a renamed Noto Serif CJK SC subset).
- Important primary actions use `MistbankSerifUI-Bold.otf` (a true original Bold face, not synthetic emboldening). Dense secondary/tool controls remain sans.
- Both serif faces explicitly fall back to that complete Simplified Chinese sans resource for new labels or uncommon characters. System fallback is disabled to make packaging behavior deterministic.

## Source, license and modification

The existing installed Noto CJK fonts at `/usr/share/fonts/opentype/noto/` are the source of the two new subset binaries. Their OpenType metadata identifies the Simplified Chinese faces as Noto Serif CJK SC, version 2.003, and retains the original Adobe copyright and author/notice records. Source repository: https://github.com/notofonts/noto-cjk . Official font packaging guidance: https://github.com/notofonts/noto-cjk/blob/main/Serif/README.md . Official license: https://github.com/notofonts/noto-cjk/blob/main/Serif/LICENSE . We did not install a new font or alter OS settings.

`LICENSE.txt` includes the original copyright notice and full SIL Open Font License 1.1. The derivatives remain under OFL, are renamed in both OpenType name records and CFF family/PostScript names, and are not advertised as an upstream release. Original glyph drawings are unchanged. The full original files are not duplicated into the project.

`build_ui_subsets.py` extracts SC face 2, retains all available characters used by the fixed UI plus ASCII/digits/punctuation, preserves copyright/license/designer metadata, and renames the subset. `ui_characters.txt` records its input. `provenance.json` records original versions, original file hashes, derivative hashes, exact byte counts and modifications. Rebuilding requires fontTools and the stated source files; it never installs fonts.

New font payload: **656,520 bytes total** (324,972 Regular + 331,548 Bold). Binary hashes are in `provenance.json`. The complete body font's pre-existing license remains at `core/NotoSansCJK-LICENSE.txt`.
