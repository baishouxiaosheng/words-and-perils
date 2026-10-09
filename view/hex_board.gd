extends Node3D
const InputGuard = preload("res://view/tabletop_interaction/input_guard.gd")
const TerrainField = preload("res://view/terrain_field.gd")
const MeshLandscapeReuse=preload("res://view/mesh_landscape_reuse.gd")
const Geometry = preload("res://view/miniature_geometry.gd")
const ChessTokens = preload("res://view/chess_tokens.gd")
const Batcher=preload("res://view/static_batcher.gd")
const TerrainMaterials=preload("res://view/terrain_materials.gd")
const BiomeMaterials=preload("res://view/biome_materials.gd")
const NameStyle=preload("res://view/world_name_style.gd")
const MeshChunks=preload("res://view/mesh_chunks.gd")
const Materials = preload("res://view/miniature_materials.gd")
const Presentation = preload("res://view/action_presentation.gd")
const FeatureLayout=preload("res://shared/scene_feature_layout.gd")
const AttentionCatalog=preload("res://view/attention_catalog.gd")
signal hex_selected(hex: Vector2i)
signal focus_candidates(candidates: Array, point: Vector2)
signal hex_hovered(hex: Vector2i, terrain: String, cost: float)
const COLORS = {"plain":Color("9eb58a"), "plains":Color("9eb58a"), "swamp":Color("829d8b"), "river":Color("78acbc"), "bridge":Color("a6b49a"), "mountain":Color("9bacae"), "wall":Color("b7ad99")}
const DIRS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]
var world_state: Dictionary = {}
var attention_catalog=AttentionCatalog.new()
var attention_world_id:=""
var terrain_pick_ceiling:=3.5
var terrain_pick_floor:=-0.78
var tiles: Dictionary = {}
var token_nodes: Dictionary = {}
var overlays: Node3D
var camera: Camera3D
var selected_hex = Vector2i(99,99)
var attention_ui_mode:=false
var hover_hex = Vector2i(99,99)
var focus_hex = Vector2i(-2,1)
var view_angle := 0.0
var elapsed := 0.0
var terrain_field = TerrainField.new()
var terrain_root: Node3D
var token_base_heights: Dictionary = {}
var orbit_drag_button: MouseButton = MOUSE_BUTTON_NONE
var orbit_dragging := false
var orbit_pitch := 0.91
var grid_visible := true
var terrain_signature := ""
var presentation
var selected_actor_id := ""
var animate_refresh := false
var material_cache: Dictionary={}
var static_root: Node3D
var camera_distance:=18.0
var view_focus:=Vector3(0,0.30,0)
var contact_shadows: Dictionary={}
var tabletop:MeshInstance3D
var terrain_source_snapshot:Variant=null
var generated_source_snapshot:Dictionary={}
var terrain_revision:=0
var preview_tree:Dictionary={}
var preview_tree_key:=""
var preview_tree_builds:=0
var overlay_signature:=""
var range_signature:=""
var range_rebuilds:=0
var overlay_rebuilds:=0
var target_overlays:Node3D
var name_style
var use_spatial_chunks:=true
var terrain_chunk_size:=6
var render_policy_snapshot:Dictionary={}
var terrain_chunks:Node3D
var whole_terrain_layers:Array[MeshInstance3D]=[]
var chunk_mode:=false
var overview_mode:=false
var overview_fit_size:=1.0
var overview_zoom_factor:=1.0
var overview_close_angle:=0.0
var overview_label_signature:=0
var water_near_material:StandardMaterial3D
var water_overview_material:StandardMaterial3D
var water_layers:Array[MeshInstance3D]=[]
var water_material_mode:=-1
const OVERVIEW_NAME_MIN_PX:=14.0

func _ready() -> void:
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("263235")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("99b3c7")
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if not get_meta("diagnosis_skip_startup_sky",false):
		var sky=Sky.new()
		var sky_material=ProceduralSkyMaterial.new()
		sky_material.sky_top_color=Color("8ca9c2")
		sky_material.sky_horizon_color=Color("cbd5dc")
		sky_material.ground_bottom_color=Color("2d3430")
		sky_material.ground_horizon_color=Color("8a8774")
		sky.sky_material=sky_material
		env.sky=sky
		env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.glow_enabled=false
	env.glow_intensity=0.30
	env.ssao_enabled=false
	env.ssao_radius=0.42
	env.ssao_intensity=0.60
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60,-34,0)
	sun.light_color = Color("fff0cf")
	sun.light_energy = 1.05
	sun.directional_shadow_max_distance = 35.0
	sun.shadow_normal_bias = 0.16
	sun.shadow_bias=0.045
	sun.shadow_enabled = true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var fill=DirectionalLight3D.new();fill.name="CoolSideFill"
	fill.rotation_degrees=Vector3(-22,90,0);fill.light_color=Color("b5d1f2");fill.light_energy=0.58;fill.shadow_enabled=false;add_child(fill)
	var rim=DirectionalLight3D.new();rim.name="WarmBackRim"
	rim.rotation_degrees=Vector3(-38,145,0);rim.light_color=Color("ffdbb6");rim.light_energy=0.48;rim.shadow_enabled=false;add_child(rim)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov=40.0
	camera.size = 10.8
	camera.position = Vector3(7.6,8.0,10.7)
	camera_distance=camera.position.length()
	orbit_pitch=asin(camera.position.y/camera_distance)
	add_child(camera)
	camera.look_at(view_focus)
	view_angle=atan2(camera.position.x,camera.position.z)
	camera.current = true
	get_viewport().size_changed.connect(_resize_overview)
	presentation = Presentation.new()
	add_child(presentation)
	tabletop=MeshInstance3D.new();tabletop.name="TabletopSupport"
	var plane=PlaneMesh.new();plane.size=Vector2(120,120);tabletop.mesh=plane
	var table_mat=StandardMaterial3D.new();table_mat.albedo_color=Color("625d51");table_mat.roughness=0.83;table_mat.metallic_specular=0.24
	table_mat.albedo_texture=Materials.texture("oak_albedo");table_mat.uv1_scale=Vector3(18,18,18)
	tabletop.material_override=table_mat;tabletop.position.y=-0.80;tabletop.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(tabletop)
	name_style=NameStyle.new();name_style.name="WorldNameStyle";add_child(name_style)
	overlays = Node3D.new()
	add_child(overlays)

func material(color: Color, unshaded := false) -> StandardMaterial3D:
	var key=color.to_html()+str(unshaded)
	if material_cache.has(key):return material_cache[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
	material_cache[key]=mat
	return mat

func primitive(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	obj.mesh = mesh
	obj.material_override = material(color)
	if parent.name=="ConnectedFortifications" or parent.name.begins_with("settlement_"):
		obj.material_override=Materials.stone_material(color)
	elif parent.name.begins_with("Scenery_") and mesh is BoxMesh:
		obj.material_override=Materials.wood_material(color)
	obj.position = pos
	parent.add_child(obj)
	return obj

func cylinder(radius: float, height: float, segments:=12, top_radius: float=-1.0) -> CylinderMesh:
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func hex_pos(hex: Vector2i) -> Vector3:
	return Vector3(sqrt(3.0) * (hex.x + hex.y * 0.5), 0, 1.5 * hex.y)

func tile_key(hex: Vector2i) -> String:
	return "%d,%d" % [hex.x,hex.y]

func parse_hex(value: Variant) -> Vector2i:
	if value is Vector2i: return value
	if value is Array and value.size()>=2: return Vector2i(int(value[0]),int(value[1]))
	if value is Dictionary: return Vector2i(int(value.get("q",0)),int(value.get("r",0)))
	return Vector2i.ZERO

func set_world(state: Dictionary, animate_changes: bool = false) -> void:
	var old_actors: Dictionary = world_state.get("actors",{}).duplicate(true)
	world_state = state
	animate_refresh = animate_changes
	if not animate_changes: presentation.cancel_all()
	# Actor/HP refreshes do not need to resample the entire terrain. Preserve
	# scenery whenever semantic terrain is unchanged; the state remains exact.
	for id in token_nodes.keys():
		if not state.get("actors",{}).has(id):
			presentation.forget_actor(String(id))
			attention_catalog.erase_subject("actor:"+String(id))
			if contact_shadows.has(id):contact_shadows[id].queue_free();contact_shadows.erase(id)
			token_nodes[id].queue_free()
			token_nodes.erase(id)
	token_base_heights.clear()
	var terrain_data = state.get("hexes", state.get("board",{}).get("hexes",[]))
	var metadata:Dictionary=state.get("generated_world",{})
	# Keep detached snapshots so an in-place canonical edit cannot alias the
	# cache and evade detection. Compare values, avoiding per-cell JSON strings.
	var policy={"chunks":use_spatial_chunks,"chunk_size":terrain_chunk_size}
	var unchanged=terrain_source_snapshot!=null and terrain_data==terrain_source_snapshot and metadata==generated_source_snapshot and policy==render_policy_snapshot and attention_world_id==String(state.get("world_id",""))
	if not unchanged:
		tiles.clear()
		terrain_source_snapshot=terrain_data.duplicate(true) if terrain_data is Dictionary or terrain_data is Array else terrain_data
		generated_source_snapshot=metadata.duplicate(true)
		render_policy_snapshot=policy.duplicate()
		if terrain_data is Dictionary:
			for key in terrain_data:
				var raw = terrain_data[key]
				var parts = String(key).split(",")
				var hex = Vector2i(int(parts[0]),int(parts[1]))
				tiles[tile_key(hex)] = {"hex":hex,"terrain":raw.get("terrain","plain") if raw is Dictionary else String(raw),"raw":raw if raw is Dictionary else {}}
		elif terrain_data is Array:
			for raw in terrain_data:
				var hex = parse_hex(raw.get("hex",[raw.get("q",0),raw.get("r",0)]))
				tiles[tile_key(hex)] = {"hex":hex,"terrain":raw.get("terrain","plain")}
		if tiles.is_empty():
			for q in range(-4,5):
				for r in range(-4,5):
					if abs(q+r)>4: continue
					var terrain="plain"
					if q==0: terrain="river" if r!=0 else "bridge"
					elif q==-1 and r<0: terrain="swamp"
					elif q>=2 and r>=0: terrain="mountain"
					if Vector2i(q,r) in [Vector2i(-1,2),Vector2i(0,2),Vector2i(1,1)]: terrain="wall"
					tiles[tile_key(Vector2i(q,r))]={"hex":Vector2i(q,r),"terrain":terrain}
		terrain_revision+=1
		terrain_signature=str(terrain_revision)
	if not unchanged:
		if is_instance_valid(static_root):static_root.free()
		for child in get_children():
			if child == terrain_root or child.name.begins_with("Scenery_") or child.name == "ConnectedFortifications" or child.name == "SettlementsAndRoads" or child.name == "BatchedScenery":
				child.queue_free()
		if not terrain_field.configure(tiles,state.get("generated_world",{})):
			push_warning("Generated visual sampler rejected invalid metadata; canonical model was not changed.")
			return
		attention_catalog.clear_world();attention_world_id=String(state.get("world_id",""))
		build_continuous_terrain()
		for tile in tiles.values(): build_tile(tile)
		build_wall_network()
		if state.has("generated_world"): build_generated_infrastructure(state.generated_world)
		# Batch static scenery together; terrain remains a separate coarse mesh.
		static_root=Node3D.new();static_root.name="BatchedScenery";add_child(static_root)
		for child in get_children():
			if child.name.begins_with("Scenery_") or child.name in ["ConnectedFortifications","SettlementsAndRoads"]:
				if child.is_queued_for_deletion():continue
				child.reparent(static_root)
		Batcher.merge_under(static_root)
	var actors = state.get("actors",{})
	if actors is Dictionary:
		for id in actors: build_token(String(id),actors[id])
	elif actors is Array:
		for actor in actors: build_token(String(actor.get("id","")),actor)
	if actors.is_empty():
		build_token("actor_player",{"hex":[-2,1],"name":"旅人"})
		build_token("actor_sentinel",{"hex":[2,-1],"name":"守望者"})
	if animate_changes:
		for id in actors:
			if old_actors.has(id) and actors[id].get("health") is Dictionary and old_actors[id].get("health") is Dictionary:
				if float(actors[id].health.current) < float(old_actors[id].health.current):
					presentation.play_effect("hit",token_nodes[id].position,hex_pos(parse_hex(actors[id].hex))+Vector3(0,terrain_field.support_height(parse_hex(actors[id].hex)),0))
	draw_overlay()

func vertex_material(roughness: float=0.96) -> StandardMaterial3D:
	var mat=material(Color.WHITE)
	mat.vertex_color_use_as_albedo=true
	mat.vertex_color_is_srgb=true
	mat.roughness=roughness
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	return mat

func build_continuous_terrain() -> void:
	terrain_root=Node3D.new();terrain_root.name="ContinuousTerrain";add_child(terrain_root)
	var meshes=MeshLandscapeReuse.build_meshes(terrain_field)
	# Shared vertex samples are temporary mesh-build data. Live height, route
	# and picking queries keep their separate channel/landscape caches.
	if terrain_field.generated: terrain_field.vertex_cache.clear()
	terrain_pick_ceiling=3.5;terrain_pick_floor=-0.78
	for mesh in meshes.values():
		if mesh!=null:
			terrain_pick_ceiling=maxf(terrain_pick_ceiling,mesh.get_aabb().end.y+0.1)
			terrain_pick_floor=minf(terrain_pick_floor,mesh.get_aabb().position.y-0.1)
	whole_terrain_layers.clear();water_layers.clear();water_material_mode=-1
	terrain_chunks=Node3D.new();terrain_chunks.name="SpatialTerrainChunks";terrain_root.add_child(terrain_chunks)
	var chunked=use_spatial_chunks and terrain_field.generated and int(world_state.get("board_radius",4))>=10
	for layer in ["land","skirt","bank","water"]:
		if meshes[layer]==null: continue
		var obj=MeshInstance3D.new();obj.name=layer;obj.mesh=meshes[layer]
		obj.material_override=vertex_material(0.30) if layer=="water" else (Materials.ground_material() if layer=="bank" else (BiomeMaterials.ground_material(TerrainMaterials._software_preview) if terrain_field.biomes_v2 else TerrainMaterials.ground_material()))
		if layer=="water":
			obj.material_override.metallic=0.10
			obj.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			water_near_material=obj.material_override;water_overview_material=water_near_material.duplicate()
			water_overview_material.roughness=0.92;water_overview_material.metallic_specular=0.08
			water_layers.append(obj)
		terrain_root.add_child(obj);whole_terrain_layers.append(obj)
		if chunked:
			var chunks:Dictionary=MeshChunks.split(meshes[layer],terrain_chunk_size)
			for key_ in chunks:
				var part=MeshInstance3D.new();part.name="Chunk_"+key_.replace(",","_")+"_"+layer;part.mesh=chunks[key_]
				part.material_override=obj.material_override;part.cast_shadow=obj.cast_shadow
				terrain_chunks.add_child(part)
				if layer=="water":water_layers.append(part)
	terrain_chunks.set_meta("enabled",chunked);terrain_chunks.set_meta("chunk_size",terrain_chunk_size)
	_update_chunk_visibility();_update_overview_water()
	# Delicate cartographic boundaries conform to the actual land and water.
	var grid=SurfaceTool.new();grid.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in tiles.values():
		var c=hex_pos(tile.hex)
		for edge in range(6):
			var neighbor:Vector2i=tile.hex+DIRS[posmod(5-edge,6)]
			if tiles.has(tile_key(neighbor)) and tile_key(tile.hex)>tile_key(neighbor): continue
			var a=c+TerrainField.corner(edge);var b=c+TerrainField.corner(edge+1)
			_draped_strip(grid,a,b,0.009,0.024,10)
	var lines=MeshInstance3D.new();lines.name="HexGrid";lines.mesh=grid.commit()
	lines.material_override=material(Color(0.27,0.35,0.26,0.23),true)
	lines.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	lines.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(lines)
	terrain_root.set_meta("flow_glints",[])
	# Flow glints are narrow broken strokes, never a whole blue tile.
	for i in range(0,terrain_field.channels.size(),3):
		var segment=terrain_field.channels[i]
		var a:Vector3=segment.a;var b:Vector3=segment.b
		if terrain_field.biomes_v2:
			a=segment.a.lerp(segment.b,0.31);b=segment.a.lerp(segment.b,0.54)
		a.y=terrain_field.water_height(a)+0.008;b.y=terrain_field.water_height(b)+0.008
		var tangent=(b-a).normalized();var side=Vector3(-tangent.z,0,tangent.x)
		var offset=0.10*sin(float(i)*2.8)
		if terrain_field.biomes_v2:offset=terrain_field.bank_width((a+b)*0.5)*0.24*sin(float(i)*2.8)
		var x=a+side*offset;var y=b+side*offset
		if terrain_field.biomes_v2:
			var wet=true
			for t in [0.0,0.25,0.5,0.75,1.0]:
				var point=x.lerp(y,t)
				if terrain_field.land_height(point)>=terrain_field.water_height(point)-0.008:wet=false
			if not wet:continue
		_segment_mesh(terrain_root,x,y,0.013,0.005,Color("97cac7"))
		terrain_root.get_meta("flow_glints").append({"a":x,"b":y,"kind":"water_surface_cue","lift":0.008})

func _update_chunk_visibility()->void:
	if not is_instance_valid(terrain_chunks):return
	var enabled=bool(terrain_chunks.get_meta("enabled",false))
	var near=enabled and not overview_mode and camera_distance<float(world_state.get("board_radius",4))*2.6
	chunk_mode=near;terrain_chunks.visible=near
	for layer in whole_terrain_layers:layer.visible=not near

func _segment_mesh(parent: Node3D,a: Vector3,b: Vector3,width: float,height: float,color: Color) -> MeshInstance3D:
	var mesh=BoxMesh.new();mesh.size=Vector3(width,height,a.distance_to(b))
	var obj=primitive(parent,mesh,(a+b)*0.5,color)
	obj.look_at(b,Vector3.UP)
	return obj

func _draped_strip(surface: SurfaceTool,a: Vector3,b: Vector3,width: float,lift: float,steps: int=10) -> void:
	if steps<=0:return
	var side=Vector3(-(b-a).z,0,(b-a).x).normalized()*width*0.5
	# Retain original lerp arithmetic and vertex order. Only reuse the exact
	# already-evaluated strip endpoint; no rounded/global height cache is added.
	var first=a.lerp(b,0.0)
	var left=first-side;var right=first+side
	left.y=terrain_field.surface_height(left)+lift;right.y=terrain_field.surface_height(right)+lift
	for i in range(steps):
		var next=a.lerp(b,float(i+1)/steps)
		var next_left=next-side;var next_right=next+side
		next_left.y=terrain_field.surface_height(next_left)+lift;next_right.y=terrain_field.surface_height(next_right)+lift
		for p in [left,right,next_left,next_left,right,next_right]:surface.add_vertex(p)
		left=next_left;right=next_right

func build_tile(tile: Dictionary) -> void:
	var root=Node3D.new();root.position=hex_pos(tile.hex);root.name="Scenery_"+tile_key(tile.hex);add_child(root)
	var terrain=String(tile.terrain)
	var seed=abs(int(tile.hex.x*31+tile.hex.y*17))
	var biome=String(tile.get("raw",{}).get("biome",""))
	# Shared recipe uses the exact old RNG order, rejection, sizes and transforms.
	for tree in FeatureLayout.trees_for_tile(tile,tiles,terrain_field,attention_world_id):
		var tree_root=Node3D.new();tree_root.name="ObservableTree_"+str(tree.slot);root.add_child(tree_root)
		var p=Vector3(tree.local_position[0],tree.local_position[1],tree.local_position[2])
		var size:float=tree.size
		if tree.vegetation_type=="broadleaf":_build_broadleaf(tree_root,p,size,int(tree.shape_seed))
		else:
			primitive(tree_root,cylinder(0.034,0.35*size,6),p+Vector3(0,0.17*size,0),Color("776954"))
			primitive(tree_root,cylinder(0.20*size,0.42*size,7,0.02),p+Vector3(0,0.43*size,0),Color("496f58"))
			primitive(tree_root,cylinder(0.15*size,0.36*size,7,0),p+Vector3(0,0.66*size,0),Color("678660"))
		var reference={"world_id":attention_world_id,"kind":"tree","id":tree.id,"hex":tree.hex.duplicate(),"catalog_version":FeatureLayout.VERSION}
		attention_catalog.capture(reference,"树 · (%d, %d) · 第 %d 棵"%[tile.hex.x,tile.hex.y,int(tree.slot)+1],tree_root)
	var jungle_branch=terrain_field.biomes_v2 and biome=="jungle" and String(tile.get("raw",{}).get("settlement_id","")).is_empty()
	if terrain_field.biomes_v2 and biome=="desert" and not jungle_branch:
		# Sparse low sandstone chips reinforce sand identity without route barriers.
		if seed%11==0 and not tile.get("raw",{}).get("road",false):
			var p=Vector3(-0.38,0,0.27);p.y=terrain_field.land_height(root.position+p)+0.035
			var rock=primitive(root,Geometry.chamfered_block(Vector3(0.22,0.09,0.16),0.022),p,Color("a89271"));rock.material_override=Materials.stone_material(Color("a89271"))
	elif terrain=="swamp" and not jungle_branch:
		for i in range(8):
			var p=Vector3(sin(float(seed+i)*3.4)*0.67,0,cos(float(seed+i)*2.2)*0.62)
			p.y=terrain_field.land_height(root.position+p)
			if p.y<TerrainField.WATER_Y: continue
			primitive(root,cylinder(0.017,0.24+0.07*sin(float(i)),5),p+Vector3(0,0.13,0),Color("61744b"))
			if i%2==0: primitive(root,cylinder(0.035,0.09,5),p+Vector3(0,0.28,0),Color("79654b"))
	elif terrain=="bridge" and not terrain_field.generated and not jungle_branch:
		build_bridge(root,tile.hex)
	# Loose riverbank rocks echo the incised shoreline rather than filling cells.
	if terrain in ["river","bridge"]:
		for i in range(3):
			var p=Vector3((0.54 if i%2==0 else -0.54),0,-0.48+i*0.47)
			var world_p=root.position+p
			p.y=terrain_field.land_height(world_p)
			if p.y<TerrainField.WATER_Y: continue
			if terrain_field.biomes_v2:
				var dry=true
				for offset in [Vector3.ZERO,Vector3(0.075,0,0),Vector3(-0.075,0,0),Vector3(0,0,0.075),Vector3(0,0,-0.075)]:
					var contact=world_p+offset
					if terrain_field.land_height(contact)<=terrain_field.water_height(contact)+0.012:dry=false
				if not dry:continue
			var rock=SphereMesh.new();rock.radius=0.08;rock.height=0.11;rock.radial_segments=5;rock.rings=3
			primitive(root,rock,p+Vector3(0,0.025,0),Color("929384"))

func _build_broadleaf(root:Node3D,p:Vector3,size_:float,seed:int)->void:
	primitive(root,cylinder(0.045*size_,0.66*size_,7),p+Vector3(0,0.32*size_,0),Color("6c614b")).material_override=Materials.wood_material(Color("6c614b"))
	primitive(root,cylinder(0.12*size_,0.19*size_,7,0.046*size_),p+Vector3(0,0.085*size_,0),Color("6c614b")).material_override=Materials.wood_material(Color("6c614b"))
	for i in range(3):
		var crown=SphereMesh.new();crown.radial_segments=8;crown.rings=3
		crown.radius=(0.30 if i==0 else 0.23)*size_;crown.height=(0.42 if i==0 else 0.35)*size_
		var offset=Vector3(0,0.65*size_,0) if i==0 else Vector3((0.15 if i==1 else -0.13)*size_,(0.87 if i==1 else 0.78)*size_,sin(float(seed+i))*0.09)
		primitive(root,crown,p+offset,Color("355d43") if i==0 else (Color("4e7952") if i==1 else Color("426d4a")))

func build_bridge(root: Node3D,h: Vector2i) -> void:
	var tangent=Vector3(0.5,0,sqrt(3.0)*0.5)
	for d in DIRS:
		if terrain_field.river_nodes.has(tile_key(h+d)):
			tangent=hex_pos(d).normalized();break
	var across=Vector3(-tangent.z,0,tangent.x)
	var deck_top=terrain_field.support_height(h)
	var contacts:Array[Vector3]=[]
	# Twin masonry seats are sunk into the bank, not hanging under the deck.
	for end in [-1.0,1.0]:
		var local=across*end*0.79
		var point=root.position+local
		var ground=terrain_field.land_height(point)-0.045
		var seat_top=deck_top-0.12
		var seat=primitive(root,Geometry.chamfered_block(Vector3(0.66,maxf(0.14,seat_top-ground),0.29),0.035),local+Vector3(0,(ground+seat_top)*0.5,0),Color("92937e"))
		seat.rotation.y=atan2(across.x,across.z)
		seat.material_override=Materials.stone_material(Color("92937e"))
		contacts.append(Vector3(point.x,ground,point.z))
		var cap=primitive(root,Geometry.chamfered_block(Vector3(0.74,0.07,0.33),0.022),local+Vector3(0,seat_top+0.028,0),Color("b0a68a"))
		cap.rotation.y=seat.rotation.y;cap.material_override=Materials.stone_material(Color("b0a68a"))
	# Deep structural stringers and cross bearers visibly carry the planks.
	for sign in [-1.0,1.0]:
		var offset=tangent*sign*0.28
		_segment_mesh(root,across*-0.90+offset+Vector3(0,deck_top-0.13,0),across*0.90+offset+Vector3(0,deck_top-0.13,0),0.105,0.15,Color("796246"))
	for t in [-0.72,0.0,0.72]:
		var p=across*t+Vector3(0,deck_top-0.155,0)
		_segment_mesh(root,p-tangent*0.42,p+tangent*0.42,0.09,0.10,Color("67543e"))
	for i in range(12):
		var p=across*(-0.825+float(i)*0.15)+Vector3(0,deck_top-0.04,0)
		_segment_mesh(root,p-tangent*0.37,p+tangent*0.37,0.142,0.08,Color("b4a17c") if i%3 else Color("a38c67"))
	for side in [-1.0,1.0]:
		var offset=tangent*side*0.40
		_segment_mesh(root,across*-0.90+offset+Vector3(0,deck_top+0.25,0),across*0.90+offset+Vector3(0,deck_top+0.25,0),0.060,0.065,Color("75654e"))
		_segment_mesh(root,across*-0.86+offset+Vector3(0,deck_top+0.10,0),across*0.86+offset+Vector3(0,deck_top+0.10,0),0.037,0.045,Color("887255"))
		for t in [-0.84,-0.28,0.28,0.84]:
			var p=across*t+offset
			var bottom=terrain_field.land_height(root.position+p)-0.05 if absf(t)>0.8 else deck_top-0.10
			var top=deck_top+0.30
			primitive(root,cylinder(0.045,top-bottom,6),p+Vector3(0,(bottom+top)*0.5,0),Color("796950")).material_override=Materials.wood_material(Color("796950"))
		# Short diagonal knee braces, not extra traversable platforms.
		for end in [-1.0,1.0]:
			_segment_mesh(root,across*end*0.84+offset+Vector3(0,deck_top-0.12,0),across*end*0.53+offset+Vector3(0,deck_top+0.095,0),0.038,0.045,Color("67543e"))
	# Narrow sloped entry boards meet the existing adjacent dry surface.
	for end in [-1.0,1.0]:
		var a=across*end*0.90;a.y=deck_top-0.022
		var b=across*end*1.10;b.y=terrain_field.land_height(root.position+b)+0.013
		_segment_mesh(root,a,b,0.70,0.045,Color("a38c67"))
	root.set_meta("art_bridge",{"deck_top":deck_top,"abutment_contacts":contacts,"span_half":0.90,"mode":"original"})

func build_wall_network() -> void:
	var root=Node3D.new();root.name="ConnectedFortifications";add_child(root)
	root.set_meta("art_wall_spans",[]);root.set_meta("art_foundation_contacts",[]);root.set_meta("art_wall_corners",[])
	for tile in tiles.values():
		if tile.terrain!="wall": continue
		var c=hex_pos(tile.hex)
		var links=0
		for d in DIRS:
			var other=tile.hex+d
			if not tiles.has(tile_key(other)) or tiles[tile_key(other)].terrain!="wall": continue
			links+=1
			if tile_key(tile.hex)<tile_key(other): _build_wall_span(root,c,hex_pos(other))
		var y=terrain_field.land_height(c)
		var top=y+0.94
		if terrain_field.river_distance(c)<0.50:
			# Preserve the existing culvert, with one joined corner lintel above it.
			top=1.02
			primitive(root,cylinder(0.32,top-0.57,8),Vector3(c.x,(top+0.57)*0.5,c.z),Color("b3aa90"))
		else:
			var base=y-0.075
			primitive(root,cylinder(0.35,0.18,8),c+Vector3(0,base+0.09,0),Color("979985"))
			primitive(root,cylinder(0.29,0.96,8),c+Vector3(0,y+0.48,0),Color("a9a28d"))
			root.get_meta("art_foundation_contacts").append({"point":c,"bottom":base})
		# Continuous cornice and compact battlements join every wall direction.
		primitive(root,cylinder(0.34,0.10,8),Vector3(c.x,top+0.015,c.z),Color("c9bea1"))
		for i in range(6):
			var a=float(i)*TAU/6.0
			var block=Geometry.chamfered_block(Vector3(0.16,0.16,0.17),0.012)
			primitive(root,block,Vector3(c.x+cos(a)*0.25,top+0.145,c.z+sin(a)*0.25),Color("c8bea5"))
		root.get_meta("art_wall_corners").append(c)
		if links==0:_build_wall_span(root,c-Vector3(0.63,0,0),c+Vector3(0.63,0,0))

func _build_wall_span(parent: Node3D,a: Vector3,b: Vector3) -> void:
	var length=a.distance_to(b)
	var steps=ceili(length/0.22)
	var top=maxf(terrain_field.land_height(a),terrain_field.land_height(b))+0.87
	var side=Vector3(-(b-a).z,0,(b-a).x).normalized()
	var culvert=false
	for i in range(steps):
		var x=a.lerp(b,float(i)/steps);var y=a.lerp(b,float(i+1)/steps)
		var mid=(x+y)*0.5
		var bottom_x=minf(terrain_field.land_height(x-side*0.17),terrain_field.land_height(x+side*0.17))-0.06
		var bottom_y=minf(terrain_field.land_height(y-side*0.17),terrain_field.land_height(y+side*0.17))-0.06
		if terrain_field.river_distance(mid)<0.53:
			bottom_x=0.57;bottom_y=0.57;culvert=true
		else:
			parent.get_meta("art_foundation_contacts").append({"point":mid,"bottom":minf(bottom_x,bottom_y)})
		# One contiguous sloped wall body. Shared end planes prevent box seams.
		primitive(parent,Geometry.grounded_wall(x,y,bottom_x,bottom_y,top,0.28),Vector3.ZERO,Color("ada58e"))
		# A projecting foot binds the wall into the terrain, absent at the culvert.
		if maxf(bottom_x,bottom_y)<0.55:
			primitive(parent,Geometry.grounded_wall(x,y,bottom_x-0.025,bottom_y-0.025,minf(top,maxf(bottom_x,bottom_y)+0.18),0.35),Vector3.ZERO,Color("999a84"))
		var cap_x=x;var cap_y=y;cap_x.y=top+0.035;cap_y.y=cap_x.y
		_segment_mesh(parent,cap_x,cap_y,0.33,0.085,Color("cec2a3"))
		if i%2==0:
			var obj=primitive(parent,Geometry.chamfered_block(Vector3(0.24,0.17,0.23),0.014),Vector3(mid.x,top+0.158,mid.z),Color("c7bca1"))
			obj.rotation.y=atan2((b-a).x,(b-a).z)
		# Thin, continuous horizontal courses and alternating vertical mortar.
		for rise in [0.28,0.56]:
			var course=top-rise
			if course<maxf(bottom_x,bottom_y)+0.03:continue
			var cx=x;var cy=y;cx.y=course;cy.y=course
			_segment_mesh(parent,cx,cy,0.283,0.012,Color("8f917c"))
			if (i+int(rise*10))%2==0:
				for sign in [-1.0,1.0]:
					var va=mid+side*sign*0.143;var vb=va;va.y=course+0.016;vb.y=minf(top,course+0.25)
					# Vertical mortar is shallow, not a door/crack/interaction cue.
					var joint=BoxMesh.new();joint.size=Vector3(0.011,vb.y-va.y,0.009)
					var part=primitive(parent,joint,(va+vb)*0.5,Color("989980"));part.rotation.y=atan2(side.x,side.z)
	parent.get_meta("art_wall_spans").append({"a":a,"b":b,"top":top,"culvert":culvert})

func _roof_mesh(width: float, depth: float, rise: float) -> ArrayMesh:
	var s:=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a=Vector3(-width/2,0,-depth/2);var b=Vector3(width/2,0,-depth/2)
	var c=Vector3(width/2,0,depth/2);var d=Vector3(-width/2,0,depth/2)
	var e=Vector3(0,rise,-depth/2);var f=Vector3(0,rise,depth/2)
	for p in [a,e,d,d,e,f,b,c,e,c,f,e,a,b,e,d,f,c]: s.add_vertex(p)
	s.generate_normals()
	return s.commit()

func build_generated_infrastructure(metadata: Dictionary) -> void:
	var root=Node3D.new();root.name="SettlementsAndRoads";add_child(root)
	var road_surface=SurfaceTool.new();road_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var used_bridges: Dictionary={}
	for road in metadata.get("roads",[]):
		var path: Array=road.path
		for i in range(path.size()-1):
			var a=hex_pos(tiles[path[i]].hex);var b=hex_pos(tiles[path[i+1]].hex)
			_draped_strip(road_surface,a,b,0.19,0.038,10)
		for i in range(path.size()):
			var h: Vector2i=tiles[path[i]].hex
			if not tiles[path[i]].get("raw",{}).get("bridge",false) or used_bridges.has(path[i]): continue
			used_bridges[path[i]]=true
			var center=hex_pos(h)
			var previous=hex_pos(tiles[path[maxi(0,i-1)]].hex)
			var next=hex_pos(tiles[path[mini(path.size()-1,i+1)]].hex)
			_build_generated_bridge(root,center,previous,next)
	var roads_mesh=MeshInstance3D.new();roads_mesh.name="DrapedRoadNetwork";roads_mesh.mesh=road_surface.commit()
	roads_mesh.material_override=material(Color("b7a17d"),true)
	roads_mesh.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	roads_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(roads_mesh)
	for settlement in metadata.get("settlements",[]):
		var h=parse_hex(settlement.hex);var center=hex_pos(h)
		var village=Node3D.new();village.name=String(settlement.id);root.add_child(village)
		var yard=cylinder(0.64,0.045,16)
		primitive(village,yard,center+Vector3(0,terrain_field.land_height(center)+0.015,0),Color("a99a7a"))
		var house_count=6 if settlement.kind=="city" else 4
		village.set_meta("building_count",house_count)
		for i in range(house_count):
			var angle=float(i)*TAU/house_count+0.2
			var p=center+Vector3(cos(angle)*0.56,0,sin(angle)*0.56)
			p.y=terrain_field.land_height(p)
			var house=Node3D.new();house.position=p;house.rotation.y=-angle;village.add_child(house)
			var width=0.23+0.06*(i%2);var depth=0.27+0.04*(i%3)
			var height=0.22+0.09*(i%3)
			var box=BoxMesh.new();box.size=Vector3(width,height,depth)
			var body=primitive(house,box,Vector3(0,height*0.5,0),Color("c2b194") if i%2 else Color("acac91"))
			body.material_override=Materials.stone_material(Color("c2b194") if i%2 else Color("acac91"))
			primitive(house,_roof_mesh(width+0.04,depth+0.06,0.13),Vector3(0,height,0),Color("8b6351") if i%3 else Color("5d7371"))
			var door=BoxMesh.new();door.size=Vector3(0.07,0.11,0.012)
			primitive(house,door,Vector3(0,0.06,-depth*0.5-0.008),Color("66523e")).material_override=Materials.wood_material(Color("66523e"))
			var chimney=BoxMesh.new();chimney.size=Vector3(0.045,0.16,0.045)
			primitive(house,chimney,Vector3(width*0.22,height+0.06,depth*0.20),Color("a7a18b"))
		if settlement.kind=="city":
			var road_neighbors:Array=tiles[settlement.hex_key].raw.get("road_neighbors",[])
			var gate_directions:Array[Vector3]=[]
			for neighbor in road_neighbors:
				if tiles.has(neighbor):gate_directions.append((hex_pos(tiles[neighbor].hex)-center).normalized())
			for edge in range(6):
				var a=center+TerrainField.corner(edge)*0.84;var b=center+TerrainField.corner(edge+1)*0.84
				var outward=((a+b)*0.5-center).normalized()
				var is_gate=false
				for gate in gate_directions:
					if outward.dot(gate)>0.62:is_gate=true
				if is_gate:continue
				a.y=terrain_field.land_height(a)+0.20;b.y=terrain_field.land_height(b)+0.20
				_segment_mesh(village,a,b,0.07,0.35,Color("9a9983"))
		attention_catalog.capture({"world_id":attention_world_id,"kind":"settlement","id":settlement.id,"hex":settlement.hex.duplicate()},String(settlement.name)+" · 聚落",village)
		var plate=Label3D.new();plate.text=String(settlement.name)
		plate.font=load("res://assets/NotoSansCJK-Regular.ttc");plate.font_size=32;plate.pixel_size=0.008
		plate.position=center+Vector3(0,terrain_field.support_height(h)+0.9,0)
		plate.billboard=BaseMaterial3D.BILLBOARD_ENABLED;plate.modulate=Color.WHITE;plate.outline_size=0
		plate.set_meta("overview_kind","site");village.add_child(plate);name_style.attach(plate)

func _build_generated_bridge(parent:Node3D,center:Vector3,previous:Vector3,next:Vector3)->void:
	var level=terrain_field.water_height(center)+0.35
	for neighbor in [previous,next]:
		if neighbor.distance_to(center)<0.01:continue
		var endpoint=center.lerp(neighbor,0.55)
		var direction=(endpoint-center).normalized()
		var side=Vector3(-direction.z,0,direction.x)
		var count=maxi(1,ceili(center.distance_to(endpoint)/0.18))
		for i in range(count):
			var p=center.lerp(endpoint,(float(i)+0.5)/count);p.y=level-0.035
			_segment_mesh(parent,p-side*0.22,p+side*0.22,center.distance_to(endpoint)/count+0.012,0.07,Color("9a7653")).material_override=Materials.wood_material(Color("9a7653"))
		for sign in [-1.0,1.0]:
			var a=center+side*sign*0.25;a.y=level+0.25
			var b=endpoint+side*sign*0.25;b.y=a.y
			_segment_mesh(parent,a,b,0.055,0.045,Color("634c38")).material_override=Materials.wood_material(Color("634c38"))
			for t in [0.0,0.55,1.0]:
				var p=center.lerp(endpoint,t)+side*sign*0.25
				var ground=terrain_field.land_height(p)
				primitive(parent,cylinder(0.045,maxf(0.08,level+0.28-ground),6),Vector3(p.x,(level+0.28+ground)*0.5,p.z),Color("80644b")).material_override=Materials.wood_material(Color("80644b"))
		var ramp_start=endpoint;ramp_start.y=level
		var ramp_end=center.lerp(neighbor,0.88);ramp_end.y=terrain_field.land_height(ramp_end)+0.04
		_segment_mesh(parent,ramp_start,ramp_end,0.44,0.045,Color("9a7653")).material_override=Materials.wood_material(Color("9a7653"))

func _resize_overview() -> void:
	if overview_mode:_fit_topdown()

func _fit_topdown() -> void:
	if tiles.is_empty():return
	var right=Vector3(cos(view_angle),0,-sin(view_angle))
	var up=Vector3(-sin(view_angle),0,-cos(view_angle))
	var minimum=Vector2(INF,INF);var maximum=Vector2(-INF,-INF)
	for tile in tiles.values():
		var center=hex_pos(tile.hex)
		for i in range(6):
			var point=center+TerrainField.corner(i)
			var projected=Vector2(point.dot(right),point.dot(up))
			minimum=minimum.min(projected);maximum=maximum.max(projected)
	var span=maximum-minimum;var midpoint=(minimum+maximum)*0.5
	var viewport_size=get_viewport().get_visible_rect().size
	var aspect=maxf(0.1,viewport_size.x/maxf(1.0,viewport_size.y))
	overview_fit_size=maxf(span.y,span.x/aspect)*1.08
	camera.size=overview_fit_size*overview_zoom_factor
	view_focus=right*midpoint.x+up*midpoint.y+Vector3(0,0.30,0)
	camera.position=view_focus+Vector3.UP*camera_distance
	# North-up vector is perpendicular to vertical sightline: no look_at pole.
	camera.look_at(view_focus,up)
	_update_overview_names();_update_overview_water()

func _update_overview_water() -> void:
	var mode=int(overview_mode)
	if mode==water_material_mode:return
	water_material_mode=mode
	var source=water_overview_material if overview_mode else water_near_material
	for layer in water_layers:
		if is_instance_valid(layer):layer.material_override=source

func _update_overview_names() -> void:
	var labels:Array=[];var signature:Array=[overview_mode,camera.size,view_angle,get_viewport().get_visible_rect().size]
	for node in find_children("*","Label3D",true,false):
		var label:Label3D=node
		if not label.has_meta("near_position"):label.set_meta("near_position",label.position)
		if not label.has_meta("near_scale"):label.set_meta("near_scale",label.scale)
		labels.append(label)
		signature.append_array([label.get_instance_id(),label.text,label.get_parent().global_transform,label.get_meta("near_position")])
	var key_=signature.hash()
	if key_==overview_label_signature:return
	overview_label_signature=key_
	if not overview_mode:
		for label in labels:label.position=label.get_meta("near_position");label.scale=label.get_meta("near_scale")
		return
	labels.sort_custom(func(a,b):return String(a.get_meta("overview_kind","site"))<String(b.get_meta("overview_kind","site")))
	var viewport_size=get_viewport().get_visible_rect().size
	var pixels_per_world=viewport_size.y/maxf(0.01,camera.size)
	var occupied:Array[Rect2]=[]
	for label in labels:
		var base_scale:Vector3=label.get_meta("near_scale")
		var parent_scale=label.get_parent().global_transform.basis.y.length()
		var nominal=float(label.font_size)*label.pixel_size*base_scale.y*parent_scale*pixels_per_world
		var factor=maxf(1.0,OVERVIEW_NAME_MIN_PX/maxf(0.01,nominal))
		label.scale=base_scale*factor
		var original:Vector3=label.get_parent().global_transform*label.get_meta("near_position")
		original.y=maxf(original.y,6.0) # View label only; no collision or world fact.
		var screen=camera.unproject_position(original)
		var font:Font=label.font;var measured=font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)
		var width=measured.x*label.pixel_size*factor*base_scale.x*parent_scale*pixels_per_world
		var height=font.get_height(label.font_size)*label.pixel_size*factor*base_scale.y*parent_scale*pixels_per_world
		var offset=Vector2(0,24 if label.get_meta("overview_kind","")=="actor" else -24)
		var chosen=Rect2()
		for attempt in range(8):
			var center=screen+offset
			center.x=clampf(center.x,width*0.5+8,viewport_size.x-width*0.5-8)
			center.y=clampf(center.y,height*0.5+8,viewport_size.y-height*0.5-8)
			chosen=Rect2(center-Vector2(width,height)*0.5,Vector2(width,height)).grow(3.0)
			if not occupied.any(func(rect):return rect.intersects(chosen)):break
			offset.y+=(height+8)*(1 if offset.y>0 else -1)
		occupied.append(chosen)
		var delta=chosen.get_center()-screen
		label.global_position=original+camera.global_basis.x*(delta.x/pixels_per_world)-camera.global_basis.y*(delta.y/pixels_per_world)
		label.set_meta("overview_nominal_px",nominal*factor);label.set_meta("overview_screen_rect",chosen)

func _oblique_overview() -> void:
	var radius=int(world_state.get("board_radius",4))
	camera.size=10.8 if radius<=4 else float(radius)*2.9
	camera_distance=15.4 if radius<=4 else float(radius)*4.20
	view_focus=Vector3(0,0.30,0)
	view_angle=0.63;orbit_pitch=0.53
	orbit_camera(0,0)

func reset_camera() -> void:
	var radius=int(world_state.get("board_radius",4))
	if terrain_field.generated and radius>4:
		if not overview_mode:overview_close_angle=view_angle
		overview_mode=true;overview_zoom_factor=1.0
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_HEIGHT
		camera_distance=20.0;view_angle=0.0;orbit_pitch=PI/2.0
		_fit_topdown();_update_chunk_visibility()
	else:
		overview_mode=false;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		_oblique_overview();_update_overview_names();_update_overview_water()

func focus_player() -> void:
	if overview_mode:view_angle=overview_close_angle
	overview_mode=false;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	var actor_position=hex_pos(focus_hex)
	var nearest=7.0
	var encounter_center=actor_position
	for id in world_state.get("actors",{}):
		if id=="actor_player":continue
		var other=hex_pos(parse_hex(world_state.actors[id].hex))
		var distance=actor_position.distance_to(other)
		if distance<nearest:
			nearest=distance;encounter_center=actor_position.lerp(other,0.20)
	view_focus=encounter_center+Vector3(0,terrain_field.support_height(focus_hex)+0.35,0)
	camera_distance=10.1;orbit_pitch=0.62
	orbit_camera(0,0);_update_overview_names();_update_overview_water()

func set_projection(perspective: bool) -> void:
	overview_mode=false
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	_oblique_overview()

func create_contact_shadow(id:String) -> void:
	if contact_shadows.has(id) and is_instance_valid(contact_shadows[id]):return
	var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(32):
		var a=float(i)*TAU/32.0;var b=float(i+1)*TAU/32.0
		for pair in [[Vector3.ZERO,0.21],[Vector3(cos(a),0,sin(a))*0.44,0.0],[Vector3(cos(b),0,sin(b))*0.44,0.0]]:
			surface.set_color(Color(0.10,0.09,0.07,pair[1]));surface.add_vertex(pair[0])
	var shadow=MeshInstance3D.new();shadow.name="ContactShadow_"+id;shadow.mesh=surface.commit()
	var mat=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	shadow.material_override=mat;shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(shadow);contact_shadows[id]=shadow

func build_token(id: String, actor: Dictionary) -> void:
	var actor_hex = parse_hex(actor.get("hex", [-2,1] if id == "actor_player" else [2,-1]))
	var support := hex_pos(actor_hex)+Vector3(0,terrain_field.support_height(actor_hex),0)
	var visual_signature := JSON.stringify([ChessTokens.piece_for(id,actor),actor.get("faction",""),actor.get("token_rotation",0)])
	var root: Node3D = token_nodes.get(id)
	if is_instance_valid(root) and root.get_meta("visual_signature","") != visual_signature:
		presentation.forget_actor(id)
		root.queue_free()
		root=null
	var existing := is_instance_valid(root)
	if not existing:
		root = ChessTokens.build(id, actor)
		root.set_meta("visual_signature",visual_signature)
		add_child(root)
		attention_catalog.capture({"world_id":attention_world_id,"kind":"actor","id":id,"hex":actor.hex.duplicate()},String(actor.get("name",id))+" · 角色",root,true)
		Batcher.merge_under(root)
		presentation.register_actor(id,root,support)
		create_contact_shadow(id)
	var nameplate: Label3D = root.get_node_or_null("Nameplate")
	if not is_instance_valid(nameplate):
		nameplate = Label3D.new()
		nameplate.name = "Nameplate"
		root.add_child(nameplate)
	nameplate.text = String(actor.get("name", "旅人" if id == "actor_player" else "守望者"))
	if actor.has("health"):
		nameplate.text += "  %s/%s" % [actor.health.current, actor.health.max]
	nameplate.position = Vector3(0, ChessTokens.height_for(id, actor) + 0.23, 0)
	nameplate.set_meta("near_position",nameplate.position);nameplate.set_meta("overview_kind","actor")
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font = load("res://assets/NotoSansCJK-Regular.ttc")
	nameplate.font_size = 32
	nameplate.pixel_size = 0.007
	nameplate.modulate = Color.WHITE
	nameplate.outline_size = 0
	name_style.attach(nameplate)
	token_nodes[id] = root
	token_base_heights[id] = support.y
	if existing:
		var track: Dictionary = presentation.actors[id]
		if animate_refresh and track.support.distance_to(support) > 0.01:
			var highest := maxf(track.support.y,support.y)
			for i in range(12):
				highest=maxf(highest,terrain_field.surface_height(track.support.lerp(support,float(i)/11.0)))
			presentation.move_actor(id,support,highest-minf(track.support.y,support.y)+0.85)
		elif not animate_refresh:
			presentation.reset_actor(id,support)
	var reference={"world_id":attention_world_id,"kind":"actor","id":id,"hex":actor.hex.duplicate()}
	if not attention_catalog.subjects.has("actor:"+id):attention_catalog.capture(reference,String(actor.get("name",id))+" · 角色",root,true)
	else:attention_catalog.update_reference(reference,String(actor.get("name",id))+" · 角色")
	if id == "actor_player": focus_hex = actor_hex

func select_actor_at(hex: Vector2i) -> void:
	for id in world_state.get("actors",{}):
		if parse_hex(world_state.actors[id].hex) == hex:
			selected_actor_id=String(id)
			presentation.select_actor(selected_actor_id)
			return

func clear_actor_selection() -> void:
	selected_actor_id=""
	presentation.select_actor("")

func present_resolved_metadata(metadata: Variant) -> void:
	# Optional, constrained presentation data is read only after valid commit.
	# It supplies no damage, dice, movement permissions or item effects.
	if not metadata is Dictionary:return
	if not metadata.get("kind") is String:return
	var kind:String=metadata.kind
	if not kind in ["magic","gunfire","melee"]:return
	if not metadata.get("source_actor_id","actor_player") is String or not metadata.get("target_actor_id","") is String:return
	var source_id:String=metadata.get("source_actor_id","actor_player")
	var target_id:String=metadata.get("target_actor_id","")
	if not token_nodes.has(source_id):return
	var destination:Vector3
	if token_nodes.has(target_id):destination=token_nodes[target_id].position
	elif metadata.get("target_hex") is Array and metadata.target_hex.size()==2:
		for component in metadata.target_hex:
			if not (component is int or component is float):return
			if not is_finite(float(component)) or absf(float(component))>1000000.0 or floor(float(component))!=float(component):return
		var h=parse_hex(metadata.target_hex)
		if not tiles.has(tile_key(h)):return
		destination=hex_pos(h)+Vector3(0,terrain_field.support_height(h),0)
	else:return
	presentation.play_effect(kind,token_nodes[source_id].position,destination,false)

func showcase_effect(kind: String) -> void:
	var from: Node3D = token_nodes.get("actor_player")
	var to: Node3D = token_nodes.get("actor_sentinel")
	if not is_instance_valid(from) or not is_instance_valid(to): return
	presentation.play_effect(kind,from.position,to.position,true)

func cost(terrain: String) -> float:
	match terrain:
		"swamp": return 2.0
		"river": return 2.5
		"wall": return 5.0
		"mountain": return 4.0
	return 1.0

func preview_to(target: Vector2i) -> Dictionary:
	var cache_key=terrain_signature+":"+tile_key(focus_hex)
	if preview_tree_key!=cache_key:
		var distances={tile_key(focus_hex):0.0}
		var previous={}
		var frontier=[focus_hex]
		while not frontier.is_empty():
			frontier.sort_custom(func(a,b): return distances[tile_key(a)]<distances[tile_key(b)])
			var current:Vector2i=frontier.pop_front()
			for direction in DIRS:
				var next:Vector2i=current+direction
				var key=tile_key(next)
				if not tiles.has(key): continue
				var estimate=float(distances[tile_key(current)])+cost(tiles[key].terrain)
				if not distances.has(key) or estimate<float(distances[key]):
					distances[key]=estimate;previous[key]=current
					if not next in frontier: frontier.append(next)
		preview_tree={"distances":distances,"previous":previous}
		preview_tree_key=cache_key;preview_tree_builds+=1
	var distances:Dictionary=preview_tree.distances
	var previous:Dictionary=preview_tree.previous
	var path:Array[Vector2i]=[]
	if distances.has(tile_key(target)):
		var cursor=target;path.append(cursor)
		while cursor!=focus_hex:
			cursor=previous[tile_key(cursor)];path.push_front(cursor)
	return {"path":path,"cost":float(distances.get(tile_key(target),999)),"distances":distances.duplicate()}

func ring(hex: Vector2i, color: Color, width: float, height: float) -> void:
	var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center=hex_pos(hex)
	for i in range(6):
		var a=center+TerrainField.corner(i)*0.97
		var b=center+TerrainField.corner(i+1)*0.97
		_draped_strip(surface,a,b,width,height,12)
	var obj=MeshInstance3D.new();obj.mesh=surface.commit();obj.material_override=material(color,true)
	obj.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	obj.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(target_overlays if is_instance_valid(target_overlays) else overlays).add_child(obj)

func line(a: Vector3, b: Vector3, color: Color, radius: float=0.045) -> void:
	if a.distance_to(b)<0.01: return
	var mesh=cylinder(radius,a.distance_to(b),8)
	var obj=primitive(target_overlays if is_instance_valid(target_overlays) else overlays,mesh,(a+b)*0.5,color)
	obj.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	obj.material_override=material(color,true)

func draw_overlay() -> void:
	if not is_instance_valid(overlays) or tiles.is_empty(): return
	var signature=terrain_signature+":"+tile_key(focus_hex)+":"+tile_key(selected_hex)+":"+tile_key(hover_hex)+":"+str(attention_ui_mode)
	if signature==overlay_signature:return
	overlay_signature=signature;overlay_rebuilds+=1
	if is_instance_valid(target_overlays):target_overlays.free()
	target_overlays=Node3D.new();target_overlays.name="DynamicTargetOverlay";overlays.add_child(target_overlays)
	var target=hover_hex if tiles.has(tile_key(hover_hex)) else selected_hex
	var preview=preview_to(target)
	var new_range=terrain_signature+":"+tile_key(focus_hex)
	if new_range!=range_signature:
		for child in overlays.get_children():
			if child!=target_overlays:child.free()
		range_signature=new_range;range_rebuilds+=1
		_build_range_overlay(preview)
	if tiles.has(tile_key(selected_hex)): ring(selected_hex,Color("e8ad4d"),0.060,0.065)
	if tiles.has(tile_key(hover_hex)): ring(hover_hex,Color("fff7c4"),0.044,0.077)
	if attention_ui_mode:return
	var path:Array=preview.path
	for i in range(path.size()-1):
		var a=hex_pos(path[i]);var b=hex_pos(path[i+1])
		# Sampling the route prevents markers disappearing inside hills and banks.
		for part in range(10):
			var x=a.lerp(b,float(part)/10.0);var y=a.lerp(b,float(part+1)/10.0)
			x.y=terrain_field.surface_height(x)+0.20;y.y=terrain_field.surface_height(y)+0.20
			line(x,y,Color("fff0a5"),0.035)
	if path.size()>1:
		var end=hex_pos(path[-1]);end.y=terrain_field.support_height(path[-1])+0.23
		var direction=(hex_pos(path[-1])-hex_pos(path[-2])).normalized()
		var side=Vector3(-direction.z,0,direction.x)
		line(end,end-direction*0.30+side*0.17,Color("fff0a5"),0.04)
		line(end,end-direction*0.30-side*0.17,Color("fff0a5"),0.04)
	Batcher.merge_under(target_overlays)

func _build_range_overlay(preview:Dictionary)->void:
	var range_surface := SurfaceTool.new()
	range_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boundary := SurfaceTool.new()
	boundary.begin(Mesh.PRIMITIVE_TRIANGLES)
	var range_vertices := 0
	for tile in tiles.values():
		if float(preview.distances.get(tile_key(tile.hex), 999)) > 3.0: continue
		var center := hex_pos(tile.hex)
		for edge in range(6):
			var a := TerrainField.corner(edge)
			var b := TerrainField.corner(edge + 1)
			for u in range(4):
				for v in range(4-u):
					var p := center + (a*u+b*v)/4.0
					var pa := p+a/4.0
					var pb := p+b/4.0
					for vertex in [p, pb, pa]:
						vertex.y=terrain_field.surface_height(vertex)+0.030
						range_surface.add_vertex(vertex)
						range_vertices += 1
					if u+v < 3:
						for vertex in [pa, pb, p+(a+b)/4.0]:
							vertex.y=terrain_field.surface_height(vertex)+0.030
							range_surface.add_vertex(vertex)
							range_vertices += 1
			var neighbor: Vector2i = tile.hex+DIRS[posmod(5-edge, 6)]
			if float(preview.distances.get(tile_key(neighbor), 999)) > 3.0:
				_draped_strip(boundary, center+a, center+b, 0.045, 0.052, 12)
	if range_vertices > 0:
		var fill := MeshInstance3D.new()
		fill.name = "AdvisoryRangeFill"
		fill.mesh = range_surface.commit()
		fill.material_override = Materials.range_material(Color(1.0,0.85,0.33,0.12))
		
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlays.add_child(fill)
		var outline := MeshInstance3D.new()
		outline.name = "AdvisoryRangePerimeter"
		outline.mesh = boundary.commit()
		outline.material_override = material(Color("eac35e"), true)
		outline.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlays.add_child(outline)

func _nearest_hex(p: Vector3) -> Vector2i:
	var fq=sqrt(3.0)/3.0*p.x-p.z/3.0
	var fr=2.0/3.0*p.z
	var fs=-fq-fr
	var q=roundi(fq);var r=roundi(fr);var s=roundi(fs)
	var dq=absf(q-fq);var dr=absf(r-fr);var ds=absf(s-fs)
	if dq>dr and dq>ds: q=-r-s
	elif dr>ds: r=-q-s
	var h=Vector2i(q,r)
	return h if tiles.has(tile_key(h)) else Vector2i(99,99)

func _surface_hit(origin:Vector3,direction:Vector3)->Dictionary:
	if direction.y>=-0.001:return {}
	var start=maxf(0.0,(terrain_pick_ceiling+0.5-origin.y)/direction.y)
	var finish=(terrain_pick_floor-0.5-origin.y)/direction.y
	var previous=start;var distance=start
	while distance<=finish:
		var p=origin+direction*distance
		var h=_nearest_hex(p)
		if h!=Vector2i(99,99) and p.y<=terrain_field.surface_height(p):
			var lo=previous;var hi=distance
			for _i in range(10):
				var middle=(lo+hi)*0.5;var hit=origin+direction*middle
				if hit.y>terrain_field.surface_height(hit):lo=middle
				else:hi=middle
			var t=(lo+hi)*0.5;var point=origin+direction*t
			return {"hex":_nearest_hex(point),"point":point,"distance":t}
		previous=distance;distance+=0.12
	return {}

func pick(point: Vector2) -> Vector2i:
	var hit:Dictionary=_surface_hit(camera.project_ray_origin(point),camera.project_ray_normal(point))
	return hit.get("hex",Vector2i(99,99))

func pick_focus(point:Vector2)->Array[Dictionary]:
	var origin=camera.project_ray_origin(point);var direction=camera.project_ray_normal(point)
	if direction.y>=-0.001:return []
	var terrain_hit:Dictionary=_surface_hit(origin,direction)
	var limit:float=terrain_hit.get("distance",(terrain_pick_floor-0.5-origin.y)/direction.y)
	# Terrain occlusion is checked before mesh picking. A 0.012 world-unit contact
	# tolerance allows surfaces touching the sampled land, never hidden back hills.
	var candidates:Array[Dictionary]=attention_catalog.query(origin,direction,limit+0.012)
	if not terrain_hit.is_empty():
		var h:Vector2i=terrain_hit.hex
		if tiles.has(tile_key(h)):
			var cell:Dictionary=world_state.get("hexes",{}).get(tile_key(h),{})
			var mountain_id:=""
			if cell.get("landform","")=="plateau":mountain_id=String(cell.get("plateau_region",""))
			elif cell.get("terrain","")=="mountain" or cell.get("landform","")=="ridge":
				mountain_id=String(cell.get("mountain_region",""))
				if mountain_id.is_empty():mountain_id=String(cell.get("range_id",""))
				if mountain_id.is_empty() and cell.get("terrain")=="mountain":mountain_id="mountain_"+String(cell.id)
			if not mountain_id.is_empty():candidates.append({"reference":{"world_id":attention_world_id,"kind":"mountain","id":mountain_id,"hex":[h.x,h.y]},"label":("高原" if cell.get("landform","")=="plateau" else "山地")+" · (%d, %d)"%[h.x,h.y],"distance":terrain_hit.distance,"point":terrain_hit.point})
			candidates.append({"reference":{"world_id":attention_world_id,"kind":"tile","id":cell.get("id","hex_%d_%d"%[h.x,h.y]),"hex":[h.x,h.y]},"label":"地格 · (%d, %d)"%[h.x,h.y],"distance":terrain_hit.distance,"point":terrain_hit.point})
	return candidates

func select_attention(reference:Dictionary)->void:
	if not reference.get("hex") is Array:return
	selected_hex=parse_hex(reference.hex)
	if reference.get("kind")=="actor":
		selected_actor_id=String(reference.id);presentation.select_actor(selected_actor_id)
	else:clear_actor_selection()
	draw_overlay()

func orbit_camera(delta_angle: float,delta_pitch: float=0.0) -> void:
	view_angle+=delta_angle
	if overview_mode:
		_fit_topdown();return
	orbit_pitch=clampf(orbit_pitch+delta_pitch,0.40,1.22)
	var radius=camera_distance
	camera.position=view_focus+Vector3(sin(view_angle)*cos(orbit_pitch),sin(orbit_pitch),cos(view_angle)*cos(orbit_pitch))*radius
	camera.look_at(view_focus)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == orbit_drag_button:
		orbit_dragging = false; orbit_drag_button = MOUSE_BUTTON_NONE
	if not InputGuard.permits(event, InputGuard.context_for(self)):
		if event is InputEventMouse: orbit_dragging = false; orbit_drag_button = MOUSE_BUTTON_NONE
		return
	if event is InputEventMouseMotion:
		orbit_dragging = orbit_dragging and orbit_drag_button != MOUSE_BUTTON_NONE and InputGuard.button_held(event, orbit_drag_button)
		if orbit_dragging:
			orbit_camera(-event.relative.x*0.007,event.relative.y*0.004)
			return
		var hex=pick(event.position)
		if hex!=hover_hex:
			hover_hex=hex;draw_overlay()
			if tiles.has(tile_key(hex)): hex_hovered.emit(hex,tiles[tile_key(hex)].terrain,preview_to(hex).cost)
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			orbit_dragging=true; orbit_drag_button=event.button_index
	if event is InputEventKey and InputGuard.shortcut_allowed(event):
		if event.keycode==KEY_Q: orbit_camera(-0.22)
		elif event.keycode==KEY_E: orbit_camera(0.22)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT:
			var candidates:Array[Dictionary]=pick_focus(event.position)
			if not candidates.is_empty():
				if focus_candidates.get_connections().is_empty():
					select_attention(candidates[0].reference);hex_selected.emit(selected_hex)
				else:focus_candidates.emit(candidates,event.position)
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP:
			if camera.projection==Camera3D.PROJECTION_PERSPECTIVE:camera_distance=maxf(9.0,camera_distance-1.2);orbit_camera(0,0)
			else:
				camera.size=maxf(7.5,camera.size-0.65)
				if overview_mode:overview_zoom_factor=camera.size/overview_fit_size
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			if camera.projection==Camera3D.PROJECTION_PERSPECTIVE:camera_distance=minf(65.0,camera_distance+1.2);orbit_camera(0,0)
			else:
				camera.size=minf(maxf(30.0,overview_fit_size*1.5),camera.size+0.7)
				if overview_mode:overview_zoom_factor=camera.size/overview_fit_size

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		orbit_dragging = false; orbit_drag_button = MOUSE_BUTTON_NONE

func _process(delta: float) -> void:
	_update_chunk_visibility()
	_update_overview_names();_update_overview_water()
	if terrain_field.biomes_v2:BiomeMaterials.set_software_preview(TerrainMaterials._software_preview)
	elapsed+=delta
	for id in contact_shadows:
		if not token_nodes.has(id) or not is_instance_valid(token_nodes[id]):continue
		var p:Vector3=token_nodes[id].position
		var support=terrain_field.surface_height(p)
		contact_shadows[id].position=Vector3(p.x,support+0.012,p.z)
		var distance=maxf(0.0,p.y-support)
		contact_shadows[id].scale=Vector3.ONE*(1.0+distance*0.20)
		contact_shadows[id].transparency=clampf(distance*0.35,0.0,0.70)

