# Admitted V3 village renderer

`settlement_view.gd` is a standalone `Node3D`. Attach it at identity transform in the same source-coordinate frame as the native ground mesh, then call `configure(placement_result)`. Configuration returns `{ok, placement_hash, report}` or `{ok:false, error, report}`. An error clears all renderer-owned content; it never substitutes another model or terrain proxy.

## Inputs and scope

- A successful planner result with the unmodified `generated_v3_placement/v1`, `dry_village/v1` manifest and exact `surface` object. The manifest digest, asset-catalog identity and surface geometry hash are checked again.
- Exactly one settlement, three buildings, and at least one road. Asset IDs are the pinned catalog's original `village_cottage_a`, `village_barn`, and `village_cottage_b` IDs.
- Manifest transforms are applied literally: uniform scalar scale, yaw around Y, authoring front −Z, and Y=0 authoring pivot. There is no recentering, refitting, radius-based replacement or fallback art.
- Actual native `surface_get_arrays` vertex/index data across the entire scene hierarchy supply bounds. `Mesh.get_faces()` is deliberately excluded because Godot TriangleMesh snaps its picking vertices to 0.0001. These must match the pinned catalog and fit inside the supplied full conservative convex footprint. LOD geometry must fit inside full bounds. Every actual full and LOD vertex is also transformed and independently checked against the admitted footprint and support floor; the physical tolerance remains 0.00001. Declared-vs-native local bounds retain the 0.00002 tolerance and now report signed per-axis deltas, even on failure.
- There are no gameplay, navigation, authority, save, source-geometry or biome writes, no physics nodes, and no gates/NPCs/rooms.

## Lossless wire coordinates

Building `position`, `yaw_radians`, `scale`, footprint and support fields remain ordinary numeric values quantized to Q=4096 (q12). They are applied literally without further rounding.

Road centerlines use `centerline_q40: [[x_int,y_int,z_int], ...]` and `centerline_scale: 1099511627776` (2^40). Each coordinate must be a finite, mathematically integral JSON-safe number; fractional values, unsafe integers and other scales are rejected. Integral numeric values decoded by JSON as floats are accepted because the integer itself is exact. The renderer divides by 2^40 into a local array for shading and diagnostic reports only. Decoded coordinates are never written back to the manifest. A legacy floating `centerline` field is not used as a fallback.

Entry anchors similarly carry `position_q40` and `position_scale`; this renderer does not consume anchors. Exact terrain clipping and foundation edge intersections come from the native surface and are independent of the centerline wire representation.

## Geometry and inspection

Building tops are flat at `foundation_plane[2]`, which must equal `position[1]`. Full footprint coverage is checked against native terrain triangles. Each foundation edge is split at every `surface.segment_points` triangle crossing; its lower wall vertices use the exact returned terrain heights. There are no guessed corner supports and no skirt pushed beneath terrain.

Roads use `surface.clip_polygon` for the complete manifest footprint, triangulating each returned native triangle intersection separately. Their only displacement is the declared +0.012 Y lift; nominal visual width is 0.40. Warm earth/edge color changes do not alter geometry. Roads do not receive gameplay cost changes.

`selection_nodes()` returns `{id, kind, node, hex}` rows for each building and road followed by the aggregate settlement. It exposes no new interaction authority. The caller owns any catalog integration and visibility policy.

`report()` is JSON-safe and includes identities, full/LOD bounds and triangle counts, applied transforms, foundation terrain edge samples, road native piece vertices/triangle IDs, coverage areas and LOD identity. `lod_report()` gives current displayed asset hashes. `update_lod(camera)` is public for deterministic camera tests and is called automatically for the active viewport camera. LOD uses 32/44 px hysteresis and swaps only the one matching mesh, with no change to entity identity, root transform or full authoritative footprint.

## Validation ownership

The renderer owner does not launch Godot; native parse/runtime and camera QA are performed through the parent-owned engine queue. `verify_assets.py` is a read-only, engine-independent GLB integrity/bounds check runnable with Python. It is not a replacement for Godot imported-hierarchy and visual QA.

## Native measurement reference

The rejected first capture measured Godot's triangle-query proxy rather than its render vertex buffer. In Godot4.6, [`Mesh::get_faces`, lines477–480](https://github.com/godotengine/godot/blob/4.6/scene/resources/mesh.cpp#L477-L480) delegates to `TriangleMesh`; [`TriangleMesh::create`, lines125–127](https://github.com/godotengine/godot/blob/4.6/core/math/triangle_mesh.cpp#L125-L127) snaps each input vertex to0.0001. That explains the observed raw cottage coordinate0.251514077 becoming0.251499981 in the proxy. The fix reads actual surface arrays and retains the original physical tolerances. No engine code was copied, imported or executed from those references.


## Explicit combined board

`board.gd` extends the accepted inventory board for the separate
`generated_v3_village_inventory/v1` profile. It consumes an admitted combined
Source with `placement_result`, `static_reference`, and the placement-aware
navigation overlay. It registers full opaque building bounds before the inherited
pack view fits a ground pose, and shares the already-verified `Surface` rather
than building a second triangle index. The old inventory and exploration boards
are unchanged.

`picking.gd` indexes actual render surface arrays. Its capture membership excludes
later selection-glow children; queries use current transforms and current LOD
meshes. Building and aggregate settlement references can share a nearest physical
surface. An opaque nearest surface hides deeper objects and terrain. A road click
retains the actual supporting cell; the aggregate settlement cannot be selected
on an outside road endpoint.

The board validates immutable static references and their supported cells while
installing an admitted placement. Pointer queries only retrieve these checked
headers; unsupported cells fail closed. This avoids rehashing the entire static
catalog on the first hover. Actions still pass their reference back through the
authority resolver. Actor and item facts are never cached by this new layer.

The accepted joint board fixture passes68 checks across both radius-12 recipes:
selection/camera purity, actual assessed travel/rest, entry animation, grounded
village pack placement, pickup, and byte-exact combined save readmission after
11 and13 turns. The inherited historical actor-focus validation defect exposed
by those longer journeys was fixed and regression-tested by the authority lane;
no placement or geometry change was needed.

All three remaining incident edges for each tested village are also sampled in
both directions,41 times per direction (492 local-approach samples total), using
the production support poses, exact navigation route points, hop animation and
actual carried mesh AABBs. No sampled pack/building AABB intersection occurs.
This is a bounded sampled presentation regression, not a continuous swept-volume
proof or a claim about every possible seed. The full-area physical placement
suite independently covers12 source/recipe/radius fixtures.
