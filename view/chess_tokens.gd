extends RefCounted
## Original procedural Staunton-inspired pieces. No imported third-party geometry.
## build() returns an unparented, floor-aligned Node3D. Names/HP stay in the board UI.
## Supported actor fields: chess_piece (pawn/rook/knight/bishop/queen/king), faction,
## token_rotation (degrees). With no art fields the traveller is a knight, guard a rook.

const Materials = preload("res://view/miniature_materials.gd")
const PIECES := ["pawn", "rook", "knight", "bishop", "queen", "king"]
const HEIGHTS := {"pawn":1.12, "rook":1.31, "knight":1.52, "bishop":1.57, "queen":1.68, "king":1.82}
const SEGMENTS := 64
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _stone_shader: Shader

static func piece_for(actor_id: String, actor: Dictionary) -> String:
	var raw_kind=actor.get("chess_piece",actor.get("token_style",""))
	var requested:String=raw_kind.to_lower() if raw_kind is String else ""
	if requested in PIECES:
		return requested
	var raw_role=actor.get("role","")
	var role:String=raw_role.to_lower() if raw_role is String else ""
	if role in PIECES:
		return role
	if actor_id == "actor_player" or role in ["traveller", "explorer", "ranger"]:
		return "knight"
	if "sentinel" in actor_id or "guard" in actor_id or role in ["guard", "sentinel"]:
		return "rook"
	if role in ["mage", "healer", "priest"]:
		return "bishop"
	if role in ["leader", "king", "lord"]:
		return "king"
	return "pawn"

static func height_for(actor_id: String, actor: Dictionary) -> float:
	return float(HEIGHTS[piece_for(actor_id, actor)])

static func build(actor_id: String, actor: Dictionary) -> Node3D:
	var kind := piece_for(actor_id, actor)
	var faction=actor.get("faction","")
	var allied: bool = actor_id == "actor_player" or (faction is String and faction in ["player", "ally", "friendly", "ivory"])
	var palette := _palette(allied)
	var root := Node3D.new()
	root.name = "Chess_" + kind
	root.set_meta("chess_piece", kind)
	root.set_meta("token_height", HEIGHTS[kind])
	root.set_meta("support_y", 0.0)
	root.set_meta("faction_style", "ivory_jade" if allied else "slate_bronze")
	var rotation_=actor.get("token_rotation",-16.0 if kind=="knight" else 0.0)
	var safe_rotation=(rotation_ is int or rotation_ is float) and is_finite(float(rotation_))
	root.rotation_degrees.y=fposmod(float(rotation_),360.0) if safe_rotation else (-16.0 if kind=="knight" else 0.0)
	_base(root, palette)
	match kind:
		"pawn": _pawn(root, palette)
		"rook": _rook(root, palette)
		"knight": _knight(root, palette)
		"bishop": _bishop(root, palette)
		"queen": _queen(root, palette)
		"king": _king(root, palette)
	return root

static func _palette(allied: bool) -> Dictionary:
	var key := "ivory" if allied else "slate"
	if not _materials.has(key):
		_materials[key] = {
			"body":_stone(Color("cfc6b2") if allied else Color("30464b"), 0.35 if allied else 0.41),
			"edge":_metal(Color("9d8658") if allied else Color("b69564"), 0.93, 0.35),
			"band":_metal(Color("276d71") if allied else Color("835142"), 0.18, 0.41),
			"dark":_metal(Color("3a5558") if allied else Color("182b31"), 0.05, 0.64),
			"felt":_metal(Color("293f3c"), 0.0, 0.94),
		}
	return _materials[key]

static func _stone(color: Color, rough: float) -> Material:
	return Materials.token_stone_material(color,rough)

static func _procedural_stone_reference(color: Color, rough: float) -> ShaderMaterial:
	if _stone_shader == null:
		_stone_shader = Shader.new()
		_stone_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 stone_color : source_color;
uniform float stone_roughness = 0.45;
varying vec3 object_pos;
float h(vec3 p) { p = fract(p * 0.3183099 + vec3(0.17,0.31,0.53)); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float n(vec3 p) { vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(mix(h(i),h(i+vec3(1,0,0)),f.x),mix(h(i+vec3(0,1,0)),h(i+vec3(1,1,0)),f.x),f.y),mix(mix(h(i+vec3(0,0,1)),h(i+vec3(1,0,1)),f.x),mix(h(i+vec3(0,1,1)),h(i+vec3(1,1,1)),f.x),f.y),f.z); }
void vertex() { object_pos=VERTEX; }
void fragment() {
  float grain=n(object_pos*23.0);
  float cloud=n(object_pos*5.5+vec3(7.0,2.0,1.0));
  float vein=pow(abs(sin(object_pos.y*12.0+object_pos.x*7.0+cloud*8.0)),18.0);
  ALBEDO=stone_color.rgb*(0.965+0.065*grain-0.045*vein);
  ROUGHNESS=stone_roughness+grain*0.055;
  METALLIC=0.025;
  SPECULAR=0.36;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _stone_shader
	mat.set_shader_parameter("stone_color", color)
	mat.set_shader_parameter("stone_roughness", rough)
	return mat

static func _metal(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	return Materials.metal_material(color,metallic,rough)

static func _mesh(parent: Node3D, name_: String, mesh: Mesh, mat: Material, position := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	parent.add_child(instance)
	return instance

static func _lathe(parent: Node3D, key: String, points: Array, mat: Material, radial_segments := SEGMENTS) -> MeshInstance3D:
	if not _meshes.has(key):
		_meshes[key] = _lathe_mesh(points, radial_segments)
	return _mesh(parent, key, _meshes[key], mat)

static func _lathe_mesh(profile: Array, segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in range(profile.size()):
		var point: Vector2 = profile[j]
		var before: Vector2 = profile[maxi(0,j-1)]
		var after: Vector2 = profile[mini(profile.size()-1,j+1)]
		var tangent := (after-before).normalized()
		for i in range(segments+1):
			var theta := TAU*float(i)/segments
			var radial := Vector3(cos(theta),0,sin(theta))
			vertices.append(radial*point.x+Vector3.UP*point.y)
			normals.append((radial*tangent.y-Vector3.UP*tangent.x).normalized())
			uv.append(Vector2(float(i)/segments,point.y))
	for j in range(profile.size()-1):
		for i in range(segments):
			var a := j*(segments+1)+i
			var b := a+1
			var c := a+segments+1
			var d := c+1
			# Godot uses clockwise front faces.
			indices.append_array([a,b,c,b,d,c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _base(root: Node3D, p: Dictionary) -> void:
	# A continuous, weighted ogee base: foot, cove, bead, inset band and shoulder.
	_lathe(root,"Weighted_plinth",[
		Vector2(0,0),Vector2(.31,0),Vector2(.345,.013),Vector2(.369,.033),Vector2(.38,.054),
		Vector2(.38,.072),Vector2(.371,.087),Vector2(.347,.101),Vector2(.335,.113),
		Vector2(.334,.136),Vector2(.332,.171),Vector2(.328,.192),Vector2(.314,.203),
		Vector2(.301,.207),Vector2(.303,.220),Vector2(.323,.232),Vector2(.326,.245),
		Vector2(.312,.259),Vector2(.282,.272),Vector2(.252,.287),Vector2(.224,.310),
		Vector2(.215,.329),Vector2(0,.329)
	],p.body)
	_lathe(root,"Felt_sole",[Vector2(0,.001),Vector2(.327,.001),Vector2(.332,.012),Vector2(.329,.021),Vector2(0,.021)],p.felt)
	_lathe(root,"Faction_enamel",[Vector2(.332,.117),Vector2(.337,.121),Vector2(.337,.179),Vector2(.329,.189)],p.band)
	_lathe(root,"Lower_brass_bead",[Vector2(.341,.100),Vector2(.349,.104),Vector2(.350,.111),Vector2(.340,.118)],p.edge)
	_lathe(root,"Upper_brass_bead",[Vector2(.329,.183),Vector2(.337,.187),Vector2(.335,.194),Vector2(.322,.201)],p.edge)
	# Four restrained inlaid lozenges make factions readable without fluorescent rings.
	for angle in [PI/4,3*PI/4,5*PI/4,7*PI/4]:
		var badge := _beveled_polygon([
			Vector2(-.029,0),Vector2(0,.027),Vector2(.029,0),Vector2(0,-.027)
		],.003,.08)
		var node := _mesh(root,"Inlaid_lozenge",badge,p.edge,Vector3(sin(angle)*.338,.152,cos(angle)*.338))
		node.rotation.y = angle

static func _stem(root: Node3D, key: String, top: float, waist: float, p: Dictionary) -> void:
	_lathe(root,key,[
		Vector2(0,.298),Vector2(.224,.298),Vector2(.217,.327),Vector2(.198,.357),Vector2(.174,.391),
		Vector2(.151,.445),Vector2(waist,.52),Vector2(waist*.95,top-.13),Vector2(waist,top-.085),
		Vector2(.145,top-.049),Vector2(.182,top-.028),Vector2(.214,top-.020),
		Vector2(.226,top-.007),Vector2(.226,top+.007),Vector2(.212,top+.022),Vector2(.16,top+.032),Vector2(0,top+.032)
	],p.body)
	_lathe(root,key+"_necklace",[Vector2(.18,top-.038),Vector2(.211,top-.030),Vector2(.216,top-.021),Vector2(.208,top-.014)],p.edge)

static func _pawn(root: Node3D, p: Dictionary) -> void:
	_stem(root,"Pawn_stem",.695,.113,p)
	_sphere(root,"Pawn_pearl",.208,Vector3(0,.905,0),p.body)
	_lathe(root,"Pawn_head_seat",[Vector2(0,.703),Vector2(.147,.703),Vector2(.157,.718),Vector2(.135,.74),Vector2(0,.75)],p.edge)

static func _rook(root: Node3D, p: Dictionary) -> void:
	_lathe(root,"Rook_tower",[
		Vector2(0,.295),Vector2(.219,.295),Vector2(.232,.319),Vector2(.228,.344),Vector2(.21,.371),
		Vector2(.197,.411),Vector2(.184,.52),Vector2(.179,.69),Vector2(.188,.843),Vector2(.209,.897),
		Vector2(.241,.921),Vector2(.261,.939),Vector2(.272,.965),Vector2(.278,.989),Vector2(.277,1.024),
		Vector2(.253,1.046),Vector2(.198,1.046),Vector2(.19,1.015),Vector2(0,1.015)
	],p.body)
	_lathe(root,"Rook_cornice",[Vector2(.227,.914),Vector2(.263,.926),Vector2(.271,.939),Vector2(.263,.948)],p.edge)
	_lathe(root,"Rook_upper_moulding",[Vector2(.271,1.014),Vector2(.282,1.022),Vector2(.281,1.041),Vector2(.27,1.053)],p.edge)
	# Open circular crown with six individually curved merlons, not a solid cylinder.
	for i in range(6):
		var start := i*TAU/6.0+.105
		var end := (i+1)*TAU/6.0-.105
		_mesh(root,"Rook_merlon_%d"%i,_arc_block(.182,.277,1.034,1.30,start,end),p.body)
	_lathe(root,"Rook_crown_well",[Vector2(0,1.028),Vector2(.188,1.028),Vector2(.188,1.052),Vector2(0,1.052)],p.dark)
	# An inset arrow slit reads as a crafted tower at close range.
	var slit := _beveled_polygon([Vector2(-.019,-.072),Vector2(-.019,.067),Vector2(0,.083),Vector2(.019,.067),Vector2(.019,-.072)],.008,.05)
	_mesh(root,"Rook_arrow_slit",slit,p.dark,Vector3(0,.713,.184))

static func _bishop(root: Node3D, p: Dictionary) -> void:
	_stem(root,"Bishop_stem",.947,.105,p)
	# A true split mitre. The diagonal kerf is open air, so it remains legible in silhouette.
	var mitre := [Vector2(0,1.018),Vector2(.092,1.034),Vector2(.149,1.096),Vector2(.166,1.179),Vector2(.151,1.258),Vector2(.111,1.337),Vector2(.055,1.401),Vector2(0,1.446)]
	var halves := _split_mitre(mitre)
	_mesh(root,"Bishop_split_mitre",halves,p.body)
	_sphere(root,"Bishop_finial",.048,Vector3(0,1.508,0),p.edge)
	_lathe(root,"Bishop_mitre_collar",[Vector2(0,.965),Vector2(.143,.965),Vector2(.158,.986),Vector2(.149,1.016),Vector2(.101,1.03),Vector2(0,1.03)],p.body)

static func _queen(root: Node3D, p: Dictionary) -> void:
	_stem(root,"Queen_stem",1.055,.112,p)
	_lathe(root,"Queen_crown_cup",[Vector2(0,1.071),Vector2(.135,1.071),Vector2(.141,1.11),Vector2(.182,1.158),Vector2(.225,1.216),Vector2(.247,1.263),Vector2(.244,1.285),Vector2(.218,1.292),Vector2(.194,1.238),Vector2(0,1.223)],p.body)
	_lathe(root,"Queen_coronet_rim",[Vector2(.237,1.255),Vector2(.255,1.262),Vector2(.255,1.281),Vector2(.243,1.293)],p.edge)
	for i in range(8):
		var angle := TAU*i/8.0
		var point := Vector3(sin(angle)*.226,1.41,cos(angle)*.226)
		var tooth := _beveled_polygon([Vector2(-.054,0),Vector2(-.035,.14),Vector2(0,.177),Vector2(.035,.14),Vector2(.054,0)],.028,.18)
		var node := _mesh(root,"Queen_crown_leaf_%d"%i,tooth,p.body,Vector3(sin(angle)*.205,1.26,cos(angle)*.205))
		node.rotation.y = angle
		_sphere(root,"Queen_crown_pearl_%d"%i,.036,point+Vector3(0,.053,0),p.edge)
	_lathe(root,"Queen_centre_stalk",[Vector2(0,1.21),Vector2(.055,1.21),Vector2(.039,1.45),Vector2(0,1.50)],p.body)
	_sphere(root,"Queen_centre_pearl",.082,Vector3(0,1.58,0),p.body)

static func _king(root: Node3D, p: Dictionary) -> void:
	_stem(root,"King_stem",1.14,.127,p)
	_lathe(root,"King_crown",[Vector2(0,1.162),Vector2(.139,1.162),Vector2(.138,1.209),Vector2(.163,1.244),Vector2(.194,1.277),Vector2(.208,1.311),Vector2(.207,1.352),Vector2(.185,1.386),Vector2(.153,1.404),Vector2(.086,1.41),Vector2(0,1.41)],p.body)
	_lathe(root,"King_crown_band",[Vector2(.199,1.315),Vector2(.217,1.327),Vector2(.217,1.345),Vector2(.198,1.360)],p.edge)
	_lathe(root,"King_cross_socket",[Vector2(0,1.398),Vector2(.09,1.398),Vector2(.099,1.415),Vector2(.085,1.437),Vector2(.045,1.45),Vector2(0,1.45)],p.body)
	var cross := [Vector2(-.044,0),Vector2(.044,0),Vector2(.044,.156),Vector2(.145,.156),Vector2(.145,.241),Vector2(.044,.241),Vector2(.044,.356),Vector2(-.044,.356),Vector2(-.044,.241),Vector2(-.145,.241),Vector2(-.145,.156),Vector2(-.044,.156)]
	_mesh(root,"King_cross",_beveled_polygon(cross,.046,.10),p.body,Vector3(0,1.453,0))
	_sphere(root,"King_cross_inlay",.033,Vector3(0,1.652,.047),p.edge)

static func _knight(root: Node3D, p: Dictionary) -> void:
	_lathe(root,"Knight_pedestal",[Vector2(0,.297),Vector2(.212,.297),Vector2(.225,.319),Vector2(.229,.345),Vector2(.22,.371),Vector2(.203,.392),Vector2(.225,.417),Vector2(.229,.439),Vector2(.214,.459),Vector2(0,.459)],p.body)
	_lathe(root,"Knight_saddle_ring",[Vector2(.218,.409),Vector2(.238,.42),Vector2(.238,.436),Vector2(.217,.45)],p.edge)
	# Sculpted horse contour: long arching neck, forward muzzle, cheek and upright ears.
	var horse := [
		Vector2(-.204,.449),Vector2(-.251,.539),Vector2(-.270,.652),Vector2(-.268,.799),
		Vector2(-.256,.956),Vector2(-.208,1.117),Vector2(-.141,1.236),Vector2(-.064,1.308),
		Vector2(.014,1.336),Vector2(.104,1.316),Vector2(.184,1.256),Vector2(.211,1.199),
		Vector2(.235,1.136),Vector2(.293,1.088),Vector2(.371,1.061),Vector2(.404,1.023),
		Vector2(.403,.958),Vector2(.373,.925),Vector2(.304,.915),Vector2(.245,.95),
		Vector2(.202,.996),Vector2(.16,1.007),Vector2(.130,.958),Vector2(.107,.883),
		Vector2(.099,.807),Vector2(.116,.723),Vector2(.158,.642),Vector2(.214,.578),
		Vector2(.256,.521),Vector2(.248,.453)
	]
	_mesh(root,"Knight_sculpted_horse",_beveled_polygon(horse,.152,.115),p.body)
	# A rear mane following the neck, with individually cut flutes.
	var mane := [Vector2(-.25,.54),Vector2(-.301,.606),Vector2(-.314,.782),Vector2(-.294,.969),Vector2(-.244,1.13),Vector2(-.165,1.263),Vector2(-.081,1.329),Vector2(-.031,1.319),Vector2(-.103,1.23),Vector2(-.161,1.12),Vector2(-.203,.972),Vector2(-.222,.795),Vector2(-.223,.62)]
	_mesh(root,"Knight_carved_mane",_beveled_polygon(mane,.102,.08),p.body)
	for side in [-1.0,1.0]:
		var z: float = side*.094
		for i in range(7):
			var y := .64+i*.082
			var x := -.289+maxf(0,y-.90)*.43
			_tube(root,"Knight_mane_flute",[Vector3(x,y,z),Vector3(x+.032,y-.011,z+side*.012),Vector3(x+.057,y-.039,z+side*.010)],.0055,p.dark)
		# Ears are sculpted pointed prisms, separated in depth instead of a single spike.
		var ear := [Vector2(-.104,1.272),Vector2(-.108,1.492),Vector2(-.057,1.513),Vector2(.009,1.333),Vector2(-.013,1.275)]
		_mesh(root,"Knight_ear",_beveled_polygon(ear,.038,.15),p.body,Vector3(0,0,side*.075))
		_mesh(root,"Knight_inner_ear",_beveled_polygon([Vector2(-.085,1.338),Vector2(-.082,1.459),Vector2(-.035,1.348)],.004,.05),p.dark,Vector3(0,0,side*.112))
		# Small dark socket and warm inset eye, both shallow and fully shaded.
		var socket := _sphere(root,"Knight_eye_socket",.035,Vector3(.139,1.238,side*.145),p.dark)
		socket.scale.z=.24
		var eye := _sphere(root,"Knight_eye",.018,Vector3(.141,1.239,side*.153),p.edge)
		eye.scale.z=.30
		var nostril := _sphere(root,"Knight_nostril",.026,Vector3(.354,1.03,side*.115),p.dark)
		nostril.scale=Vector3(.69,1.0,.30)
		_tube(root,"Knight_jaw_engraving",[Vector3(.224,.999,side*.141),Vector3(.272,.976,side*.133),Vector3(.350,.96,side*.119)],.0058,p.dark)
		_tube(root,"Knight_cheek_curve",[Vector3(.17,1.15,side*.15),Vector3(.115,1.11,side*.151),Vector3(.107,1.04,side*.148)],.007,p.edge)

static func _sphere(root: Node3D, name_: String, radius: float, position: Vector3, mat: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2
	sphere.radial_segments = 40
	sphere.rings = 20
	return _mesh(root,name_,sphere,mat,position)

static func _tube(root: Node3D, name_: String, path: Array, radius: float, mat: Material) -> void:
	for i in range(path.size()-1):
		var a: Vector3=path[i]
		var b: Vector3=path[i+1]
		var mesh := CylinderMesh.new()
		mesh.top_radius=radius
		mesh.bottom_radius=radius
		mesh.height=a.distance_to(b)
		mesh.radial_segments=8
		var node := _mesh(root,name_,mesh,mat,(a+b)*.5)
		node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())

static func _beveled_polygon(points: Array, depth: float, bevel: float) -> ArrayMesh:
	var polygon := PackedVector2Array(points)
	if Geometry2D.is_polygon_clockwise(polygon):
		polygon.reverse()
	var centre := Vector2.ZERO
	for point in polygon: centre+=point
	centre/=polygon.size()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var sections := [Vector2(-1.0,1.0-bevel),Vector2(-.72,1.0-bevel*.25),Vector2(0,1.0),Vector2(.72,1.0-bevel*.25),Vector2(1.0,1.0-bevel)]
	for section in sections:
		for point in polygon:
			var p: Vector2 = centre+(point-centre)*section.y
			vertices.append(Vector3(p.x,p.y,section.x*depth))
	var count := polygon.size()
	for layer in range(sections.size()-1):
		for i in range(count):
			var next := (i+1)%count
			var a := layer*count+i
			var b := layer*count+next
			var c := (layer+1)*count+i
			var d := (layer+1)*count+next
			indices.append_array([a,c,b,b,c,d])
	var faces := Geometry2D.triangulate_polygon(polygon)
	for i in range(0,faces.size(),3):
		indices.append_array([faces[i],faces[i+1],faces[i+2]])
		var offset := (sections.size()-1)*count
		indices.append_array([offset+faces[i],offset+faces[i+2],offset+faces[i+1]])
	return _smooth_mesh(vertices,indices)

static func _smooth_mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices: st.add_vertex(vertex)
	for index in indices: st.add_index(index)
	st.generate_normals()
	return st.commit()

static func _arc_block(inner: float, outer: float, bottom: float, top: float, start: float, end: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 12
	# A bevelled solid annular sector, closed on every side.
	var profile := [Vector2(inner,bottom),Vector2(outer-.012,bottom),Vector2(outer,bottom+.012),Vector2(outer,top-.015),Vector2(outer-.015,top),Vector2(inner+.011,top),Vector2(inner,top-.011)]
	for j in range(profile.size()):
		var a: Vector2=profile[j]
		var b: Vector2=profile[(j+1)%profile.size()]
		for i in range(steps):
			var t0 := lerpf(start,end,float(i)/steps)
			var t1 := lerpf(start,end,float(i+1)/steps)
			var p0 := Vector3(cos(t0)*a.x,a.y,sin(t0)*a.x)
			var p1 := Vector3(cos(t1)*a.x,a.y,sin(t1)*a.x)
			var p2 := Vector3(cos(t0)*b.x,b.y,sin(t0)*b.x)
			var p3 := Vector3(cos(t1)*b.x,b.y,sin(t1)*b.x)
			for vertex in [p0,p1,p2,p1,p3,p2]: st.add_vertex(vertex)
	var flat := Geometry2D.triangulate_polygon(PackedVector2Array(profile))
	for side in [0,1]:
		var angle := start if side==0 else end
		for i in range(0,flat.size(),3):
			var order := [flat[i],flat[i+1],flat[i+2]] if side==0 else [flat[i],flat[i+2],flat[i+1]]
			for index in order:
				var point: Vector2=profile[index]
				st.add_vertex(Vector3(cos(angle)*point.x,point.y,sin(angle)*point.x))
	st.generate_normals()
	return st.commit()

static func _split_mitre(profile: Array) -> ArrayMesh:
	# Clip every triangle against two oblique parallel planes, then close the cut.
	# Slot crosses x/y and passes through z. Its bottom ends above the neck collar.
	var source := _lathe_mesh(profile,64)
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plane_normal := Vector3(.79,-.61,0).normalized()
	var plane_center := Vector3(.061,1.307,0)
	for side in [-1.0,1.0]:
		var boundary: Vector3 = plane_center+plane_normal*(.017*side)
		for i in range(0,indices.size(),3):
			var polygon: Array=[]
			for j in range(3): polygon.append({"p":vertices[indices[i+j]],"n":normals[indices[i+j]]})
			var clipped: Array=[]
			for j in range(polygon.size()):
				var a: Dictionary=polygon[j]
				var b: Dictionary=polygon[(j+1)%polygon.size()]
				var da: float=(a.p-boundary).dot(plane_normal)*side
				var db: float=(b.p-boundary).dot(plane_normal)*side
				if da>=0: clipped.append(a)
				if (da>=0)!=(db>=0):
					var t := da/(da-db)
					clipped.append({"p":a.p.lerp(b.p,t),"n":a.n.lerp(b.n,t).normalized()})
			for j in range(1,clipped.size()-1):
				for item in [clipped[0],clipped[j],clipped[j+1]]:
					st.set_normal(item.n)
					st.add_vertex(item.p)
	# Close the two planar kerf surfaces by slicing the rotational profile.
	for side in [-1.0,1.0]:
		var boundary: Vector3 = plane_center+plane_normal*(.017*side)
		var ring: Array=[]
		for j in range(profile.size()-1):
			var a: Vector2=profile[j]
			var b: Vector2=profile[j+1]
			for k in range(10):
				var point := a.lerp(b,float(k)/10)
				var x: float = boundary.x+(point.y-boundary.y)*(.61/.79)
				if absf(x)<=point.x and point.x>0:
					ring.append(Vector3(x,point.y,sqrt(maxf(0,point.x*point.x-x*x))))
		if ring.size()>2:
			var contour: Array=ring.duplicate()
			for j in range(ring.size()-1,-1,-1): contour.append(Vector3(ring[j].x,ring[j].y,-ring[j].z))
			var points2 := PackedVector2Array()
			for p in contour: points2.append(Vector2(p.z,p.y))
			var flat := Geometry2D.triangulate_polygon(points2)
			for i in range(0,flat.size(),3):
				var tri := [flat[i],flat[i+1],flat[i+2]] if side>0 else [flat[i],flat[i+2],flat[i+1]]
				for index in tri:
					st.set_normal(-plane_normal*side)
					st.add_vertex(contour[index])
	return st.commit()
