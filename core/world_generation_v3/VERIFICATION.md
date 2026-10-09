# Verification: 2026-10-03

## Source

Godot 4.6.3, guarded headless run: **360/360 assertions**, exit 0, 16.6588 seconds. Four requested seeds (0, 726381, signed32 boundary -2147483648, and Chinese text) × radii 4/12/24 × two recipes = 24 source cases. All accepted without retry.

Checks include strict input rejection, complete domain, deterministic interleaved regeneration, exact JSON round trip/content hash, same-seed actual numeric recipe differences, bounded finite fields, quantized-field biome consistency, post-conditioning temperature, exact persisted fill identity, declared world-space adjacent-edge slope bound, downhill adjacency, per-node rainfall/flow balance within stated quantization tolerance, and ocean components reaching the crop boundary. Controlled climate fixtures verify wind reversal, terrain response, height lapse and double-buffer iteration-order independence within floating tolerance. Source comparisons do not establish renderer clearance.

For seed 726381 the plateau recipe has 3/26/98 cap-center samples at radius 4/12/24. Final cap spreads are 0/0.001953125/0.00390625 world units. This is an actual broad source cap with a small conditioning tilt, not a perfect final flatness claim.

Controlled ridge fixture: windward rainfall sum 0.1587778846, leeward 0.0516978067, approximately 3.07×; reversing wind reverses the contrast. These are fixture numbers, not a guarantee for arbitrary coast geometry. Soil moisture may increase downwind through runoff even where rainfall decreases.

Maximum sampled headless process high-water RSS: 107,260 KiB; sampled total cgroup peak 4,543,963,136 bytes. Physical cgroup limit 8,589,934,592; guard threshold 8,053,063,680. These are bounded source-test costs, not rendered FPS.

## Native diagnostic

Final capture: exit 0, six PNGs, no script/runtime ERROR, 2.6739 seconds. Godot 4.6.3 GL Compatibility, cloud Mesa llvmpipe. Maximum sampled process high-water RSS 250,916 KiB; total sampled cgroup peak 4,662,288,384 bytes. Only the unsupported V-Sync warning remains.

Both r12 recipes use seed 726381, identical matched camera transforms/projection/size per view, the same lighting, and a complete **864-triangle** cell-center lattice. Overview, oblique biome-colored, and oblique neutral-material images are provided. Independently generated native source JSON is byte-equivalent to the headless fixture in a separate process for both recipes.

Actual PNG buffers are **1280×800**. The script requested 1280×900, but the cloud desktop supplied a shorter window. This was caught by reading the PNG dimensions. The original capture report's hardcoded `viewport` field is retained only in `native_report_original.json`; the current report correctly distinguishes requested dimensions from verified captured pixels. The capture script was narrowly corrected to record actual image dimensions on future runs; no geometry, source, camera or image pixels were changed after capture.

## Pixel review and decision

Reviewed all six final native PNGs plus the source-field chart.
- The two recipes visibly differ in coastline orientation, distribution of high ground and broad cap area
- Neutral views show continuous connected relief; no isolated one-cone-per-cell construction or dense repeated ridge stair-strip is evident in this coarse fixture
- Biome-colored views still show coarse triangular/zigzag climate transitions. These are **not accepted** as final natural boundaries
- The numerical plateau cap is real, but its wide-view silhouette is too subdued to certify final plateau readability
- Water/board clipping and color are diagnostic scaffolding. There is no beach, river-curve or 80% area acceptance

Decision: **promising source/climate foundation; retain as separate research candidate**. Do not migrate the default game or present the native diagnostic as finished terrain art. Further plateau and ecological-boundary refinement is deferred.

## Isolation and failure history

All ten files in `protected_before.json` and `protected_after.json` remain byte-identical, including the v2 generator/contract/validation, shared terrain profiles/field/channel index, generated source/navigation/seeded adapter and main entry. No old renderer/default integration or Library game replacement was performed.

The first source run caught a real threshold-adjacent pre-quantization biome mismatch (297/298). Classification was moved after authoritative quantization; final-height temperature and exact fill identity were strengthened, and threshold regression cases added. The initial native harness failed because `root` shadowed SceneTree's native member; it was renamed, and unavailable ALSA was avoided with dummy audio. Pixel review of the next capture found 12 missing triangles at one cropped lattice edge; the harness was corrected to enumerate boundary-adjacent triangle anchors and assert 864 triangles. Failed/intermediate logs and images are explicitly archived separately and are not accepted evidence.
