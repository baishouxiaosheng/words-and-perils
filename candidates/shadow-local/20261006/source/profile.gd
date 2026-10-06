extends RefCounted
## Fixture-scoped transaction. Unsupported materials reject before any write.
const RECEIVER := 1 << 18
const CASTER := 1 << 19
const SHADERS := {
	"ground":preload("ground.gdshader"),
	"mountain":preload("mountain.gdshader"),
	"vegetation":preload("vegetation.gdshader")
}
const ORIGINALS := {
	"ground":preload("../fixture/ground.gdshader"),
	"mountain":preload("../fixture/mountains.gdshader"),
	"vegetation":preload("../fixture/vegetation.gdshader")
}
var snapshots:Array=[]
var light_snapshots:Array=[]
var sun:DirectionalLight3D
var proxy:MeshInstance3D
var installed:=false
var last_error:=""

func install(root:Node3D, nodes:Array, shadow_mesh:ArrayMesh) -> bool:
	if installed:last_error="Already installed";return false
	var pending:Array=[]
	for node:GeometryInstance3D in nodes:
		var kind:String=node.get_meta("shadow_kind","")
		var mesh:Mesh=node.multimesh.mesh if node is MultiMeshInstance3D else node.mesh
		var material:Material=node.material_override
		if not SHADERS.has(kind) or mesh==null or mesh.get_surface_count()!=1 or not material is ShaderMaterial or material.shader!=ORIGINALS[kind] or material.next_pass!=null:
			last_error="Unsupported material/surface: "+str(node.name);return false
		if node is MeshInstance3D and node.get_surface_override_material(0)!=null:
			last_error="Surface override requires explicit adapter: "+str(node.name);return false
		if node.material_overlay!=null:
			last_error="Material overlay requires explicit adapter: "+str(node.name);return false
		var styled:ShaderMaterial=material.duplicate()
		styled.shader=SHADERS[kind]
		styled.set_shader_parameter("canopy_contact_strength",0.0)
		pending.append({"node":node,"material":material,"styled":styled,"layers":node.layers,"cast":node.cast_shadow,"kind":kind})
	if shadow_mesh==null:last_error="Missing validated shadow proxy";return false
	# All material validation and proxy building precede the synchronous commit.
	for light:Light3D in root.find_children("*","Light3D",true,false):
		light_snapshots.append({"node":light,"mask":light.light_cull_mask})
		light.light_cull_mask &= ~(RECEIVER|CASTER)
	snapshots=pending
	for row in snapshots:
		row.node.material_override=row.styled
		row.node.layers=RECEIVER|(CASTER if row.kind=="vegetation" else 0)
		row.node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if row.kind=="vegetation" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy=MeshInstance3D.new();proxy.name="RidgeShadowOnlyProxy";proxy.mesh=shadow_mesh;proxy.layers=CASTER
	proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	root.add_child(proxy)
	sun=DirectionalLight3D.new();sun.name="SinglePaletteShadowSun"
	sun.light_cull_mask=RECEIVER;sun.shadow_caster_mask=CASTER
	# Documented Godot defaults, replacing the preliminary half-default offset.
	# This does not claim to solve all self-shadow acne; camera/depth stay fixed.
	sun.shadow_enabled=true;sun.shadow_bias=0.1;sun.shadow_normal_bias=2.0
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1=0.35;sun.directional_shadow_blend_splits=true
	root.add_child(sun);sun.look_at(-Vector3(-.55,.74,.39).normalized(),Vector3.UP)
	installed=true;last_error="";return true

func uninstall() -> void:
	if not installed:return
	for row in snapshots:
		row.node.material_override=row.material;row.node.layers=row.layers;row.node.cast_shadow=row.cast
	for row in light_snapshots:row.node.light_cull_mask=row.mask
	proxy.free();sun.free();snapshots.clear();light_snapshots.clear();installed=false
