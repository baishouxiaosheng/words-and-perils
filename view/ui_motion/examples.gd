extends RefCounted
const Frame=preload("res://view/ui_motion/modal_window.gd")
## Adding another size only adds a data row, with no layout or tween branch.
const WINDOWS={
	9901:{"kind":&"small","title":"简短提示 · 小图框","options":{},"text":"按小图框预设自动适配当前窗口。\n关闭也沿慢、快、慢的曲线退出。"},
	9902:{"kind":&"standard","title":"旅途记录 · 标准图框","options":{},"text":"标准图框保留安全边距，文字保持原字号。\n尺寸不足时使用内容滚动。\n\n这段界面说明不会提交行动或修改存档。"},
	9903:{"kind":&"large","title":"规则说明 · 大图框","options":{},"text":"大图框使用同一套布局和开关生命周期。\n\n长内容自动放在滚动区域。\n\n关闭、重开和窗口缩放共用预设。\n\n" ,"repeat":10},
	9904:{"kind":&"standard","title":"新增图框 · 仅配置尺寸","options":{"preferred":Vector2(720,520)},"text":"这个新图框只增加了配置：标准类型、720×520偏好尺寸。\n没有单独的移动、缩放或关闭代码。"}
}
static func show_window(main:Control,presenter:Node,id:int)->void:
	if not WINDOWS.has(id):return
	var row:Dictionary=WINDOWS[id]
	var cache:Dictionary=main.get_meta(&"ui_preset_examples",{})
	var frame=cache.get(id)
	if not is_instance_valid(frame):
		frame=Frame.new();frame.title=row.title;frame.ok_button_text="返回";frame.theme=main.theme
		frame.configure(row.kind,row.options)
		main.add_child(frame)
		var body:=RichTextLabel.new();body.text=String(row.text).repeat(int(row.get("repeat",1)));body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.size_flags_vertical=Control.SIZE_EXPAND_FILL
		body.custom_minimum_size.y=240;body.fit_content=true;body.scroll_active=false
		frame.set_content(body);presenter.watch(frame)
		cache[id]=frame;main.set_meta(&"ui_preset_examples",cache)
	presenter.open(frame)
