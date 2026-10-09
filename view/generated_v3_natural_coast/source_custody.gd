extends RefCounted
## Detached source/geometry/water/navigation custody; deliberately no game engine,
## pending actions, world mutation, default menu, or legacy-save substitution.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const LegacySource=preload("res://view/generated_v3_adventure/source.gd")
const Geometry=preload("res://view/generated_v3_natural_coast/geometry.gd")
const Navigation=preload("res://view/generated_v3_runtime/navigation.gd")
const ID="natural_coast_source_custody/experimental2"
const PROFILE="natural_coast_source_preview/experimental2"
const SNAPSHOT="natural_coast_source_snapshot/experimental2"
const SNAPSHOT_FIELDS=["schema_version","profile","source","identity"]
var data: Dictionary={}
var identity: Dictionary={}
var renderer_bundle: Dictionary={}
var navigation: RefCounted

static func pipeline_digest() -> String:
	var hashes={}
	# Retain the complete old upstream identity and add every direct new physical
	# and presentation dependency. Never forge or replace the old pipeline digest.
	hashes["upstream_structured_v1_pipeline"]=LegacySource.pipeline_digest()
	for path in ["res://core/world_generation_v3/generator.gd","res://core/world_generation_v3/tiny_remnant_cleanup.gd","res://view/generated_v3_runtime/geometry.gd","res://view/generated_v3_runtime/structured_hex_builder.gd","res://view/generated_v3_runtime/navigation.gd","res://view/generated_v3_adventure/source.gd","res://view/generated_v3_adventure/projection.gd","res://view/generated_v3_adventure/resolver.gd","res://view/generated_v3_adventure/rule.gd","res://view/generated_v3_adventure/assessments.gd","res://view/generated_v3_natural_coast/source_custody.gd","res://view/generated_v3_natural_coast/builder.gd","res://view/generated_v3_natural_coast/geometry.gd","res://view/generated_v3_runtime/appearance.gd","res://view/generated_v3_runtime/ground.gdshader","res://view/generated_v3_runtime/water.gdshader","res://core/world_generation_contract.gd","res://core/ai_gm_rebuilt/canonical.gd","res://view/mesh_chunks.gd"]:
		var hash_=FileAccess.get_sha256(path)
		if not LegacySource.valid_hash(hash_):return ""
		hashes[path]=hash_
	return C.digest(hashes)
func admit(value: Variant) -> Dictionary:
	var checked=LegacySource.validate_source(value)
	if not checked.get("ok",false):return checked
	var source=C.normalized(value);var built=Geometry.build(source)
	if not built.get("ok",false):return built
	var nav=Navigation.new();checked=nav.build(source,built)
	if not checked.get("ok",false):return checked
	var pin=pipeline_digest()
	if not LegacySource.valid_hash(pin):return C.fail("COAST_PIPELINE","A physical dependency cannot be pinned.")
	var stable_nav={"supported":nav.supported,"support_heights":nav.support_heights,"allowed":nav.allowed}
	var next={"source_contract":ID,"profile":PROFILE,"source_schema":source.schema_version,"recipe_version":source.recipe_version,"recipe_id":source.recipe.id,"seed_token":source.seed_token,"seed":source.seed,"board_radius":source.board_radius,"content_hash":source.content_hash,"source_payload_sha256":C.bytes(source).sha256_text(),"renderer_profile":Geometry.PROFILE,"geometry_hash":built.geometry_hash,"water_hash":built.water_hash,"water_clipper_profile":Geometry.WATER_CLIP_PROFILE,"shore_graph_hash":C.digest(built.geometry.intended_shore_edges),"navigation_id":Navigation.ID,"navigation_content_hash":C.digest(stable_nav),"pipeline_sha256":pin,"engine_version":Engine.get_version_info().string,"scope":"detached physical source custody; no gameplay adapter/save admission"}
	next["identity_hash"]=C.digest(next)
	data=source;identity=C.normalized(next);renderer_bundle=built;navigation=nav
	return {"ok":true,"identity":identity.duplicate(true)}
func snapshot() -> Dictionary:
	if identity.is_empty():return {}
	var unsigned=identity.duplicate(true);unsigned.erase("identity_hash")
	if C.digest(unsigned)!=identity.identity_hash or C.bytes(data).sha256_text()!=identity.source_payload_sha256 or pipeline_digest()!=identity.pipeline_sha256:return {}
	var arrays=renderer_bundle.ground_mesh.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX];var expanded=PackedVector3Array()
	for index in indices:expanded.append(vertices[index])
	var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(expanded.to_byte_array())
	if hash_.finish().hex_encode()!=identity.geometry_hash or Geometry.water_hash(renderer_bundle.water_mesh)!=identity.water_hash:return {}
	if C.digest({"supported":navigation.supported,"support_heights":navigation.support_heights,"allowed":navigation.allowed})!=identity.navigation_content_hash:return {}
	return {"schema_version":SNAPSHOT,"profile":PROFILE,"source":data.duplicate(true),"identity":identity.duplicate(true)}
func restore_snapshot(value: Variant) -> Dictionary:
	if not C.exact_fields(value,SNAPSHOT_FIELDS) or not C.safe(value) or value.schema_version!=SNAPSHOT or value.profile!=PROFILE or not value.identity is Dictionary:
		return C.fail("COAST_SNAPSHOT_SCHEMA","This is not the separate coast source snapshot; no legacy save is consumed.")
	var candidate=get_script().new();var checked=candidate.admit(value.source)
	if not checked.get("ok",false):return checked
	if C.bytes(candidate.identity)!=C.bytes(value.identity):return C.fail("COAST_SNAPSHOT_IDENTITY","Exact source, physical water, geometry, navigation or pipeline identity changed.")
	data=candidate.data;identity=candidate.identity;renderer_bundle=candidate.renderer_bundle;navigation=candidate.navigation
	return {"ok":true,"identity":identity.duplicate(true)}
func height_at_xz(point: Vector2) -> Dictionary:
	return navigation.height_at_xz(point) if navigation!=null else C.fail("COAST_SOURCE_REQUIRED","No source is admitted.")
func sea_at_xz(point: Vector2) -> Dictionary:
	var hit=height_at_xz(point)
	if not hit.get("ok",false):return hit
	return {"ok":true,"wet":float(hit.height)<=0.0,"water_level":0.0,"geometry_hash":identity.geometry_hash,"water_hash":identity.water_hash,"source_contract":ID}
