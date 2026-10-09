# v28 natural coast

The accepted v27 source gains two explicit offline natural-coast entries:
coastal_range and plateau_hinterland, with seed 726381 and radius 4.
Supported basic actions are move, observe, rest, drop_item and pickup_item.
The existing default entry remains 1801. Actor-action and biome-preview bridges
are not part of this update. Existing saves and rules remain unchanged.

## Recorded acceptance

Candidate checks: compile 4, coastal adapter 157, plateau adapter 157, session 35,
localized full-scene 81 unique assertion IDs and real OS input 20 unique IDs.
The independently materialized adopted copy separately passed 16 smoke assertion
IDs with exit 0 and no recorded engine errors. These are distinct runs and are
not combined into a new whole-game acceptance claim.

The SHA-bound update contains exactly 20 production files and 7 acceptance-test
files. Additional publication-only helpers, this note and a redacted adoption
summary provide offline restoration and verification. The root main.gd visible
before restoration remains the previously verified recovery-base file.

## Offline restoration

Run python3 tools/restore_repository.py, then open project.godot in Godot 4.6.3.
The GitHub chain is v21 base, v22, v23, v24, v26, v27, then v28. V25 remains
withdrawn. README.md stays blank. All resource archives are reused unchanged.

Publication testing applies the real small delta to the previously verified
v27 public recovery tree and checks immutable preimages, refusal of unknown
changes, idempotence, exact production pins and unchanged resource identities.
It does not launch Godot or rehash the large base resources. The full user-facing
offline restore command still validates every source and resource byte.
Generated editor caches and differing historical evidence layouts are not
claimed to be an exact mirror of the adopted development directory.
