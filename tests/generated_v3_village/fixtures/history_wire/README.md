# Valid radius-12 journey wire fixtures

These are exact closed save checkpoints from the real integrated board journey gate. Each journey contains movement, actor-focused rest, a clear village entry, then one whole-stack bundle drop and pickup. They are valid histories, retained byte-for-byte. Their earlier load rejection came from a shared focus comparison using raw integer-versus-JSON-float array equality; the guard-preserving canonical numeric comparison fixes it without changing these saves or their source/profile identities.

The regression reads only these package-owned fixtures and must never overwrite them. Both default `test_adapter.gd` and its `-- history_wire` mode require exact canonical roundtrip, unchanged source/catalog/placement/history/RNG, and unchanged fixture SHA.

Origin: isolated `v3_entities_candidate_20261005/game` integrated board gate; original research captures are listed below for provenance only and are not runtime dependencies. No credentials, live-provider requests, or user account data are present.

## valid_r12_coastal_range_journey.json

- SHA-256: `bb2de7749f0a6c1423cdba3e22e74d9c27df17f08cdbd3a4f78484c1d356bdff`
- Bytes: 536039
- Completed turns: 11
- Seed token: `726381`
- Recipe: `coastal_range`
- Profile: `generated_v3_village_inventory/v1`
- Source hash: `d88a38a306fb0d084a9b9ded823c0b272fdcec1d11deb6886d8e8d2862c668fc`
- Runtime hash: `9f0e2fc6cbb1525d819f3b351d89abfdab0f955b6f7261d0ebbed81f607204d0`
- Placement hash: `7ca43da518717a29f20bd88d08266e0843483746d4660882cce25e22b3667152`
- Original capture: `artifacts/generated_v3_placement/board_failed_save_coastal_range.json`

## valid_r12_plateau_hinterland_journey.json

- SHA-256: `5dee67e51cbb85f34aafa3fcc3068ee1f08dc188cdcaa4bfe6da3388abeab741`
- Bytes: 541764
- Completed turns: 13
- Seed token: `726381`
- Recipe: `plateau_hinterland`
- Profile: `generated_v3_village_inventory/v1`
- Source hash: `c7118fa41d30d369ac19043986db31c324a5da8ce1dd5667b610705774bb5492`
- Runtime hash: `83afb82318fe86182b2da7daf34899c8955bbd5ace5d5de6a383e83ad2195fc2`
- Placement hash: `56bb00c78da6b6338952a9be7b1039cf22e8591c7aa6fbb2694a4206a3df2021`
- Original capture: `artifacts/generated_v3_placement/board_failed_save_plateau_hinterland.json`
