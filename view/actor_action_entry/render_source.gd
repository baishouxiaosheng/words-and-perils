extends RefCounted
## Read-only rendering bridge over an admitted v2 source. No authority admission,
## model projection or alternate world is constructed here. Geometry/navigation
## remain owned by the original source; only the renderer residency map is aliased.
const Source = preload("res://view/actor_action_profile_v2/source.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCENE = "scene_generated_v3"
const ITEM = "item_travel_bundle"
const RENDERER_PROFILE = "structured_v1"
var _authority: RefCounted
var profile: String:
	get: return Source.PROFILE
var world: Dictionary:
	get: return _authority.world.duplicate(true)
var data: Dictionary:
	get: return _authority.base.data.duplicate(true)
var authority_identity: Dictionary:
	get: return _authority.identity.duplicate(true)
var renderer_identity: Dictionary:
	get: return _authority.base.identity.duplicate(true)
# Compatibility getter for existing geometry/residency/item-view consumers only.
# Its old generated metadata is NOT the authority profile: use profile_id().
var identity: Dictionary:
	get: return renderer_identity
var renderer_bundle: Dictionary:
	get: return _authority.base.renderer_bundle
var navigation: RefCounted:
	get: return _authority.navigation
var base_navigation: RefCounted:
	get: return _authority.navigation
var placement_result: Dictionary:
	get: return _authority.base.placement_result.duplicate(true)
var npc_placement_result: Dictionary:
	get: return _authority.base.npc_placement_result.duplicate(true)
var enemy_placement_result: Dictionary:
	get: return _authority.base.enemy_placement_result.duplicate(true)
var vegetation_result: Dictionary:
	get: return {}
var features: Dictionary:
	get: return {"vegetation": false}
var npc_reservations: Array:
	# EnemySource also includes its initial enemy reservation; this bridge exposes
	# only stationary NPC exclusions so a moved enemy cannot collide with itself.
	get: return _authority.base.base_source.npc_reservations.duplicate(true)
var spawn_component: Dictionary:
	get: return _authority.base.spawn_component.duplicate(true)
var npc_id: String:
	get: return str(_authority.base.npc_id)
var enemy_id: String:
	get: return Source.ACTORS[1]

func _init(admitted_source: RefCounted) -> void:
	_authority = admitted_source

func profile_id() -> String: return Source.PROFILE
func render_owner() -> RefCounted: return _authority.base
func validate_state(state: Variant) -> Dictionary:
	return _authority.validate_state(state) if _authority != null else C.fail("ACTOR_RENDER_SOURCE", "No admitted actor source.")
func static_reference(id: String, clicked_hex: Array = []) -> Dictionary:
	# Static catalogs are immutable; using the v2 world is essential here.
	return StaticFocus.make_reference(id, _authority.world, clicked_hex)
func vegetation_reference(_id: String, _state: Dictionary) -> Dictionary: return {}
func render_state(state: Dictionary) -> Dictionary:
	# Existing boards obtain raw terrain through source.data. Do not add keys to
	# the authority snapshot, which would violate v2's exact state schema.
	return state.duplicate(true) if validate_state(state).get("ok", false) else {}
