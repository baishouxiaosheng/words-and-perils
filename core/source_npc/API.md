# Source-bound finite NPC core v1

Pure catalogue, mutable typed state, frozen focus, public projection and a resolver.
No terrain or renderer preloads, provider calls, economy, combat, relationship state,
legacy keeper/wine/lamp effects or second transaction engine are introduced.

## Ownership and admission

Source authenticates physical placement against its actual admitted village and
navigation. It then builds the immutable finite descriptor and catalogue. Generic
catalogue hashes prove transport consistency, **not** that geometry was authenticated.
Source must deterministically rebuild catalogue/reservation and compare exact immutable
metadata on load; rehashing arbitrary user data is not valid Source admission.

Metadata keeps old item/static bindings separate and adds:

- npc_profile: generated_v3_village_npc/v1 (Source's chosen immutable profile)
- npc_catalog: the complete catalogue
- npc_catalog_hash: catalogue digest
- base_village_runtime_hash: the V18 village runtime identity
- existing source_contract/content_hash/geometry_hash/placement_hash are unchanged

Catalog.build(profile_id, base_identity, descriptors) returns {ok,catalog} or a
canonical failure. Source identity binds source_contract, content_hash, geometry_hash,
source_runtime_hash=base_identity.runtime_hash, and placement_hash.
Catalog.stable_id(profile_id, base_identity, placement_witness, role) is required for
NPC ids. It binds profile, source_identity (source, geometry, village runtime and
placement hash), settlement_id, immutable role slot (placement_witness.role), and actor
role. It deliberately excludes pose, support, actor_id, contact and location revision,
so a logical NPC retains identity when its placement input changes. The catalogue hash
still covers the exact reservation and Source reconstructs/authenticates it; a rehashed
pose is not sufficient Source admission. Duplicate logical role-slot NPC IDs are rejected. Safe IDs use only ASCII letters,
digits, underscore, period, colon and hyphen, max128 characters.

Each descriptor has exact fields:

    id, kind="actor", name, description, role, faction,
    health={current,max}, stamina={current,max},
    inventory=[], statuses={}, hooks=[], scene_id, hex,
    location_revision=0, placement_witness, topics, facts

placement_witness exact fields:

    schema_version, placement_hash, settlement_id, role, hex,
    position_q40=[x,y,z], position_scale=1099511627776, support_witness

support_witness is finite bounded Source-authored data, physically authenticated by
Source, not the generic module. Source should include exact source/geometry bindings,
fixed frame/scale/footprint and support proof. These are public placement evidence.
Do not put secret dialogue or fact answers into the witness.

topics maps stable id to {id,label,fact_ids:[...]}. facts maps stable fact id to
{id,summary,payload:{...}}. Every fact belongs to exactly one topic; fact IDs are
globally unique across this catalogue. The generic bounds are16 NPCs,8 topics and16
facts per NPC,16KiB per descriptor,64KiB catalogue. Initial Source installs only one
NPC and one cooperative directions topic.

Catalog.actor_from_descriptor(d) provides the exact common actor dictionary, excluding
kind/placement/topics/facts. Catalog.validate_world(state) checks its identity,
location, unchanged actor shape and no collision with items/scenes/static catalogs.

## Mutable state and typed patch

State.empty(catalog, observer_ids=["actor_player"]) returns:

    schema_version="source_npc_state/v1"
    contacts[npc_id]={revision,contacted,conversation_count,
                      last_action_id,last_action_start_turn}
    learned_facts[observer_id][fact_id]={fact_id,npc_id,topic_id,catalog_hash,
                      evidence_hash,summary,payload,first_action_id,
                      first_action_start_turn}

Initial contact is revision/count0, contacted=false, last_action_id="",
last_action_start_turn=-1. Contacts cap at1,000,000. The typed state caps at128KiB and
64 observers. Knowledge summary/payload must exactly match finite catalogue data.
Evidence hash binds the source identity, catalogue, exact NPC reservation, topic and
fact definition under source_npc_fact_evidence/v1. Model-created facts are rejected.

State.make_patch(world, observer_id, npc_id, topic_id, action_id) returns the exact
npc_conversation_record patch or {}. Patch fields are:

    type,observer_id,npc_id,topic_id,catalog_hash,expected_revision,
    action_id,action_start_turn,facts:[exact first-proof records]

All start-turn fields mean the zero-based world.turn at action start. They are not
the receipt's committed turn, which Engine advances by1. The first legitimate talk
starting at turn0 records first_action_start_turn=0; committed state has turn1.
Repeats increment contact revision/count and latest action/start turn but copy the
original learned record unchanged, with no duplicate fact or replacement evidence.

State.validate_world(state) performs intrinsic/type/catalog consistency and accepts
a prospective one-action branch before Engine increments turn. State.validate_committed
adds count<=world.turn and all recorded start turns<world.turn; Source must call this
for committed outer saves. Partial npc_* metadata fails closed. Unrelated worlds
with no NPC markers retain existing behavior, including legacy scalar/null/array
metadata that this optional module does not reinterpret. Typed NPC state with malformed
metadata and partial NPC profile/hash markers are rejected.

World dispatches State.apply(state,patch), State.validate_world and State.stable.
apply validates the exact finite patch, prepares/validates a detached typed block and
publishes only on success. It never charges stamina or advances turn. stable permits
only unchanged state or an exact finite-topic, one-contact transition and retains
all old first-proof records. World actor_pool_delta charges1 stamina; Engine advances1
turn and owns rollback, branch freezing and receipt/replay.

State.public_effect(patch) returns {type,observer_id,npc_id,topic_id,
contact_revision,newly_learned_facts,already_known_fact_ids,action_id,action_start_turn}
for an already validated frozen patch. It never looks up live state or current
knowledge. fact.first_action_id==patch.action_id distinguishes acquisition from repeat.
Newly learned entries contain readable trusted summary/payload and first evidence. Engine can also project patch.facts explicitly for repeated dialogue;
it must distinguish redisplaying known facts from a new acquisition.

## Focus and projection

Focus.VERSION = source-npc-focus/v1

- make_reference(id,state), resolve(reference,state), reference_for(focus)
- validate_historical(focus,state) returns error array, empty on success
- references carry world_id,kind=actor,id,hex,scene_id,catalog_version,catalog_id,
  location_revision and contact_revision
- internal frozen facts carry exact actor, public contact state, descriptor,
  source/catalog identities, supporting cell and location/reservation witness

Current resolution compares the entire live reference canonically. Every legitimate
conversation invalidates an old live contact revision. Historical validation compares
immutable identities/placements and frozen contact shape; it never resolves contact
facts from current state. Parent pre-action replay must additionally validate the exact
old focus against its actual old snapshot, to authenticate the chronology.

Projection.frozen_focus(focus,cell_fields) uses frozen values only, hides catalogue
fact definitions and exposes only offered topic ids/labels. Projection.target_summary
(focus) is a compact independent target witness: id,scene_id,hex,catalog_id,
location_revision,contact_revision,actor,descriptor,public_state. This contains no
unlearned payload or duplicate full supporting-cell/reservation witness.
Projection.learned_facts(npc_state,observer_id) returns already learned facts only.

ModelView provides /npc_targets/<npc_id> using target_summary for each available
registered target. This is independent of selected attention; selecting a different
cell or entity never silently changes the requested target or grants interaction.
64KiB request budget remains unchanged; the full selected witness appears only once.

## Resolver

Conversation.new(range_check_callable) has resolver_id source_npc_conversation_v1
and implements action_schema/attempt_key/attempt_fingerprint/check_policy/freeze.
Callback signature is (snapshot,actor_id,target_actor_id) -> bool or {ok:bool}.
Core first enforces living observer, same scene, hex distance<=1, sufficient stamina,
exact offered topic, valid talk component and correct frozen target witness. Source
must additionally verify same cell or an actual directly connected navigation edge.
Missing/denied callback fails closed. Callback receives a detached snapshot.

One talk component uses A,D in0..4, P in-2..2 through the existing generic numeric
validator. Trusted policy is safe_direct and the unmodified release_v1 calculator
produces direct_success with no die domain or random draw. Disposition is advisory.
Every intent still enters Engine's model assessment or explicitly labelled, exactly
validated offline preset path. Assessments cannot supply patches or new fact payloads.
Freeze contains both boolean outcome branches for existing Engine completeness rules;
the safe_direct policy always selects the successful branch. Repeat fingerprints
include changed contact state, so a legitimate second conversation is not replayed.

Required facts: /actors/<actor_id> and /npc_targets/<target_actor_id>.
Unknown topics, forged target witnesses, extra effect parameters, stale references,
range/stamina refusal and cancellation grant no new state.

## Tests and verification status

Tests are under tests/source_npc. test_core.gd covers catalogue/collision/common actor
shape, safe IDs, integral float/int canonicalization in both directions, frozen vs
current/history, malformed/rehashed metadata, finite fact identity/evidence, first-proof
preservation, repeats, costs, range callback and unchanged release formula.

The pure-module test suite is separate from source admission, history replay,
rendering and end-to-end UI acceptance. Release evidence must refer to the exact
source generation tested and include the integrated save/recovery and projection
budget gates. A passing parser or synthetic core test alone does not establish
playable-profile acceptance.
