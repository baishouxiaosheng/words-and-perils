extends "res://view/generated_v3_enemy/board.gd"
## Same physical actors and bundle renderer; weapons stay explicit inventory facts.

func _ensure_village(state:Dictionary) -> bool:
	var metadata:Dictionary=state.get("generated_world",{})
	var result:Dictionary=_placement_result();var manifest:Dictionary=result.get("manifest",{})
	if metadata.get("profile")!="generated_v3_village_equipment/v1" or not result.get("ok",false) or manifest.get("placement_hash")!=metadata.get("placement_hash") or manifest.get("profile_id")!=metadata.get("placement_profile") or manifest.get("geometry_hash")!=metadata.get("geometry_hash") or manifest.get("source_hash")!=metadata.get("content_hash") or admitted_source.navigation.get("placement_hash")!=metadata.get("placement_hash"):
		load_error="村落显示、来源或实际阻挡规则不属于当前版本。";return false
	var signature:String=str(metadata.placement_hash)+"/"+str(state.get("world_id",""))
	if signature==placement_signature and is_instance_valid(village_view):return true
	_clear_village()
	village_view=VillageRenderer.new();add_child(village_view)
	var installed:Dictionary=village_view.configure(result)
	if not installed.ok:load_error="村落模型未通过实际地面与范围校验；没有显示替代建筑。";_clear_village();return false
	var rows:Array=village_view.selection_nodes()
	var picked:Dictionary=village_picker.capture(rows)
	if not picked.ok:load_error="村落选择几何未通过校验。";_clear_village();return false
	for row in rows:
		var reference:Dictionary=admitted_source.static_reference(str(row.id))
		var resolved:Dictionary=StaticFocus.resolve(reference,state)
		if reference.is_empty() or not resolved.get("ok",false):load_error="村落对象没有对应的已登记身份。";_clear_village();return false
		var descriptor:Dictionary=resolved.focus.facts.descriptor
		# Validate immutable witnesses once at admission, not on the first hover.
		# Roads alone may have two supporting cells; all other out-of-support
		# raw geometry hits are rejected by a cache miss without a full rehash.
		var supports:Array=descriptor.get("supported_hexes",[descriptor.primary_hex])
		for support in supports:
			var ref:Dictionary=admitted_source.static_reference(str(row.id),support)
			var verified:Dictionary=StaticFocus.resolve(ref,state)
			if ref.is_empty() or not verified.get("ok",false):load_error="村落选择位置未通过已登记身份校验。";_clear_village();return false
			static_reference_cache[str(row.id)+"/"+Canonical.bytes(support)]={"reference":ref,"label":str(descriptor.get("name",row.id))}
		village_nodes[row.id]=row.node;village_labels[row.id]=str(descriptor.get("name",row.id))
		# The inherited bag fitter consults these opaque full-model bounds.
		# They are collision witnesses only; static selection below uses raw
		# current-LOD surface arrays, not this catalog's TriangleMesh proxy.
		if row.kind=="building":
			attention_catalog.capture(reference,village_labels[row.id],row.node,false)
			collision_subject_ids.append(str(reference.kind)+":"+str(reference.id))
	placement_signature=signature;route_signature=""
	for view in inventory_packs.values():view.pose_cache.clear()
	set_meta("placement_hash",metadata.placement_hash);set_meta("renderer_id","native_v3_village_inventory/v1")
	return true

