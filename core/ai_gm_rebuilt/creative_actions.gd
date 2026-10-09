extends RefCounted
## A reusable grounded object/environment relation compiler, not item-name scripts.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Effects = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const Generic = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const RetryV2 = preload("res://core/ai_gm_rebuilt/generic_actions_v2.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const ID := "coast_creative_obstruction_v1"
const HISTORY := "material_attempt_history/v1"
func resolver_id() -> String: return ID
func retry_history_version() -> String: return HISTORY
func action_schema() -> Dictionary:
	return {"schema_version":"creative_object_action/v1","resolver_id":ID,"bindings":{"actor_id":"acting actor ID","operation":"place_obstruction or remove_obstruction","source":{"kind":"item","id":"existing singleton physical item"},"target":{"kind":"passage_edge","id":"existing authored narrow passage"},"mechanism":Effects.MECHANISM,"intended_effect":"restrict_ground_traversal or restore_ground_traversal"},"components":{"place_obstruction":["placement","stability"],"remove_obstruction":["release"]},"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"assessment_rubric":{"A":"Task-specific handling ability: 0 incapable,1 impaired skill,2 ordinary baseline,3 trained,4 exceptional. Use2 when public facts disclose no training; never infer skill from name or confidence.","D":"Execution demand after all hard predicates pass: 1 unusually easy,2 ordinary,3 demanding,4 extreme. Placement examples: compatible singleton<=3000g =>2;3001..6000g =>3. Stability examples: span overlap>=500mm =>2;200..499mm =>3. These are declared baseline anchors, not success guarantees.","P":"Public preparation/position advantage -2..2; neutral0 without explicit evidence. Do not count stamina/injury/drunk again: program F owns those. Cite any departure from baseline; synonyms and confidence alone do not change numbers."},"required_fact_paths":["/actors/<actor_id>","/items/<source_id>","/passage_targets/<target_id>","/physical_catalog","/creative_placements","/creative_relations","/hexes/<endpoint_q,r>"],"mechanism":"Rigid portable solid singleton spans authored contacts. Trusted traits: length>=width+200mm, section inside contact interval, rigidity>=2, bearing>=target, mass<=6000g. Stand on support_hex. Source owned or reachable unowned within one cell. No new physics from names or narration.","outcomes":"Two contested program dice. Placement failure keeps original custody; placement-only leaves loose object beside aperture; both pass deploy exactly one ground-edge brace. Every attempt costs 1 stamina and one turn/hook tick. Safe assessed removal costs 1 stamina, releases only that relation, and leaves the same object loose for separate pickup. No damage, cover, sight restriction, bridge or compound action.","intent_policy":"Explicit text wins over selected attention. Clarify questions/ambiguous sources/targets/consequences. Preserve all clauses; unsupported additional clause means no execution. Arbitrary synonyms may map to this installed relation.","retry_policy":"Retained normalized pre/post failure arrangements, bounded 256 history records. Own cost/hooks, names, revisions, wording and A/D/P never grant an immediate reroll. Successful deployment followed by assessed removal permits reuse.","every_intent_requires_assessment":true}
func attempt_key(snapshot: Dictionary, assessment: Dictionary) -> String:
	var b: Dictionary = assessment.bindings; var target: Dictionary = snapshot.passage_targets[b.target.id]
	return C.bytes([b.actor_id,Effects.MECHANISM,b.operation,b.source.id,target.scene_id,target.endpoints,b.intended_effect])
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings; var actor: Dictionary = snapshot.actors[b.actor_id]; var item: Dictionary = snapshot.items[b.source.id]; var target: Dictionary = snapshot.passage_targets[b.target.id]
	var pose: Dictionary = snapshot.creative_placements.get(item.id,{})
	var cells: Array = []
	for h in target.endpoints:
		var cell: Dictionary = Cells.cell(snapshot,target.scene_id,h)
		cells.append({"hex":h,"terrain":cell.terrain,"ground":cell.ground_blocked,"air":cell.air_blocked,"all":cell.all_blocked})
	var source_support: Dictionary = {}
	if item.has("hex"):
		var support_cell: Dictionary = Cells.cell(snapshot,item.scene_id,item.hex)
		if not support_cell.is_empty(): source_support={"ground":support_cell.ground_blocked,"air":support_cell.air_blocked,"all":support_cell.all_blocked,"terrain":support_cell.terrain}
	var touch_accessible: bool = item.get("owner_actor_id","")==actor.id or (item.get("scene_id","")==actor.scene_id and item.get("hex",[])==actor.hex)
	if item.has("hex") and item.get("scene_id","")==actor.scene_id and Effects.distance(actor.hex,item.hex)==1: touch_accessible=Traversal.can_enter(snapshot,actor,item.hex) and Traversal.edge_allowed(snapshot,actor,actor.hex,item.hex)
	return {"source_support":source_support,"touch_accessible":touch_accessible,"policy":HISTORY,"actor":{"scene":actor.scene_id,"hex":actor.hex,"F":RetryV2._release_modifier(actor),"alive":actor.health.current>0,"can_pay":actor.stamina.current>=1},"source":{"id":item.id,"profile":item.physical_traits,"quantity":item.quantity,"owner":item.get("owner_actor_id",""),"scene":item.get("scene_id",""),"hex":item.get("hex",[]),"target":pose.get("target_id",""),"posture":pose.get("posture","")},"target":{"definition":target,"cells":cells,"occupied":Effects.active_target(snapshot,target.id)}}
func retry_commit_policy(snapshot: Dictionary, assessment: Dictionary, outcomes: Dictionary) -> Dictionary:
	if assessment.bindings.operation == "remove_obstruction" or not false in outcomes.values(): return {"retain":false}
	return {"retain":true,"fingerprint":attempt_fingerprint(snapshot,assessment)}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var frozen := freeze(snapshot,assessment)
	if not frozen.ok: return frozen
	return {"ok":true,"policies":{"release":"safe_direct"} if assessment.bindings.operation=="remove_obstruction" else {"placement":"contested","stability":"contested"}}
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if assessment.fact_refs.size()>32: return C.fail("CREATIVE_FACT_BUDGET","This bounded mechanism accepts at most32 exact public fact references.")
	if not C.exact_fields(b,["actor_id","operation","source","target","mechanism","intended_effect"]) or not b.actor_id is String or not snapshot.actors.has(b.actor_id) or not b.operation in ["place_obstruction","remove_obstruction"] or not C.exact_fields(b.source,["kind","id"]) or not b.source.kind is String or b.source.kind != "item" or not b.source.id is String or not C.exact_fields(b.target,["kind","id"]) or not b.target.kind is String or b.target.kind != "passage_edge" or not b.target.id is String or not b.mechanism is String or b.mechanism != Effects.MECHANISM: return C.fail("CREATIVE_BINDING","Use one installed typed source/passage relation; code, raw patches and extra operations are not accepted.")
	var removing: bool = b.operation == "remove_obstruction"
	if not b.intended_effect is String or b.intended_effect != ("restore_ground_traversal" if removing else "restrict_ground_traversal"): return C.fail("CREATIVE_INTENT","The bounded mechanism must preserve the declared ground traversal consequence.")
	if not snapshot.has("physical_catalog") or not snapshot.items.has(b.source.id) or not snapshot.passage_targets.has(b.target.id): return C.fail("CREATIVE_CATALOG","The object and passage must exist in this world's trusted physical catalog; missing traits cannot be invented.")
	var required_ids: Array = ["release"] if removing else ["placement","stability"]
	if assessment.components.size() != required_ids.size(): return C.fail("CREATIVE_COMPONENT","Exactly the mechanism's declared checks are required.")
	var seen := {}
	for component in assessment.components:
		if not component.id in required_ids or seen.has(component.id) or not Generic.validate_numeric_parameters(ID,component): return C.fail("CREATIVE_COMPONENT","Only bounded A/D/P and the exact component IDs are accepted.")
		seen[component.id] = true
	var actor: Dictionary = snapshot.actors[b.actor_id]; var item: Dictionary = snapshot.items[b.source.id]; var target: Dictionary = snapshot.passage_targets[b.target.id]
	for path in ["/actors/"+actor.id,"/items/"+item.id,"/passage_targets/"+target.id,"/physical_catalog","/creative_placements","/creative_relations"]:
		if not Generic._has_ref(assessment,path): return C.fail("CREATIVE_FACT","Every check must cite complete public actor, source, target, catalog, placements and relations.")
	for h in target.endpoints:
		var path: String = ("/scene_hexes/"+target.scene_id+"/" if snapshot.get("scene_hexes",{}).has(target.scene_id) else "/hexes/")+Traversal.key(h)
		if not Generic._has_ref(assessment,path): return C.fail("CREATIVE_FACT","Both actual endpoint cells must be cited by every check.")
	if actor.health.current <= 0 or actor.stamina.current < 1: return C.fail("CREATIVE_RESOURCE","A living actor needs one stamina; no roll, cost or turn has happened.")
	if actor.scene_id != target.scene_id or actor.hex != target.support_hex: return C.fail("CREATIVE_APPROACH","Stand at the passage's published support_hex before manipulating its contact frame.")
	if not item.has("physical_traits") or item.quantity != 1 or not item.get("interaction_profile",{}).get("movable",false): return C.fail("CREATIVE_SOURCE","This mechanism needs one movable physical singleton, not a stack, decoration or imaginary object.")
	var p: Dictionary = item.physical_traits
	if not p.solid or not p.portable or p.rigidity < 2: return C.fail("CREATIVE_RIGIDITY","The actual source must be portable, solid and rigid enough to span contacts.")
	if p.length_mm < target.width_mm + 200: return C.fail("CREATIVE_SPAN","The object is too short to overlap both authored contacts by 100 mm.")
	if p.section_mm < target.min_section_mm or p.section_mm > target.max_section_mm: return C.fail("CREATIVE_CONTACT","The object's cross section does not fit the authored contact slots.")
	if p.bearing < target.required_bearing or p.mass_g > 6000: return C.fail("CREATIVE_CAPACITY","The source's bearing class or handling mass is unsuitable.")
	var id := Effects.relation_id(item.id,target.id); var relation: Dictionary = snapshot.creative_relations.get(id,{})
	var pose: Dictionary = snapshot.creative_placements.get(item.id,{})
	var branches: Array = []
	var cost := {"type":"actor_pool_delta","actor_id":actor.id,"pool":"stamina","delta":-1}
	if removing:
		if not relation.get("active",false): return C.fail("CREATIVE_INACTIVE","The specified object does not actively brace this passage.")
		var patch := {"type":"creative_relation_set","source_item_id":item.id,"target_id":target.id,"expected_relation_revision":relation.revision,"expected_source_revision":item.get("custody_revision",0),"active":false}
		branches = [{"id":"brace_removed","requires":{"release":true},"patches":[cost,patch]},{"id":"brace_not_removed","requires":{"release":false},"patches":[cost]}]
	else:
		if Effects.active_source(snapshot,item.id) or Effects.active_target(snapshot,target.id): return C.fail("CREATIVE_OCCUPIED","The source or target already participates in an active brace.")
		if item.has("owner_actor_id"):
			if item.owner_actor_id != actor.id or not item.id in actor.inventory: return C.fail("CREATIVE_CUSTODY","Another actor's object is not available to this mechanism.")
		else:
			if item.get("scene_id","") != actor.scene_id or not item.has("hex") or Effects.distance(actor.hex,item.hex)>1: return C.fail("CREATIVE_REACH","Unowned source must be reachable in the same scene within one cell.")
			if item.hex != actor.hex:
				if not Traversal.can_enter(snapshot,actor,item.hex) or not Traversal.edge_allowed(snapshot,actor,actor.hex,item.hex): return C.fail("CREATIVE_REACH","A wall or blocker prevents touching the source from this side.")
				if actor.scene_id == "scene_coast" and not Navigation.step(actor.hex,item.hex).ok: return C.fail("CREATIVE_REACH","Actual source geometry prevents reaching the loose object.")
		var moved: bool = item.has("owner_actor_id") or item.get("hex",[]) != target.support_hex or item.get("scene_id","") != target.scene_id
		for placement in [false,true]:
			for stability in [false,true]:
				var patches: Array = [cost.duplicate(true)]
				if placement:
					patches.append({"type":"creative_source_place","source_item_id":item.id,"target_id":target.id,"expected_custody_revision":item.get("custody_revision",0),"expected_placement_revision":pose.get("revision",-1),"posture":"braced" if stability else "loose"})
					if stability: patches.append({"type":"creative_relation_set","source_item_id":item.id,"target_id":target.id,"expected_relation_revision":relation.get("revision",-1),"expected_source_revision":int(item.get("custody_revision",0))+(1 if moved else 0),"active":true})
				branches.append({"id":"brace_%d_%d"%[int(placement),int(stability)],"requires":{"placement":placement,"stability":stability},"patches":patches})
	return {"ok":true,"resolver_id":ID,"branches":branches}
