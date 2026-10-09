extends SceneTree
## Compare all real Basic/Composite frozen branches to the pre-isolation code.
## Uses the existing authored coast adapter and actual navigation, no provider.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Adapter=preload("res://view/playable_build/adapter.gd")
const Navigation=preload("res://view/playable_build/navigation.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const OldBasic=preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const OldComposite=preload("res://core/ai_gm_rebuilt/composite_actions.gd")
const BeforeBasic=preload("res://tests/status_compatibility/pre_fix_basic.gd")
const BeforeComposite=preload("res://tests/status_compatibility/pre_fix_composite.gd")
const NewBasic=preload("res://core/status_gameplay/basic_actions.gd")
const NewComposite=preload("res://core/status_gameplay/composite_actions.gd")
var checks:Array=[]
func check(ok:bool,label_:String)->bool:
	checks.append({"passed":ok,"name":label_})
	if not ok:printerr("STATUS_WEAPON_COMPAT_FAIL ",label_)
	return ok
func _initialize()->void:run.call_deferred()
func assessment(state:Dictionary,arrival:Array,composite:bool)->Dictionary:
	var bindings:Dictionary={"actor_id":"actor_player","target_actor_id":"actor_raider","weapon_item_id":"item_coast_staff"}
	if composite:bindings.target_hex=arrival.duplicate()
	var paths:Array=["/actors/actor_player","/actors/actor_raider","/items/item_coast_staff"]
	if composite:paths.append("/hexes/%d,%d"%arrival)
	var refs:Array=[];var ids:Array=[]
	for path in paths:
		var id:String="f"+str(refs.size());refs.append({"id":id,"path":path,"expected":C.pointer(state,path).value});ids.append(id)
	var components:Array=[]
	for id in (["move","accuracy","impact"] if composite else ["accuracy","impact"]):components.append({"id":id,"parameters":{"A":3,"D":1,"P":0},"disposition":"certain","fact_ref_ids":ids.duplicate()})
	return {"resolver_id":OldComposite.ID if composite else "coast_basic_attack_v1","bindings":bindings,"components":components,"fact_refs":refs}
func finish()->void:
	var failures:int=0
	for row in checks:if not row.passed:failures+=1
	var out:String=OS.get_environment("STATUS_COMPAT_OUT")
	if not out.is_empty():FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"real coast navigation + all frozen Basic/Composite branches, no live provider","network_calls":0},"\t"))
	print("STATUS_WEAPON_COMPAT ",checks.size()-failures,"/",checks.size());quit(0 if failures==0 else 1)
func run()->void:
	check(FileAccess.get_sha256("res://core/ai_gm_rebuilt/basic_actions.gd")=="6eee6fc51bd88f7688a9751bcb9c48454e0b95d4271cdb270c269bd33b1e7afd","legacy Basic file retains exact serialized source identity")
	var setup=Adapter.new(2,true,false)
	var base:Dictionary=setup.state_copy();var arrival:Array=[]
	# Author this separate offline fixture at initial world construction. Do not
	# reset a progressed save to bypass Content.install_new_world's restriction.
	base.items.item_coast_staff.erase("hex");base.items.item_coast_staff.erase("scene_id")
	base.items.item_coast_staff.owner_actor_id="actor_player"
	if not "item_coast_staff" in base.actors.actor_player.inventory:base.actors.actor_player.inventory.append("item_coast_staff")
	base.actors.actor_player.equipment={"weapon":"item_coast_staff"}
	base.items.item_coast_staff.weapon_profile.on_full_hit="poison"
	if not check(base.turn==0 and base.state_version==0 and World.validate(base).ok,"new authored coast weapon fixture validates at initial turn zero"):finish();return
	var enemy:Dictionary=base.actors.actor_raider
	for offset in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]:
		var point:Array=[enemy.hex[0]+offset[0],enemy.hex[1]+offset[1]]
		var plan:Dictionary=Navigation.plan_weighted_route(base,"actor_player",point,7)
		if plan.ok and plan.cost+1<=base.actors.actor_player.stamina.current:arrival=point;break
	if not check(not arrival.is_empty(),"actual dry navigation has affordable move+attack arrival"):finish();return
	# Authored test weapon retains the existing damage/range/cost recipe; only
	# its allowed on-full-hit recipe is poison, installed before new-world setup.
	base.items.item_coast_staff.weapon_profile.on_full_hit="poison"
	for mode in ["legacy","fresh","already_typed_poison","lethal"]:
		var state:Dictionary=base.duplicate(true)
		if mode!="legacy":
			var installed:Dictionary=Content.install_new_world(state)
			if not check(installed.ok,mode+" explicit new-mode fixture admission"):finish();return
			state=installed.world
		if mode=="already_typed_poison":
			var applied:Dictionary=Foundation.runtime().apply_status(state.status_foundation,"poison","actor","actor_raider","offline_existing_poison",{"intensity":1,"flat_damage":1,"max_health_bps":0})
			if not check(applied.ok,"existing typed poison setup"):finish();return
			state.status_foundation=applied.store
		if mode=="lethal":state.actors.actor_raider.health.current=3
		for composite in [false,true]:
			var snapshot:Dictionary=state.duplicate(true)
			if not composite:snapshot.actors.actor_player.hex=arrival.duplicate()
			var a:Dictionary=assessment(snapshot,arrival,composite);var before:String=C.bytes(snapshot);var assessment_before:String=C.bytes(a)
			var previous=BeforeComposite.new() if composite else BeforeBasic.new("basic_attack")
			var current=NewComposite.new() if composite else NewBasic.new("basic_attack")
			var old_plan:Dictionary=previous.freeze(snapshot,a);var plan:Dictionary=current.freeze(snapshot,a)
			var label_:String=mode+(" composite" if composite else " basic")
			if not check(old_plan.ok and plan.ok,label_+" actual freeze succeeds "+str([old_plan.get("code",""),plan.get("code","")])):finish();return
			check(C.bytes(plan)==C.bytes(old_plan),label_+" every frozen branch/effect/cost equals pre-isolation status behavior")
			check(C.bytes(snapshot)==before and C.bytes(a)==assessment_before,label_+" no snapshot or assessment mutation")
			check(plan.branches.size()==(8 if composite else 4),label_+" original branch count/gating retained")
			var typed:=0;var legacy:=0
			for branch in plan.branches:
				for patch in branch.patches:
					if patch.type=="status_v2_apply":typed+=1
					if patch.type=="actor_status_set":legacy+=1
			check(typed==(1 if mode=="fresh" else 0),label_+" only fresh non-lethal full-hit branch emits one typed poison")
			check(legacy==(1 if mode=="legacy" else 0),label_+" old-mode poison stays legacy and new-mode has no legacy patch")
	finish()
