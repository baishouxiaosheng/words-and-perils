extends RefCounted
const StatusDetails = preload("res://view/status_gameplay/details.gd")
## Attention is exact contextual evidence, never an action or a gameplay rule.
const NPCFocus = preload("res://core/source_npc/focus.gd")
const VegetationFocus = preload("res://core/generated_v3_vegetation/focus.gd")
const StaticEntityFocus = preload("res://core/source_entities/static_focus.gd")
const SourceEntityFocus = preload("res://core/source_entities/focus.gd")
const GeneratedItemFocus = preload("res://view/generated_inventory/item_focus.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const VERSION := 1
const Entities = preload("res://view/playable_build/entity_catalog.gd")
const Creative = preload("res://view/playable_build/creative_content.gd")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Layout=preload("res://shared/scene_feature_layout.gd")
const Field=preload("res://view/terrain_field.gd")
const KINDS := ["actor","tile","settlement","mountain","tree","prop","district","item","passage_edge"]
const REFERENCE_FIELDS := ["world_id","kind","id","hex","catalog_version","entity_revision","scene_id"]
var source_hexes:Dictionary={}
var source_generated:Dictionary={}
var source_world_id:=""
var layout_field
var layout_tiles:Dictionary={}
var configure_count:=0

func resolve(reference:Variant,snapshot:Dictionary)->Dictionary:
	if not reference is Dictionary:return _fail("Attention focus must be an object.")
	if reference.is_empty():return {"ok":true,"focus":{}}
	if reference.get("catalog_version")==NPCFocus.VERSION:return NPCFocus.resolve(reference,snapshot)
	if reference.get("catalog_version")==VegetationFocus.VERSION:return VegetationFocus.resolve(reference,snapshot)
	if _registered_npc(reference.get("id"),snapshot):return _fail("村民目标需要完整的身份和交谈记录，请重新选择。")
	if reference.get("catalog_version")==StaticEntityFocus.VERSION:return StaticEntityFocus.resolve(reference,snapshot)
	if reference.get("catalog_version")==SourceEntityFocus.VERSION:return SourceEntityFocus.resolve(reference,snapshot)
	for key in reference:
		if not key in REFERENCE_FIELDS:return _fail("Attention reference contains unsupported field: "+str(key))
	if not reference.get("kind") is String or not reference.kind in KINDS or not reference.get("id") is String or reference.id.is_empty():return _fail("Attention reference requires a supported kind and stable ID.")
	if not reference.get("world_id") is String or reference.world_id!=snapshot.get("world_id"):return _fail("Attention reference belongs to a different world.")
	if reference.has("scene_id") and (not reference.scene_id is String or not snapshot.get("scenes",{}).has(reference.scene_id)):return _fail("Unknown focused scene.")
	if reference.has("catalog_version") and not reference.catalog_version is String:return _fail("Attention catalog version must be a string.")
	var kind:String=reference.kind;var id:String=reference.id
	if reference.get("catalog_version") == GeneratedItemFocus.VERSION:
		return GeneratedItemFocus.resolve(reference, snapshot)
	if reference.get("catalog_version") == Creative.FOCUS_VERSION:
		return _resolve_creative(reference, snapshot)
	if reference.get("catalog_version") == Entities.VERSION:
		return _resolve_entity(reference, snapshot)
	if reference.kind in ["prop","district","item","passage_edge"]: return _fail("Scene prop requires an active source catalog reference.")
	var facts:Dictionary={};var hex:Array=[]
	match kind:
		"actor":
			if not snapshot.get("actors",{}).has(id):return _fail("Unknown focused actor ID.")
			facts=snapshot.actors[id].duplicate(true);hex=facts.hex.duplicate()
			if snapshot.has("status_foundation"):facts["status_details"]=StatusDetails.public_details(snapshot,snapshot.actors[id])
		"tile":
			for cell in snapshot.get("hexes",{}).values():
				if cell is Dictionary and cell.get("id")==id:facts=cell.duplicate(true);hex=[cell.q,cell.r];break
			if facts.is_empty():
				for scene_map in snapshot.get("scene_hexes",{}).values():
					for cell in scene_map.values():
						if cell.get("id")==id:facts=cell.duplicate(true);hex=[cell.q,cell.r];break
			if facts.is_empty():return _fail("Unknown focused tile ID.")
		"settlement":
			for site in _settlements(snapshot):
				if site is Dictionary and site.get("id")==id:facts=site.duplicate(true);hex=site.hex.duplicate();break
			if facts.is_empty():return _fail("Unknown focused settlement ID.")
		"mountain":
			if not _valid_hex(reference.get("hex"),snapshot):return _fail("Mountain focus requires a valid supporting hex.")
			hex=reference.hex.duplicate()
			var cell:Dictionary=snapshot.hexes[_key(hex)]
			var ids:Array=[cell.get("mountain_region",""),cell.get("range_id",""),cell.get("plateau_region","")]
			if cell.get("terrain")=="mountain":ids.append("mountain_"+String(cell.id))
			if id.strip_edges().is_empty() or not id in ids:return _fail("Mountain ID is not supported by the clicked cell facts.")
			facts={"supporting_cell":cell.duplicate(true),"region_id":id,"scope":"supporting_cell"}
			var metadata:Dictionary=snapshot.get("generated_world",{})
			var macro=metadata.get("macro_landscape",{})
			if not macro is Dictionary:macro={}
			var regions:Array=[]
			for source in [metadata.get("mountain_regions",[]),macro.get("mountain_ranges",[]),macro.get("plateaus",[])]:
				if source is Array:regions.append_array(source)
			for region in regions:
				if region is Dictionary and region.get("id")==id:facts["region"]=region.duplicate(true);facts["scope"]="region_with_clicked_cell"
		"tree":
			if reference.get("catalog_version")!=Layout.VERSION or not _valid_hex(reference.get("hex"),snapshot):return _fail("Tree focus requires a supported recipe and valid supporting hex.")
			hex=reference.hex.duplicate()
			if not _configure_layout(snapshot):return _fail("Observable feature sampler rejected world metadata.")
			for tree in Layout.trees_for_tile(layout_tiles[_key(hex)],layout_tiles,layout_field, String(snapshot.world_id)):
				if tree.id==id:facts={"observable_feature":_observable_tree(tree),"supporting_cell":snapshot.hexes[_key(hex)].duplicate(true),"presentation_only":true,"patchable_entity":false};break
			if facts.is_empty():return _fail("Tree ID does not exist in the exact observable recipe.")
	var scene_id: String = facts.get("scene_id",facts.get("supporting_cell",{}).get("scene_id",""))
	if reference.has("scene_id") and reference.scene_id!=scene_id:return _fail("Focused identity belongs to another scene.")
	if reference.has("hex") and (not _valid_hex(reference.hex,snapshot,scene_id) or Canonical.bytes(reference.hex)!=Canonical.bytes(hex)):return _fail("Focused ID does not match its supporting hex.")
	var focus={"schema_version":VERSION,"world_id":snapshot.world_id,"kind":kind,"id":id,"hex":hex,"facts":facts}
	if reference.has("scene_id") or snapshot.get("scene_hexes",{}).has(scene_id):focus.scene_id=scene_id
	if kind=="tree":focus["catalog_version"]=Layout.VERSION
	return {"ok":true,"focus":_normalized(focus)}

func reference_for(focus:Dictionary)->Dictionary:
	if focus.is_empty():return {}
	if focus.get("catalog_version")==NPCFocus.VERSION:return NPCFocus.reference_for(focus)
	if focus.get("catalog_version")==VegetationFocus.VERSION:return VegetationFocus.reference_for(focus)
	if focus.get("catalog_version")==StaticEntityFocus.VERSION:return StaticEntityFocus.reference_for(focus)
	if focus.get("catalog_version")==SourceEntityFocus.VERSION:return SourceEntityFocus.reference_for(focus)
	var reference:Dictionary={}
	for key in REFERENCE_FIELDS:
		if focus.has(key):reference[key]=focus[key].duplicate(true) if focus[key] is Dictionary or focus[key] is Array else focus[key]
	return reference

func validate_frozen(value:Variant,snapshot:Dictionary)->Array:
	if not value is Dictionary:return ["Frozen attention focus must be an object."]
	if value.is_empty():return []
	for field in ["schema_version","world_id","kind","id","hex","facts"]:
		if not value.has(field):return ["Missing frozen attention field: "+field]
	var resolved=resolve(reference_for(value),snapshot)
	if not resolved.ok:return resolved.errors
	# New typed catalogs use the same exact top-level schema in pending and history.
	# Legacy focus keeps its pre-existing safe-extension policy.
	if value.get("catalog_version") in [SourceEntityFocus.VERSION,StaticEntityFocus.VERSION,NPCFocus.VERSION,VegetationFocus.VERSION] and not Canonical.exact_fields(value,resolved.focus.keys()):return ["此版本的目标包含未支持字段，请重新选择。"]
	# Unknown safe top-level extensions remain durable for legacy focus.
	for key in resolved.focus:
		if not value.has(key) or JSON.stringify(value[key],"",true,true)!=JSON.stringify(resolved.focus[key],"",true,true):return ["Frozen attention facts do not match the exact action snapshot."]
	return []

func validate_historical(value:Variant,world:Dictionary)->Array:
	# Historical actor/cell facts may differ from the current state after patches.
	# Validate durable shape/identity, never overwrite them with present-day facts.
	if not value is Dictionary:return ["Historical attention focus must be an object."]
	if value.is_empty():return []
	if value.has("catalog_version") and not value.catalog_version is String:return ["Historical catalog version must be a string."]
	if value.get("catalog_version") == NPCFocus.VERSION:return NPCFocus.validate_historical(value,world)
	if value.get("catalog_version") == VegetationFocus.VERSION:return VegetationFocus.validate_historical(value,world)
	if _registered_npc(value.get("id"),world):return ["历史村民目标缺少完整身份记录。"]
	if value.get("catalog_version") == StaticEntityFocus.VERSION:return StaticEntityFocus.validate_historical(value,world)
	if value.get("catalog_version") == SourceEntityFocus.VERSION:return SourceEntityFocus.validate_historical(value,world)
	if value.get("catalog_version") == GeneratedItemFocus.VERSION:return GeneratedItemFocus.validate_historical(value,world)
	if value.get("catalog_version") == Creative.FOCUS_VERSION:return _validate_historical_creative(value,world)
	if value.get("schema_version")!=VERSION or value.get("world_id")!=world.get("world_id") or not value.get("kind") is String or not value.kind in KINDS or not value.get("id") is String or value.id.is_empty() or not value.get("facts") is Dictionary or not _valid_hex(value.get("hex"),world,value.get("scene_id","")):return ["Invalid historical attention descriptor."]
	if value.has("scene_id") and value.facts.get("scene_id",value.facts.get("supporting_cell",{}).get("scene_id",value.facts.get("entity",{}).get("scene_id","")))!=value.scene_id:return ["Historical scene identity differs from frozen facts."]
	if value.get("catalog_version") == Creative.FOCUS_VERSION: return _validate_historical_creative(value, world)
	if value.kind in ["item", "passage_edge"]: return ["Creative focus requires its exact authored catalog reference."]
	if value.get("catalog_version") == Entities.VERSION: return _validate_historical_entity(value, world)
	if value.kind=="actor" and not world.actors.has(value.id):return ["Historical attention references an unknown stable actor."]
	if value.kind=="tree" and (value.get("catalog_version")!=Layout.VERSION or value.facts.get("presentation_only")!=true or value.facts.get("patchable_entity")!=false):return ["Historical tree descriptor cannot become a patchable entity."]
	if value.kind=="actor":
		if value.facts.has("status_details") and not StatusDetails.valid_public_details(value.facts.status_details):return ["Malformed historical status details."]
		if not value.facts.get("name") is String or not value.facts.get("inventory") is Array:return ["Malformed historical actor facts."]
		for pool_name in ["health","stamina"]:
			var pool=value.facts.get(pool_name)
			if not pool is Dictionary or not _finite_number(pool.get("current")) or not _finite_number(pool.get("max")) or pool.current<0 or pool.max<pool.current:return ["Malformed historical actor numeric pool."]
		if value.facts.get("id")!=value.id or value.facts.get("hex")!=value.hex:return ["Historical actor facts do not match focused identity/location."]
	elif value.kind=="tile":
		if not value.facts.get("terrain") is String:return ["Historical tile facts require terrain text."]
		var cell:Dictionary=Cells.cell(world,value.scene_id,value.hex) if value.has("scene_id") else world.hexes[_key(value.hex)]
		if cell.id!=value.id or value.facts.get("id")!=value.id or value.facts.get("q")!=value.hex[0] or value.facts.get("r")!=value.hex[1]:return ["Historical tile identity does not match supporting coordinates."]
	elif value.kind=="settlement":
		if not value.facts.get("name") is String or not value.facts.get("kind") is String or value.facts.get("hex_key")!=_key(value.hex):return ["Malformed historical settlement facts."]
		if value.facts.get("id")!=value.id or value.facts.get("hex")!=value.hex:return ["Historical settlement facts do not match focused identity/location."]
		var found:=false
		for site in _settlements(world):
			if site is Dictionary and site.get("id")==value.id:found=true
		if not found:return ["Historical settlement references an unknown stable site."]
	elif value.kind=="mountain":
		var cell=value.facts.get("supporting_cell")
		if not _supporting_cell(cell,value.hex) or value.facts.get("region_id")!=value.id or not value.facts.get("scope") in ["supporting_cell","region_with_clicked_cell"]:return ["Historical mountain supporting facts are malformed."]
		if value.facts.has("region") and (not value.facts.region is Dictionary or value.facts.region.get("id")!=value.id):return ["Historical mountain region identity differs from focus."]
		var ids:Array=[cell.get("range_id",""),cell.get("mountain_region",""),cell.get("plateau_region","")]
		if cell.get("terrain")=="mountain":ids.append("mountain_"+String(cell.get("id","")))
		if not value.id in ids:return ["Historical mountain identity is unsupported by frozen facts."]
	elif value.kind=="tree":
		var tree=value.facts.get("observable_feature")
		var cell=value.facts.get("supporting_cell")
		if not tree is Dictionary or not tree.get("slot") is int or tree.slot<0 or tree.slot>2 or tree.get("id")!=value.id or tree.get("hex")!=value.hex or tree.get("catalog_version")!=Layout.VERSION or not cell is Dictionary or cell.get("q")!=value.hex[0] or cell.get("r")!=value.hex[1]:return ["Malformed historical vegetation descriptor."]
		if value.id!=Layout.tree_id(String(value.world_id),Vector2i(value.hex[0],value.hex[1]),tree.slot):return ["Historical tree ID differs from world/recipe/cell/slot identity."]
		if not _supporting_cell(cell,value.hex) or not _valid_tree_geometry(tree):return ["Malformed historical tree geometry/supporting cell facts."]
	return []

func _configure_layout(snapshot:Dictionary)->bool:
	var metadata=snapshot.get("generated_world",{})
	if not metadata is Dictionary or not snapshot.get("hexes") is Dictionary:return false
	# Serialized exact equality safely handles legal GM extensions changing types.
	if layout_field!=null and source_world_id==snapshot.world_id and _same_json(source_hexes,snapshot.hexes) and _same_json(source_generated,metadata):return true
	var next_tiles:Dictionary={}
	for key in snapshot.hexes:
		var raw=snapshot.hexes[key]
		if not raw is Dictionary:return false
		next_tiles[key]={"hex":Vector2i(raw.q,raw.r),"terrain":raw.terrain,"raw":raw}
	var next_field=Field.new();configure_count+=1
	if not next_field.configure(next_tiles,metadata):return false
	# Publish only a successfully configured sampler; failed attempts never poison
	# the cache and cannot turn into success on the next identical reference.
	source_world_id=String(snapshot.world_id)
	source_hexes=snapshot.hexes.duplicate(true);source_generated=metadata.duplicate(true)
	layout_tiles=next_tiles;layout_field=next_field
	return true

static func _same_json(a:Variant,b:Variant)->bool:
	return JSON.stringify(a,"",true,true)==JSON.stringify(b,"",true,true)

static func _key(h:Array)->String:return "%d,%d"%[int(h[0]),int(h[1])]
static func _valid_hex(h:Variant,world:Dictionary,scene_id:String="")->bool:
	if not scene_id.is_empty():return Cells.valid_hex(h,world,scene_id)
	if not h is Array or h.size()!=2:return false
	for coordinate in h:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate)!=floorf(float(coordinate)) or absf(float(coordinate))>1000:return false
	return world.get("hexes") is Dictionary and world.hexes.has(_key(h))
static func _fail(message:String)->Dictionary:return {"ok":false,"errors":[message]}

static func _normalized(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[String(key)]=_normalized(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_normalized(item))
		return result
	if value is float and is_finite(value) and value==floorf(value) and absf(value)<=9007199254740991.0:return int(value)
	if value is StringName:return String(value)
	return value

static func _observable_tree(tree: Dictionary) -> Dictionary:
	# Render recipe retains full original transforms. JSON-visible coordinates are
	# binary-quantized descriptive metadata; exact IEEE bytes remain inspectable.
	# Godot JSON.parse does not roundtrip all tiny arbitrary decimal doubles.
	var facts:Dictionary=tree.duplicate(true)
	var bits:Array=[]
	var positions:Array=[]
	for coordinate in tree.local_position:
		bits.append(PackedFloat64Array([float(coordinate)]).to_byte_array().hex_encode())
		positions.append(snappedf(float(coordinate),1.0/4096.0))
	facts["local_position"]=positions
	facts["size"]=snappedf(float(tree.size),1.0/4096.0)
	facts["descriptive_numeric_quantum"]=1.0/4096.0
	facts["exact_recipe_transform_f64_hex"]={"local_position":bits,"size":PackedFloat64Array([float(tree.size)]).to_byte_array().hex_encode(),"encoding":"Godot PackedFloat64Array little-endian bytes; descriptive positions are rounded, render recipe is unchanged"}
	return facts

static func _settlements(world:Dictionary)->Array:
	var metadata=world.get("generated_world")
	if not metadata is Dictionary:return []
	return metadata.settlements if metadata.get("settlements") is Array else []

static func _finite_number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=9007199254740991.0

static func _supporting_cell(cell:Variant,hex:Array)->bool:
	return cell is Dictionary and cell.get("q")==hex[0] and cell.get("r")==hex[1] and cell.get("id")=="hex_%d_%d"%[int(hex[0]),int(hex[1])] and cell.get("terrain") is String

static func _valid_f64_hex(value:Variant)->bool:
	if not value is String or value.length()!=16:return false
	for character in value:
		if not character in "0123456789abcdef":return false
	return is_finite(value.hex_decode().decode_double(0))

static func _valid_tree_geometry(tree:Dictionary)->bool:
	if not tree.get("vegetation_type") in ["conifer","broadleaf"] or not tree.get("local_position") is Array or tree.local_position.size()!=3 or not _finite_number(tree.get("size")) or tree.size<=0 or tree.get("descriptive_numeric_quantum")!=1.0/4096.0:return false
	var bits=tree.get("exact_recipe_transform_f64_hex")
	if not bits is Dictionary or not bits.get("local_position") is Array or bits.local_position.size()!=3 or not _valid_f64_hex(bits.get("size")) or not bits.get("encoding") is String:return false
	for i in range(3):
		if not _finite_number(tree.local_position[i]) or not _valid_f64_hex(bits.local_position[i]):return false
		if snappedf(bits.local_position[i].hex_decode().decode_double(0),1.0/4096.0)!=tree.local_position[i]:return false
	return snappedf(bits.size.hex_decode().decode_double(0),1.0/4096.0)==tree.size

func _resolve_entity(reference: Dictionary, snapshot: Dictionary) -> Dictionary:
	var entity := Entities.entity(reference.id, snapshot)
	if entity.is_empty(): return _fail("Focused scene object is missing or belongs to an inactive world bundle.")
	if reference.has("scene_id") and reference.scene_id!=entity.scene_id:return _fail("Focused object belongs to another scene.")
	if reference.kind != entity.kind or not _valid_hex(reference.get("hex"), snapshot) or not Entities.supports_hex(entity, reference.hex): return _fail("Focused object kind or supporting cell is out of range.")
	if not Entities.exact_integer(reference.get("entity_revision")) or reference.entity_revision != entity.state.revision: return _fail("Focused object changed since selection; select it again.")
	var focus := {"schema_version": VERSION, "world_id": snapshot.world_id, "kind": entity.kind, "id": entity.id, "hex": reference.hex.duplicate(), "catalog_version": Entities.VERSION, "entity_revision": entity.state.revision,
		"facts": {"entity": entity, "supporting_cell": snapshot.hexes[_key(reference.hex)].duplicate(true), "selection_is_action": false}}
	if reference.has("scene_id"):focus.scene_id=entity.scene_id
	return {"ok": true, "focus": _normalized(focus)}

func _validate_historical_entity(value: Dictionary, world: Dictionary) -> Array:
	var descriptor := Entities.descriptor(value.id)
	if descriptor.is_empty() or descriptor.kind != value.kind or descriptor.bundle_id != world.get("generated_world", {}).get("bundle_id") or not Entities.supports_hex(descriptor, value.hex): return ["Historical scene object is outside the active immutable catalog."]
	var entity = value.facts.get("entity")
	if not entity is Dictionary or not entity.get("state") is Dictionary or not entity.get("public_facts") is Dictionary or not _supporting_cell(value.facts.get("supporting_cell"), value.hex) or value.facts.get("selection_is_action") != false: return ["Malformed historical scene object facts."]
	for key in descriptor:
		if key == "public_facts" and descriptor.kind == "prop":
			var public_: Dictionary = entity.get(key, {}).duplicate(true)
			if not public_.get("lit") is bool: return ["Historical lamp state is malformed."]
			var expected_lamp: Dictionary = descriptor[key].duplicate(true)
			if public_.lit: expected_lamp.description = "旧灯已经修复并重燃。"
			public_.erase("lit")
			if not _same_json(_normalized(public_), _normalized(expected_lamp)): return ["Historical lamp description changed."]
		elif key == "public_facts" and descriptor.kind == "tree":
			var expected: Dictionary = descriptor.public_facts.duplicate(true)
			if entity.state.get("posture") == "fallen": expected.visible_form = "fallen_vegetation"
			if not _same_json(_normalized(entity.get(key)), _normalized(expected)): return ["Historical tree form differs from its frozen state."]
		elif not entity.has(key) or not _same_json(_normalized(entity[key]), _normalized(descriptor[key])): return ["Historical scene object differs from its immutable source descriptor."]
	if descriptor.kind in ["settlement","district"]:
		if not preload("res://view/playable_build/settlement_content.gd").active(world) or not preload("res://view/playable_build/settlement_content.gd").valid_entity_state(entity.state) or value.get("entity_revision")!=entity.state.revision: return ["Historical settlement gate state/revision is invalid."]
		return []
	var initial := Entities.initial_state(value.id)
	if not _same_json(initial, _normalized(entity.state)) and not Entities.validate_record(value.id, {"id": value.id, "state": entity.state}): return ["Historical object state is not a supported public state."]
	if value.get("entity_revision") != entity.state.revision: return ["Historical object revision differs from frozen attention."]
	return []

static func validate_scene_scope(focus: Dictionary, snapshot: Dictionary, actor_id: String = "actor_player") -> bool:
	# Runtime caller supplies the acting actor. Historical validation deliberately
	# does not use the current active scene; it preserves the frozen past context.
	if focus.is_empty(): return true
	var actor: Dictionary = snapshot.get("actors", {}).get(actor_id, {})
	if not actor.get("scene_id") is String: return true # Legacy worlds lack scenes.
	var facts: Dictionary = focus.get("facts",{})
	var scene_id: String = focus.get("scene_id",facts.get("scene_id",facts.get("supporting_cell",{}).get("scene_id","")))
	if scene_id.is_empty() and facts.get("entity") is Dictionary:scene_id=facts.entity.get("scene_id","")
	if scene_id.is_empty():scene_id=snapshot.get("hexes",{}).get(_key(focus.hex),{}).get("scene_id","")
	return scene_id==actor.scene_id and _valid_hex(focus.get("hex"),snapshot,scene_id)


func _resolve_creative(reference: Dictionary, snapshot: Dictionary) -> Dictionary:
	var current := Creative.make_reference(str(reference.get("id", "")), snapshot)
	if current.is_empty() or not _same_json(_normalized(reference), _normalized(current)): return _fail("Focused physical object, custody or passage changed; select it again.")
	var facts := Creative.focus_facts(reference.id, snapshot)
	if facts.is_empty(): return _fail("Focused physical object has no valid public supporting cell.")
	var focus := current.duplicate(true)
	focus.schema_version = VERSION; focus.facts = facts
	return {"ok": true, "focus": _normalized(focus)}

func _validate_historical_creative(value: Dictionary, world: Dictionary) -> Array:
	if not Creative.active(world) or not Canonical.exact_fields(value,["schema_version","world_id","kind","id","hex","scene_id","catalog_version","entity_revision","facts"]): return ["Historical creative focus lacks its source-bound catalog."]
	if not Canonical.integer(value.schema_version) or value.schema_version!=VERSION or not value.world_id is String or value.world_id!=world.world_id or not value.kind in ["item","passage_edge"] or not value.id is String or not value.scene_id is String or not _valid_hex(value.hex,world,value.scene_id) or not value.facts is Dictionary or not Canonical.integer(value.entity_revision) or value.entity_revision<0: return ["Invalid historical creative identity."]
	var facts: Dictionary=value.facts
	var support: Variant=facts.get("supporting_cell")
	if not support is Dictionary or not Canonical.integer(support.get("q")) or not Canonical.integer(support.get("r")) or not support.get("id") is String or not support.get("terrain") is String or not _supporting_cell(support,value.hex): return ["Invalid historical creative support."]
	if not facts.get("scene_id") is String or facts.scene_id!=value.scene_id or not facts.get("selection_is_action") is bool or facts.selection_is_action or not _same_json(_normalized(facts.get("physical_catalog")),_normalized(Creative.metadata())): return ["Historical creative catalog or read-only context differs."]
	if value.kind=="item":
		if not Canonical.exact_fields(facts,["scene_id","physical_catalog","supporting_cell","selection_is_action","item","placement"]) or not value.id in Creative.ITEM_IDS or not facts.item is Dictionary or not facts.placement is Dictionary: return ["Malformed historical physical item facts."]
		var item: Dictionary=facts.item;var original: Dictionary=Creative.items()[value.id]
		for field in ["id","quantity","physical_traits","interaction_profile"]:
			if not _same_json(_normalized(item.get(field)),_normalized(original[field])): return ["Historical physical item changed immutable traits."]
		for field in item:
			if not field in Creative.PUBLIC_ITEM_FIELDS:return ["Historical physical item has an unsupported field."]
		if not item.get("name") is String or not item.get("description") is String or not Canonical.integer(item.get("custody_revision",0)) or item.get("custody_revision",0)<0:return ["Historical physical item name or custody revision is invalid."]
		if item.has("owner_actor_id"):
			if not item.owner_actor_id is String or not world.actors.has(item.owner_actor_id) or item.has("hex") or item.has("scene_id") or not facts.placement.is_empty():return ["Historical carried item also has a ground placement."]
		elif not _same_json(item.get("hex"),value.hex) or not item.get("scene_id") is String or item.scene_id!=value.scene_id:return ["Historical ground item differs from its support."]
		if not facts.placement.is_empty():
			var placement: Dictionary=facts.placement
			if not Canonical.exact_fields(placement,["schema_version","target_id","anchor_id","posture","revision"]) or not placement.schema_version is String or placement.schema_version!="anchor_pose/v1" or not placement.target_id is String or not world.passage_targets.has(placement.target_id) or not placement.posture in ["loose","braced"] or not Canonical.integer(placement.revision) or placement.revision<0:return ["Historical item anchor pose is invalid."]
			var target: Dictionary=world.passage_targets[placement.target_id]
			if not placement.anchor_id is String or placement.anchor_id!=target.anchor_id or not _same_json(value.hex,target.support_hex):return ["Historical item anchor support is invalid."]
		if value.entity_revision!=Creative.item_focus_revision(item,facts.placement,value.hex,value.scene_id):return ["Historical item revision differs from its frozen public custody and pose."]
	else:
		if not Canonical.exact_fields(facts,["scene_id","physical_catalog","supporting_cell","selection_is_action","passage_target","state"]) or not world.passage_targets.has(value.id) or not _same_json(_normalized(facts.passage_target),_normalized(world.passage_targets[value.id])):return ["Historical passage changed immutable source geometry."]
		if not _same_json(value.hex,facts.passage_target.support_hex):return ["Historical passage support differs."]
		var state: Variant=facts.state
		if not Canonical.exact_fields(state,["posture","revision","ground_blocking","relation"]) or not Canonical.integer(state.revision) or state.revision!=value.entity_revision or not state.posture in ["open","braced"] or not state.ground_blocking is bool or not state.relation is Dictionary:return ["Malformed historical passage state."]
		if state.ground_blocking!=(state.posture=="braced") or (state.posture=="open" and not state.relation.is_empty()):return ["Historical passage posture and blocking disagree."]
		if state.posture=="braced":
			var relation: Dictionary=state.relation
			if not Canonical.exact_fields(relation,["schema_version","id","mechanism","source_item_id","target_id","source_deployment_revision","target_revision","active","revision"]):return ["Historical brace relation fields are invalid."]
			for field in ["schema_version","id","mechanism","source_item_id","target_id"]:
				if not relation[field] is String:return ["Historical brace identity types are invalid."]
			for field in ["source_deployment_revision","target_revision","revision"]:
				if not Canonical.integer(relation[field]) or relation[field]<0:return ["Historical brace revision types are invalid."]
			if relation.schema_version!="interaction_relation/v1" or relation.mechanism!="span_brace/v1" or relation.id!="brace_"+Canonical.digest(["span_brace/v1",relation.source_item_id,relation.target_id]) or not relation.source_item_id in Creative.ITEM_IDS or relation.target_id!=value.id or relation.target_revision!=facts.passage_target.revision or not relation.active is bool or not relation.active:return ["Historical brace relation is invalid."]
	return []

static func _registered_npc(id: Variant,state: Dictionary) -> bool:
	var metadata: Variant = state.get("generated_world",{})
	return metadata is Dictionary and metadata.get("npc_catalog") is Dictionary and metadata.npc_catalog.get("entries") is Dictionary and metadata.npc_catalog.entries.has(id)
