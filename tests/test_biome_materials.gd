extends SceneTree
const Biomes=preload("res://view/biome_materials.gd")
const Terrain=preload("res://view/terrain_materials.gd")
const Field=preload("res://view/terrain_field.gd")
const Generator=preload("res://core/world_generator.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:
	var before=Terrain.ground_material(true);var legacy_shader=before.shader;var legacy_palette=before.get_shader_parameter("grass_palette")
	var material=Biomes.ground_material(true)
	check(material!=before and material.shader!=legacy_shader,"V2 material is isolated from the frozen v1 path")
	check(before.shader==legacy_shader and before.get_shader_parameter("grass_palette")==legacy_palette and before.get_shader_parameter("software_preview")==true,"V2 construction does not modify v1 shader/palette/quality")
	for kind in ["grass","soil","rock"]:
		for map in ["albedo","normal","roughness"]:
			var tex:Texture2D=material.get_shader_parameter(kind+"_"+map)
			check(tex!=null and tex.get_width()==1024 and tex.get_height()==1024,"V2 uses actual existing1K map "+kind+"/"+map)
	Biomes.set_software_preview(false);check(Biomes.ground_material(false)==material and material.get_shader_parameter("software_preview")==false,"V2 detailed preset retains the one cached material")
	Biomes.set_software_preview(true);check(material.get_shader_parameter("software_preview")==true,"V2 software preset updates shared instance")
	var code=material.shader.code
	check(code.contains("biome_weights=UV2") and not code.contains("rock_height_start"),"V2 rock selection uses canonical weights/slope rather than absolute elevation")
	check(code.contains("source_color") and code.contains("ROUGHNESS=") and code.contains("NORMAL="),"V2 remains physically lit sourced albedo/roughness/normal")
	var world:Dictionary=Generator.generate(726381,12,{"generator_version":"macro_hex_biomes_v2"})
	var tiles={}
	for key in world.hexes:
		var c:Dictionary=world.hexes[key];tiles[key]={"hex":Vector2i(c.q,c.r),"terrain":c.terrain,"raw":c}
	var field=Field.new();check(field.configure(tiles,world) and field.biomes_v2,"V2 field honors validated canonical sampler")
	var cap=0;var desert=0;var jungle=0;var samples={}
	for c in world.hexes.values():
		var p:Vector3=Field.center(Vector2i(c.q,c.r));var appearance:Dictionary=field.biome_appearance(p)
		check(appearance.weights.x>=0 and appearance.weights.x<=1 and appearance.weights.y>=0 and appearance.weights.y<=1,"All biome material weights are finite bounded canonical presentation")
		if c.landform=="plateau" and c.biome!="alpine":
			cap+=1;check(appearance.weights.y==0.0,"Flat non-alpine plateau cap is not globally forced to rock")
		if c.biome=="desert":desert+=1;samples.desert=appearance.palette
		if c.biome=="jungle":jungle+=1;samples.jungle=appearance.palette
	check(cap>0 and desert>0 and jungle>0,"Representative world includes real cap/desert/jungle samples")
	check(samples.desert.r>samples.desert.g and samples.jungle.g>samples.jungle.r and samples.jungle.get_luminance()<samples.desert.get_luminance(),"Sand and jungle palettes have distinct hue/value identities")
	var invalid=world.duplicate(true);invalid.macro_landscape.climate.temperature_base="bad"
	check(not field.configure(tiles,invalid) and not field.generated and field.tiles.is_empty(),"Invalid stored v2 sampler metadata is rejected without fabricating fallback geography")
	if failures.is_empty():print("BIOME MATERIALS PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
