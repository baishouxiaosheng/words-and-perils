# Immutable vegetation catalog, focus and bounded context

## Admission boundary

`Catalog.build(profile_id, source_identity, manifest, asset_catalog)` accepts an already-admitted `Planner.build` result or the exact result returned by `Planner.validate`. The caller owns deterministic physical admission. Catalog shape/digest validation is not a substitute for native support, reservations, clear corridors, unchanged geometry or planner regeneration. Self-rehashing a manifest or catalog does not establish any of those facts. Saved external catalogs must be compared with a catalog rebuilt from the admitted manifest; immutable Source state must retain that rebuilt catalog and binding.

`source_identity` is the upstream runtime identity before vegetation composition. It must contain `source_contract`, `content_hash`, `geometry_hash`, `runtime_hash`, `placement_hash` and `effective_navigation_hash`; existing item/static/NPC catalogs are checked for ID collisions. The independent gameplay `profile_id` is not the ecology profile.

The composed world needs these metadata values:

- `profile = profile_id`
- `vegetation_entity_catalog = built.catalog`
- `vegetation_catalog_hash = built.catalog.catalog_hash`
- `vegetation_profile = "sparse_biomes/v1"`
- `vegetation_hash = admitted_manifest.vegetation_hash`
- `vegetation_base_runtime_hash = upstream_identity.runtime_hash`

Source content, geometry, placement and effective navigation digests remain unchanged. The catalog also binds the ecology context, native asset catalog and NPC reservation digests. Catalog entries preserve root IDs from the manifest; 0–1024 entries are allowed. All transport comparisons use canonical integral-safe JSON bytes. Compact descriptors retain exactly declared asset/biome/habit/transform, row hash, full/far native vertex-buffer digests and a bounded support summary. Full polygons and other physical witnesses stay in the manifest outside model requests.

## Selection and history

`Focus.make_reference(id, state, clicked_hex=[])` returns the world/kind/id/hex/scene/catalog-version/catalog-id/entity-revision header. `kind` is `vegetation`, `entity_revision` is always integer zero, and the version is `source-vegetation-focus/v1`. A valid `clicked_hex` is only a renderer hint: canopy overhang never changes the plant's admitted root hex. Malformed hints fail closed. `Focus.resolve(reference,state)` rejects altered root/reference fields and returns `{ok,focus}` with the immutable source/catalog/vegetation/descriptor/supporting-cell/location facts. `validate_historical(focus,state)` checks all frozen fields exactly. Unrelated actor movement and turns do not revise plant identity.

`Focus.references_for_admitted_world(state)` validates the complete world once, then returns `{ok,references}` with all compact exact reference headers keyed by plant ID. Source may retain this detached immutable renderer lookup table; do not call `make_reference` independently 1024 times to build it. Authority `resolve` remains strict, and no mutable caller dictionary is memoized. The test suite reports timings for validation, single reference, resolution, and the complete 1024-entry table.

No helper mutates state, consumes a turn or enables cutting, harvest, cover, custody, possession or NPC behavior. Observing remains the caller's normal assessed-turn action. Root cells must agree with the declared source biome and remain dry/non-river in a unique scene.

## Model projection and actual paging

`Projection.frozen_focus(full_focus, cell_fields=[])` emits the compact descriptor exactly once, under `facts.descriptor`. The focus header's `catalog_id` binds the complete immutable evidence retained in history. Redundant source identities, full cells and location witnesses are deliberately not repeated in this compact model view.

`Projection.resolve_context(reference,state)` is the preferred complete read-only selection refresh. It returns `{ok,focus,context}`, with the full immutable focus and exact same bounded public context as separate `Focus.resolve` plus `Projection.context`. Supply the exact header from the Source-owned immutable reference table to avoid another full validation just to rebuild a reference. The combined operation performs one complete `Catalog.validate_world`; private synchronous checked helpers reuse that result for reference, history and page work. There is no global cache or memoization of mutable caller dictionaries. Public `resolve`, `validate_historical`, `nearby_page` and `context` still validate every call, and every exact reference/history/cursor/byte gate remains in place.

`Projection.context(state, full_focus={})` now performs one full world validation (formerly three for a selected plant); it returns the page to insert as `vegetation`. It uses the player scene/root center and axial radius 2, excludes a selected plant, and chooses 3, 2 or 1 nearby summaries so the canonical combined `{frozen_focus,vegetation}` contribution is at most 2048 bytes. A failure returns `{}` and must fail closed in the caller. Each nearby summary contains only `id`, root `hex` and `asset_id`; selected descriptor content is not duplicated.

`Projection.nearby_page(state, scene_id, center, radius=2, excluded_id="", cursor={}, limit=3)` is an implemented read-only query helper, not a gameplay action. Radius is 0–2 and limit is 1–3. IDs are sorted lexically. The result contains `{ok,schema_version,catalog_id,scope,catalog_total,total,returned,omitted,after_id,next_cursor,entries}`. `catalog_total` counts all catalog roots; `total` counts exact roots in the specified scene/radius after selection exclusion; `omitted = total - returned` counts every scoped root absent from this particular page, including prior pages. It is not a claim about remaining pages or global absence. `next_cursor=null` means the scope is exhausted. A non-null cursor contains `after_id` and a digest binding the exact catalog hash and full scope. A cursor from another catalog/center/scene/radius/selection fails closed. Do not advertise pagination as an AI gameplay action: expose this helper only through a read-only inspection surface if desired.

The complete request still has a separate 65536-byte ceiling. This module's 2048-byte bound does not prove that the combined NPC/static/terrain request fits; the integrating adapter must measure and reject the final serialized request.

## Verification

No native Godot process was launched while authoring this module.

Queue in the parent's serialized native test lane:

`godot --headless --path game --script res://tests/generated_v3_vegetation/test_catalog_focus.gd`

The synthetic fixture tests exact JSON transport only; it intentionally makes no physical-admission claim. The suite covers field whitelists, row/source/asset bindings, root-versus-canopy identity, revision zero, read-only state, historical witnesses, integral JSON round-trips, tampered/rehashed catalogs, unknown capabilities, scene/cell/namespace collisions, a full 1024-record catalog, byte caps, and scope-bound cursor traversal. When `test_vegetation.gd` artifacts are present, it also converts every matching physically admitted native manifest against its native asset catalog. That optional pass is reported separately from synthetic checks.

Independent read-only export audit: `python tests/generated_v3_vegetation/audit_catalog_exports.py`. The recorded four-case result in `catalog_export_audit.json` checks existing native artifacts without invoking Godot. It measured maximum compact descriptor 688 bytes and maximum modeled combined selected-focus/three-summary contribution 1913 bytes using a full V3-length world ID. Native GDScript and final combined gameplay request measurements remain separate checks.

Optimization verification adds a test-local copy of the original context algorithm as a byte/timing oracle. It compares selected, unselected, JSON-transport and full-1024 outputs, and repeats negative reference/history/world/actor-scope gates on the single-validation paths. Timings include `legacy_context_1024_ms`, `context_refresh_1024_ms` and `resolve_context_1024_ms`. The original parent-run baseline before reuse measured approximately 194 ms validation, 631 ms selected context, and 987 ms separate reference/resolve/context; revised measurements must come from the parent-run retry. The synthetic fixture's composed runtime merge now explicitly overwrites its upstream runtime field; the upstream binding is unchanged.
