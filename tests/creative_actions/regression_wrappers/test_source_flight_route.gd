extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const Nav = preload("res://view/playable_build/navigation.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
var checks:=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var seed_value:=-1
	for candidate in range(1,1000):
		var rng:=RandomNumberGenerator.new();rng.seed=candidate
		if rng.randi_range(1,10000)<=6000 and rng.randi_range(1,10000)<=6000:seed_value=candidate;break
	check(seed_value>=0,"honest deterministic release test seed found")
	var adapter:=Adapter.new(seed_value,true)
	var source_sha:=FileAccess.get_sha256("res://artifacts/world_bundle_20261002/manifest.json")
	check(adapter.begin_intent(adapter.sample_goal("flight")).ok,"flight intention accepted without mutation")
	check(adapter.prepare_fixture().ok and adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok,"actual assessed flight commits")
	var state:=adapter.state_copy()
	check(Traversal.flight(state.actors.actor_player) and state.actors.actor_player.stamina.current==7,"flight granted by committed rules with seven stamina remaining")
	var before:=C.bytes(adapter.engine.save_data())
	var route:=adapter.movement_preview([3,8])
	check(route.ok,"actual-source broad flight search finds dry route instead of domain false alarm")
	if not route.ok:print(route);quit(1);return
	check(route.cost==7 and route.distance==7 and route.route.back()==[3,8],"seven dry edges fit assessed flight budget")
	check(C.bytes(adapter.engine.save_data())==before,"flight preview does not mutate state or RNG")
	for i in range(1,route.route.size()):
		check(Nav.step(route.route[i-1],route.route[i]).ok,"each flight route segment passes active physical water check")
		check(Nav.source_walkable.has(Traversal.key(route.route[i])),"flight route stays inside verified source-land domain")
	var unsupported: Dictionary={}
	for key in Nav.positions:
		if Nav.source_walkable.has(key):continue
		var bits: PackedStringArray=String(key).split(",");var from: Array=[int(bits[0]),int(bits[1])]
		for offset in Traversal.DIRECTIONS:
			var to: Array=[from[0]+offset[0],from[1]+offset[1]]
			var tested:=Nav.step(from,to)
			if tested.get("code")=="NAV_DOMAIN_UNSUPPORTED":unsupported={"from":from,"to":to};break
		if not unsupported.is_empty():break
	check(not unsupported.is_empty(),"actual catalog has dry sliver-anchor edges outside source-land domain")
	if not unsupported.is_empty():check(not Nav.step(unsupported.from,unsupported.to).ok,"unsupported sliver edge remains blocked, not newly flight-authorized")
	var original_cache: Dictionary=Nav.cache
	Nav.cache=Nav.cache.duplicate(true)
	var a: Array=route.route[0];var b: Array=route.route[1]
	Nav.cache.allowed_neighbors[Traversal.key(a)].erase(Traversal.key(b))
	check(Nav.step(a,b).get("code")=="NAV_GEOMETRY_MISMATCH","missing accepted-land edge remains fatal geometry mismatch")
	check(adapter.movement_preview([3,8]).get("code")=="NAV_GEOMETRY_MISMATCH","corrupted accepted-land cache still aborts weighted search")
	Nav.cache=original_cache
	for pair in Nav.cache.water_contact_pairs:
		var aa: PackedStringArray=String(pair[0]).split(",");var bb: PackedStringArray=String(pair[1]).split(",")
		check(not Nav.step([int(aa[0]),int(aa[1])],[int(bb[0]),int(bb[1])]).ok,"all canonical water-contact edges still blocked")
	check(adapter.begin_intent(adapter.movement_goal([3,8])).ok and adapter.prepare_fixture().ok,"actual flight route receives separate assessment")
	check(adapter.frozen_movement_preview().route==route.route and adapter.frozen_movement_preview().cost==7,"frozen flight route exact")
	check(adapter.roll_once().ok and adapter.save_file("user://source_flight_route.json").ok,"flight route locked and saved")
	var reload:=Adapter.new()
	check(reload.load_file("user://source_flight_route.json").ok and C.bytes(reload.engine.save_data())==C.bytes(adapter.engine.save_data()),"flight route pending reload exact")
	check(reload.stage().ok and reload.commit().ok,"reloaded flight route commits")
	var after:=reload.state_copy()
	check(after.actors.actor_player.hex==[3,8] and after.actors.actor_player.stamina.current==0,"flight endpoint and seven stamina charged once")
	check(after.turn==2 and after.actors.actor_scout.patrol.index==2 and after.actors.actor_player.statuses.condition_flight.remaining_turns==2,"flight move one turn, patrol and status tick")
	check(FileAccess.get_sha256("res://artifacts/world_bundle_20261002/manifest.json")==source_sha,"source bundle hashes untouched")
	print("SOURCE FLIGHT ROUTE ",checks-failures.size(),"/",checks," seed=",seed_value," route=",route.route," unsupported=",unsupported," failures=",failures)
	quit(0 if failures.is_empty() else 1)
