extends SceneTree
## Usage: godot --path . --script res://view/chess_tokens_qa.gd -- --validate
## Render: godot --path . --script res://view/chess_tokens_qa.gd -- --render
## Writes artifacts/chess_token_lineup.png after actual shaded rendering.
const Tokens = preload("res://view/chess_tokens.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var tri := Geometry2D.triangulate_polygon(PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]))
	print("POLYGON_TRIANGULATION ",tri)
	for allied in [true,false]:
		for kind in Tokens.PIECES:
			var actor := {"chess_piece":kind,"faction":"ally" if allied else "enemy"}
			var node: Node3D = Tokens.build("qa_piece",actor)
			var counts := {"meshes":0,"vertices":0,"triangles":0}
			var bounds := AABB(Vector3.ZERO,Vector3.ZERO)
			for child in node.get_children():
				if child is MeshInstance3D:
					counts.meshes+=1
					bounds=bounds.merge(child.transform*child.mesh.get_aabb())
					for surface in range(child.mesh.get_surface_count()):
						var arrays: Array=child.mesh.surface_get_arrays(surface)
						var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
						var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
						var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
						counts.vertices+=vertices.size()
						counts.triangles+=(indices.size() if indices.size()>0 else vertices.size())/3
						if vertices.size()==0: failures.append(kind+": empty mesh")
						for vertex in vertices:
							if not vertex.is_finite(): failures.append(kind+": non-finite vertex")
						for normal in normals:
							if not normal.is_finite(): failures.append(kind+": non-finite normal")
						for index in indices:
							if index<0 or index>=vertices.size(): failures.append(kind+": invalid mesh index")
			if bounds.position.y<-.001: failures.append(kind+": below support plane")
			if bounds.end.y>Tokens.height_for("qa_piece",actor)+.01: failures.append(kind+": height helper too small")
			print("TOKEN ",kind," ","ivory" if allied else "slate"," ",JSON.stringify(counts)," bounds=",bounds)
			node.free()
	if Tokens.piece_for("actor_player",{})!="knight": failures.append("Player style regression")
	if Tokens.piece_for("actor_sentinel",{})!="rook": failures.append("Sentinel style regression")
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	print("PASS: all 12 palette/style combinations, finite geometry and normals, valid indices, floor support and height API")
	if "--render" not in OS.get_cmdline_user_args():
		quit(0)
		return
	await render_lineup()

func render_lineup() -> void:
	root.size=Vector2i(1600,1000)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("18252c")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("bec9cc")
	env.ambient_light_energy=.48
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-38,0)
	sun.light_energy=1.6
	sun.light_color=Color("fff1d9")
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=25
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-28,130,0)
	fill.light_energy=.45
	fill.light_color=Color("b5d3df")
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=9.3
	camera.position=Vector3(2.8,5.0,9.0)
	world.add_child(camera)
	camera.look_at(Vector3(0,.50,0))
	camera.current=true
	var plane := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size=Vector2(200,200)
	plane.mesh=floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color=Color("344248")
	floor_material.roughness=.84
	plane.material_override=floor_material
	plane.position.y=-.012
	world.add_child(plane)
	for row in range(2):
		for i in range(Tokens.PIECES.size()):
			var actor := {"chess_piece":Tokens.PIECES[i],"faction":"ally" if row==0 else "enemy"}
			var token: Node3D=Tokens.build("qa",actor)
			token.position=Vector3((i-2.5)*1.28,0,(row-.5)*2.5)
			world.add_child(token)
			var label := Label3D.new()
			label.text=String(Tokens.PIECES[i]).to_upper()
			label.position=token.position+Vector3(0,.055,.70)
			label.rotation_degrees.x=-90
			label.font_size=42
			label.pixel_size=.0027
			label.modulate=Color("dfd5bd")
			label.outline_size=0
			world.add_child(label)
	await process_frame
	await process_frame
	await create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/chess_token_lineup.png")
	var error := image.save_png(path)
	print("RENDER ",path," error=",error," size=",image.get_size())
	quit(error)
