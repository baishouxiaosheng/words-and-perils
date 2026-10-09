# Committed action presentation

`view/playable_build/committed_effect_router.gd` receives only a successful fresh
commit receipt plus its before-state. The board's ordinary `set_world` path still
updates exact health/nameplates from authoritative state. It never derives damage
from a visual, prose, selected target, or effect duration.

## Render budget

- Original procedural low-poly geometry: one shared box mesh and flat material
- At most 16 reusable effect slots, each one MultiMesh (at most 24 boxes) plus an
  optional billboard label; at most 64 delayed events
- No particles, fullscreen shaders, bloom, real-time lights, colliders, or timers
- No new downloaded assets or packages. The existing Noto CJK font retains its
  repository SIL OFL provenance
- Idle processing is disabled; reset/load cancels active and delayed effects

## Semantics

- A typed `combat_event` comes from the trusted authored resolver's frozen branch
- Melee produces a short sweep; ranged a muzzle star and quick tracer; magic a
  source sigil and arcing comet. These are available only with authored equipped
  capabilities, valid range/costs, and a committed resolution
- Misses pass beside the target and display `未命中`, without hit sparks or damage
- A negative committed health patch produces the exact damage popup, brief hit
  flash, and sparks. Grazes and poison ticks have distinct text/colors
- New poison/flight, condition expiry, and actual positive health deltas have
  corresponding short effects; decrementing an existing status is not replayed
  as a new application
- HP itself updates immediately from committed state, independent of animation
- Default-board showcase calls intentionally do not invent gameplay

## Verification

`./tests/committed_action_feedback/run.sh` is a bounded, small headless regression
with a 25-second in-script watchdog and 35-second process timeout. It does not load
the terrain world. It covers empty/canceled and staged results, hash tampering,
once-only dispatch, load replay suppression, exact hit/miss/graze damage text,
poison/flight/expiry semantics, fixed pool limits, cleanup, and visible-surface
movement settling. Fixtures in this unit test are synthetic test-only receipts;
real engine combat and native-window proof are a separate integration step.

Final small-run evidence (2026-10-03): 35/35 presentation assertions and 112/112
real-engine assertions. `run_authoritative.sh` covers all nine combinations of
melee/ranged/magic and real seeded miss/graze/hit outcomes, correlating popups to
actual before/after HP. The pool report records actual saturation (16 allocated
slots, 32 deliberately dropped excess visual effects) and zero active/pending
work afterward. Dropped visuals never alter gameplay.

`test_main_combat_capture.gd` is the separate default-main native proof harness.
It uses `Adapter.new(1,true)`, expressly labelled release-test RNG, normal sample
callbacks, legal assessed movement, owned/equipped weapons, real costs and enemy
phase handling. It freezes only the presentation clock briefly to photograph an
already-committed event under a slow software renderer. It does not inject world
state or manipulate RNG outcomes. Native results are not implied by the small
headless results above; consult its separate report.

The actual-main combat headless preflight passed 62 assertions before later
composite sequencing work. Its observed sequence was a real firearm miss, a magic
hit for 3 HP, and a melee miss. Native rendering still requires separate verification.

Composite movement is now presentation-ordered: a combat event preceded by the
same actor's committed movement waits for that actor's route generation to settle.
Its impact/status delays begin at arrival. A newer route generation invalidates
stale queued visuals instead of firing from a wrong square. This scheduling never
delays or changes authoritative health/cost publication. Load/reset cancels all
queued visuals. `test_main_composite_capture.gd` uses the exact authored
move-then-attack sample and checks the mandatory NPC wait, read-only input, exact
pending save/load, and one subsequent real enemy commit. Both actual-main scripts
record source hashes and require successful save/load return values.

For fast consecutive commits, pending combat effects also track both the source
and target's existing movement generations. An NPC response therefore waits for
a still-moving player to arrive even if the NPC itself is stationary. A reset or
new route at either end invalidates the queued visual. This is covered by a small
consecutive-receipt regression; it does not delay the engine's NPC turn or damage.

Latest small regression results after composite/dual-endpoint ordering:
`run.sh`: 46/46 passed; `run_authoritative.sh`: 112/112 passed. Both exited cleanly.
The strengthened main combat and new composite native/headless harnesses still
require their next source-frozen integration run; these small results do not
substitute for rendered visual verification.

Source-frozen actual-main headless integration subsequently passed:
- Combat: 73/73, with one mandatory real NPC response, pending-request input lock,
  exact successful pending save/load, and final save/load with no effect replay
- Composite: 45/45, including arrival-before-attack, one intentional compound
  commit, exact costs, one mandatory NPC response, and load/replay suppression
- Both reports' start/end source hashes match. Observed composite result was a
  real melee graze for 1 HP; each NPC full hit applied 2 HP and authored poison

These are headless results. Native pixels and natural-time effect visibility are
not implied by them. Frozen-clock native captures are labelled shape/alignment
proofs and record frame timing plus geometry submission data separately.
