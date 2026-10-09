# Integrated material visual check

Reviewed real application captures:

- `artifacts/miniature_ui_iteration1.png`: initial 12:31 local capture; parchment,
  texture imports and brass bevels were visible, but repeated multi-band control
  edges looked too bright and heavy
- `artifacts/first_board.png`: 12:35:48 +08:00 on 2026-10-01; current narrowed
  trim and lower-contrast paper render correctly. Board background is dark,
  ivory and slate token silhouettes remain distinct, and text remains readable

Changes made from actual pixels:

- Large panels reduced to 3px visible trim, one restrained reflection
- Buttons have a dedicated 2px material trim option and directional surface grain
- Fields have a dedicated 1px recessed-edge option
- Metal highlight multiplier capped at 1.18 instead of 1.70, with gentler shadow
- Paper cloud/fiber contrast halved under text

Focused API/import verification passes in `api_check.log`: mipmap presence,
normal and roughness textures, linear vertex-color handoff, rounded UI alpha,
correct nine-slice margins, and preservation of rough non-metallic felt

These are visual/material checks, not a performance certification. Full-board
view shows restrained detail; close views are needed to judge fine mineral,
wood and polished token detail. Actual software renderer performance depends on
scene object count, shadows and terrain tessellation. This library does not
change geometry or claim hardware ray tracing.
