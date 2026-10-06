# Actor-v2 FullMain test attachment for the public actor/status successor

Status: source-only adaptation and static identity checks. No Godot parse, native run, screenshot approval, provider request, publication or adoption is claimed. This driver exercises the actor-v2 branch of the combined candidate; it does not substitute for status-specific Main/3D tests.

## Exact project-relative files

- tests/test_full_main_bridge.gd: adapted original FullMain scenario driver
- tests/test_view_facade.gd: byte-identical original actor-v2 SceneTree and typed reply helper, SHA 3bf7e2eece5505618f6532a1102b6562c162b9fe35928ecc8053f49020a0226b
- tests/ai_gm_http/mock_transport.gd: byte-identical no-network mock, SHA 8d8e3fafc18e9ed9bb1295bb2d3eff3a52771afeb9ccc162017a2402001ec2df
- tests/actor_full_main/public_source_pins.json: 62 exact source pins

Install only in the existing separately admitted disposable public QA composition. No production code, resource, source data, preparer, shell launcher or Python runner is included. Reuse existing helper/mock files only when hashes match; if an existing dependency differs, stop and report the conflict. The driver itself must be installed as the explicitly selected new test revision, preserving earlier evidence.

Main must be bb15728f636f5d22a0d2f54b026468933246d073dfee59998fa78e2e54f3fa84. Actor-v2 authority must be 084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e. The source pinset binds public manifest a6de3fff486df95013f47602fd743de5ed21af484b13f63ac3e9c1a9b5d2a546, all 42 candidate files, all 7 required unchanged files, 11 effective-public inherited runtime/HTTP sources and the 2 helper files. The driver checks this pinset before Main and before final reporting. The attachment manifest separately binds the final driver bytes, avoiding a circular self-hash.

## Private environment and original guard

The existing approved guard must directly own each Godot process. Preserve its original 120-second ceiling, 512 MiB stop reserve, effective 8 GiB ceiling (use the lower of the physical cgroup limit and the approved 8 GiB test budget), separate 1,700,000,000-byte FullMain admission, one-active-Godot rule, fail-stop policy and private writable topology checks. This attachment neither implements nor relaxes that launcher.

Before launch, create a fresh private session root and set FOGBANK_ACTOR_FULL_TEST_ROOT to its normalized absolute path. Set XDG_DATA_HOME to a strict descendant, and ensure the actual Godot user:// is a strict descendant of that XDG path. Keep the same isolated user-data/application identity for the flow producer and every reader. Do not point any value at actual user saves. Symlink/private-directory topology is still an external guard prerequisite. Missing, relative, non-normalized or non-descendant paths reject before Main or saves. Flow also rejects an already existing user://actor_full_main directory, so a failed producer cannot be silently overwritten.

Native rendering is mandatory; headless rejects. The original actual Main startup capture freshness check remains. Each independently admitted segment needs its own actual PID, terminal guard receipt, matching report and clean error/warning checks. Maintain the existing approved resource/input closure in addition to this source pinset.

## Priority order: 13 existing scenarios

Use res://tests/test_full_main_bridge.gd with exactly one of these payloads per process:

1. --gate=flow
2. --gate=display --case=death-enemy
3. --gate=display --case=death-player
4. --gate=continue --case=player_awaiting_assessment
5. --gate=continue --case=player_ready_roll
6. --gate=continue --case=player_rolled
7. --gate=continue --case=player_staged
8. --gate=continue --case=enemy_awaiting_assessment
9. --gate=continue --case=enemy_ready_roll
10. --gate=continue --case=enemy_rolled
11. --gate=continue --case=enemy_staged
12. --gate=interruptions
13. --gate=display --case=movement

Stop on the first failed, incomplete, timed-out or errored segment; do not continue or retry under a failed session. Flow generates the current public seed 726381/radius 4/coastal_range source and produces engagement plus all eight phase checkpoints through actual Main actions. Require that successful producer before any other segment. Checkpoint manifests bind the exact Main, authority, pinset, driver, save/sidecar hashes and producer PID; fresh Continue requires a different PID. No old native save is imported, migrated or edited to match a new identity.

Death cases retain real assessed attacks and contested RNG, a bounded 32 ordinary-action attempt limit, both actual HP-zero outcomes, occupied-cell rejection, full horizontal token footprint, real Nameplate/Label3D and HUD/body checks. Exhaustion or timeout is incomplete/fail. Movement retains the real supported move, read-only fit probes, dynamic inventory/focus and explicit renderer-boundary fault/recovery scenarios. Injected faults are not natural terrain-failure coverage.

Interruptions retains the original cancel/late/duplicate/manual ownership/export/load/reset/consent scenarios. Its configuration fixture now uses the actual model-capable dual-role modal, explicit custom provider/model selection events and the real Save signal. Both roles keep different session-only synthetic keys, offline.invalid endpoint, 65536-byte budget and 30-second timeout. Mock installation and exact ownership/live=false are checked before any configuration. Save must clear both visible keys, send nothing, keep automatic requests off, close the modal and restore Main input before action tests. No direct client configuration bypass is used.

## Evidence and exclusions

Each segment emits ACTOR_FULL_MAIN_RESULT and its private JSON report/screenshots. Require ok=true, empty failures, current Main/driver/pinset hashes, correct gate/case/PID and terminal proof. Inspect actual images independently; screenshot existence remains pending visual approval. Original 252/66/211 and failed death-enemy counts belong to the old source only; none transfer here.

The original nine deferred/guest scenarios are deliberately excluded because their old adoption receipt/20-file coast provenance contract needs a separately reviewed public equivalent. Thus this attachment is the existing 13-scenario portion of Full22, not a 22/22 claim. It also does not test status-specific Main/3D effects, all-source terrain coverage, live providers or publication/adoption.
