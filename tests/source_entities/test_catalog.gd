extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog=preload("res://core/source_entities/catalog.gd")
const Focus=preload("res://core/source_entities/focus.gd")
const PublicProjection=preload("res://core/source_entities/projection.gd")
const FocusContract=preload("res://core/focus_contract.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
var checks:=0
var failures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("ENTITY_FOCUS_FAIL ",label)
func descriptor(id:String,name_:String) -> Dictionary:
	return {"id":id,"kind":"item","name":name_,"description":"只用于目录单元测试的登记物品。","quantity":1,"interaction_profile":{"schema_version":"coast_item_interaction/v1","movable":true,"equip_slot":""}}
func fixture() -> Dictionary:
	var base:Dictionary={"source_contract":"unit_source/v1","content_hash":"1".repeat(64),"geometry_hash":"2".repeat(64),"runtime_hash":"3".repeat(64)}
	var built:Dictionary=Catalog.build("unit_inventory/v1",base,[descriptor("item_a","甲包"),descriptor("item_b","乙包")])
	var state:Dictionary={"world_id":"unit_multi_entities","turn":5,"actors":{"actor_player":{"id":"actor_player","scene_id":"unit_scene","hex":[0,0],"inventory":["item_a"]},"actor_other":{"id":"actor_other","scene_id":"unit_scene","hex":[1,0],"inventory":["item_b"]}},"items":{},"hexes":{},"scenes":{"unit_scene":{"id":"unit_scene"}},"generated_world":{"source_contract":base.source_contract,"content_hash":base.content_hash,"geometry_hash":base.geometry_hash,"base_runtime_hash":base.runtime_hash,"runtime_hash":"4".repeat(64),"profile":"unit_inventory/v1","inventory_profile":"unit_inventory/v1","entity_profile":"unit_inventory/v1","entity_catalog_hash":built.catalog.catalog_hash,"entity_catalog":built.catalog}}
	for i in range(3):state.hexes["%d,0"%i]={"id":"hex_"+str(i),"scene_id":"unit_scene","q":i,"r":0,"terrain":"grass","source_cell_version":"generated_v3_cell/v1","biome":"dry_steppe","elevation":.5,"ground_blocked":false,"air_blocked":false,"all_blocked":false,"secret_cell_note":"not public"}
	for pair in [["item_a","甲包","actor_player",2],["item_b","乙包","actor_other",3]]:
		var item:Dictionary=descriptor(pair[0],pair[1]);item.erase("kind");item.owner_actor_id=pair[2];item.custody_revision=pair[3];state.items[pair[0]]=item
	return C.normalized(state)
func run() -> void:
	var state:=fixture();var before:=C.bytes(state)
	check(Catalog.validate_world(state).ok,"generic catalog accepts a source-neutral fixture")
	var a:=Focus.make_reference("item_a",state);var b:=Focus.make_reference("item_b",state)
	check(not a.is_empty() and not b.is_empty() and a.id!=b.id and a.catalog_id==b.catalog_id,"two stable item IDs share one immutable catalog")
	check(b.entity_revision==3 and b.hex==[1,0],"read-only custody is tagged, not carried-even parity")
	var af:Dictionary=Focus.resolve(a,state).focus;var bf:Dictionary=Focus.resolve(b,state).focus
	check(af.facts.item.name=="甲包" and bf.facts.item.name=="乙包" and af.facts.descriptor.id!=bf.facts.descriptor.id,"descriptors cannot bleed between items")
	var bridge:=FocusContract.new()
	check(bridge.resolve(a,state).ok and C.bytes(bridge.reference_for(af))==C.bytes(a),"core dispatch retains complete catalog reference")
	check(bridge.validate_frozen(af,state).is_empty(),"exact pending snapshot focus validates")
	var public_before:=ModelView.historical_focus(af,{})
	check(not public_before.facts.supporting_cell.has("secret_cell_note") and public_before.facts.supporting_cell.biome=="dry_steppe","explicit source-cell whitelist preserves public descriptors only")
	check(C.bytes(state)==before,"catalog selection and projection are read-only")
	state.actors.actor_player.hex=[2,0]
	check(not Focus.resolve(a,state).ok,"owner movement invalidates a live reference even without custody revision change")
	check(Focus.make_reference("item_a",state).hex==[2,0],"new live reference follows actual owner")
	check(Focus.validate_historical(af,state).is_empty() and C.bytes(ModelView.historical_focus(af,{}))==C.bytes(public_before),"historical item retains exact prior owner location and public facts")
	check(not bridge.validate_frozen(af,state).is_empty(),"old frozen witness cannot be reused as a new action snapshot")
	state.actors.actor_player.inventory=[];state.items.item_a.erase("owner_actor_id");state.items.item_a.hex=[2,0];state.items.item_a.scene_id="unit_scene";state.items.item_a.custody_revision=4
	check(not Focus.make_reference("item_a",state).is_empty(),"even-revision ground custody remains valid without parity assumptions")
	check(Focus.validate_historical(af,state).is_empty(),"carried history survives later drop")
	var ground:Dictionary=Focus.resolve(Focus.make_reference("item_a",state),state).focus
	check(ground.facts.custody_witness.kind=="ground" and ground.facts.item.hex==[2,0],"ground context carries exact location witness")
	var malformed:Array=[]
	for field in ["world_id","catalog_id","catalog_version","id","scene_id"]:
		var changed:Dictionary=Focus.make_reference("item_a",state);changed[field]="wrong";malformed.append(changed)
	var fractional:Dictionary=Focus.make_reference("item_a",state);fractional.hex=[.5,0];malformed.append(fractional)
	var stale:Dictionary=Focus.make_reference("item_a",state);stale.entity_revision=3;malformed.append(stale)
	for i in range(malformed.size()):check(not Focus.resolve(malformed[i],state).ok,"malformed or stale reference rejected "+str(i))
	var bad:=state.duplicate(true);bad.actors.actor_other.inventory.append("item_a")
	check(Focus.make_reference("item_a",bad).is_empty(),"ground object cannot also appear in an inventory")
	bad=state.duplicate(true);bad.items.item_b.owner_actor_id="missing_actor"
	check(Focus.make_reference("item_b",bad).is_empty(),"unknown owner is rejected")
	bad=state.duplicate(true);bad.actors.actor_other.inventory.append("item_b")
	check(Focus.make_reference("item_b",bad).is_empty(),"duplicate owner inventory entries are rejected")
	bad=state.duplicate(true);bad.generated_world.content_hash="5".repeat(64)
	check(Focus.make_reference("item_a",bad).is_empty(),"source/catalog mismatch fails closed")
	var changed:Dictionary=af.duplicate(true);changed.facts.custody_witness.hex=[1,0]
	check(not Focus.validate_historical(changed,state).is_empty(),"mismatched frozen custody witness rejected")
	changed=af.duplicate(true);changed.facts.item.name="not the immutable descriptor"
	check(not Focus.validate_historical(changed,state).is_empty(),"historical descriptor mutation rejected")
	var base:Dictionary={"source_contract":"unit_source/v1","content_hash":"1".repeat(64),"runtime_hash":"3".repeat(64)}
	check(not Catalog.build("unit_inventory/v1",base,[descriptor("same","甲"),descriptor("same","乙")]).ok,"duplicate stable IDs are rejected before dictionary insertion")
	for id in ["item/a","item~a","item a","item\na","", "背包"]:
		check(not Catalog.build("unit_inventory/v1",base,[descriptor(id,"测试包")]).ok,"unsupported JSON Pointer ID rejected "+id)
	check(Catalog.build("unit_inventory/v1",base,[descriptor("item:v3:abc_01-test","合法ID")]).ok,"versioned composite IDs use an explicit safe alphabet")
	var legacy_ref:Dictionary={"world_id":state.world_id,"kind":"tile","id":"hex_0","hex":[0,0],"catalog_id":"unexpected"}
	check(not bridge.resolve(legacy_ref,state).ok,"legacy reference field contract is not widened")
	DirAccess.make_dir_recursive_absolute("res://artifacts/source_entities")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Synthetic multi-entity catalog unit test; no physical terrain claim"}
	var file:=FileAccess.open("res://artifacts/source_entities/catalog_report.json",FileAccess.WRITE);file.store_string(C.bytes(report));file.close()
	print("SOURCE_ENTITY_CATALOG ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)
