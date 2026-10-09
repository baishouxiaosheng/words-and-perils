# Exact state and external GM protocol

`game_state.gd` is a RefCounted state/action boundary. `gm_provider.gd` is the swappable provider interface. `json_relay_provider.gd` implements offline file relay, and `json_file_transport.gd` handles JSON bytes. No provider contains a gameplay solver, potion-name switch, success comparison, or model API credentials.

## Application interface

```gdscript
var game = preload("res://core/game_state.gd").new()
var relay = preload("res://core/json_relay_provider.gd").new()
var initial = game.request("Natural language goal", Vector2i(1, -1))
relay.export_request(initial.request, "user://planning_request.json")
var imported = relay.import_decision("user://planning_decision.json")
var planned = game.apply_planning(imported.decision)
var resolution_request
if planned.needs_roll:
    resolution_request = game.roll_action(initial.request.action_id).request
else:
    resolution_request = planned.request
relay.export_request(resolution_request, "user://resolution_request.json")
var final = relay.import_decision("user://resolution_decision.json")
var committed = game.commit_decision(final.decision)
```

Every method returns `{ok: bool}` and errors are returned as an array of strings. No-roll planning directly returns the resolution request; it must never manufacture a D20. `resume_request(action_id)` restores the stage after load. `cancel_action` removes a pending action. `new_world` resets state and generates a new world ID.

## Two model-led stages

Planning: `{schema_version:1,action_id,state_version,phase:"planning",narration,needs_roll,difficulty,context}`. `difficulty` is required when `needs_roll` is true. Planning updates pending metadata and dialogue, never the numerical world.

Resolution: `{schema_version:1,action_id,state_version,phase:"resolution",narration,outcome,patches}`. The GM must receive the exact player D20, retained as `request.context.player_roll.value`; `request.roll.d20` is a UI alias. Dice never automatically choose success. The GM supplies absolute canonical patches, e.g. `{op:"set",path:"/actors/actor_player/stamina/current",value:8}`. JSON pointer escaping is supported.

Permitted patch roots are actors, items, hexes, flags, and world_time. Existing stable IDs and hex coordinates cannot be removed/changed. Integer IDs/version numbers, finite exact numbers, valid hex references and inventory references are integrity conditions. Stats and item descriptions do not encode bespoke game rules. Any claimed admin authority in a player goal is explicitly identified as untrusted in the GM contract.

Accepted resolutions commit atomically, increment state_version once and append an exact event. Replaying the identical decision is idempotent across save/load; a conflicting decision with the same action ID is rejected. Concurrent actions from an older world version are rejected. Recent dialogue retains the last 40 entries while all committed events remain exact and durable.

## Persistence and honesty

Saves include world facts, pending stages/snapshots/planning/rolls, events, dialogue and committed decision hashes. Saving writes JSON to a temporary file and then renames it. JSON uses full precision and accepts integers only inside the exact interoperable range ±(2^53−1); whole parsed JSON numbers are normalized back to integers. Invalid loads do not replace live state.

The relay explicitly reports `live:false`. Export carries the full exact snapshot, descriptions and context. Import accepts external decisions without inferring a response. Recorded examples must use `recorded_example_for` and a labelled envelope matching goal, phase, numerical version, target and any recorded D20. A fresh session's action ID is rebound explicitly; the recorded response's provenance remains visible. Optional `expected_snapshot` requires equality of all facts except the fresh world ID.

Recorded fixture D20 overrides are testing-only. The normal application roll calls `RandomNumberGenerator.randi_range(1,20)` once per action. No deterministic gameplay mock is shipped in the production provider.

## Tests

Run `godot --headless --path . --script res://tests/test_core.gd` for isolated architecture/integrity checks. `tests/export_fixture.gd` exports concrete complete requests. `tests/test_recorded_cases.gd` audits four externally supplied model cases and writes a report; missing replies are reported, never replaced by a local mock. These cases expose model decisions and any semantic limitations independently from structural validation.
