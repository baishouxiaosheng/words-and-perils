extends VBoxContainer
## Compact, explicit demo banner and persistent authoritative numbers.
signal fixture_pressed
signal reset_pressed
var fixture_button: Button
var reset_button: Button
var authority: RichTextLabel
const Craft = preload("res://view/ui_craft.gd")

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); add_child(row)
	var banner := Label.new()
	banner.text = "AI-GM 框架测试 · 手工 / 署名夹具评估 · 无实时API · 演示公式，非正式规则"
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", Color.WHITE)
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	banner.tooltip_text = banner.text + "\n署名：项目作者手写 harbor_gate_initial/v1；仅初始状态的指定文字可用。"
	Craft.text_style(banner); row.add_child(banner)
	fixture_button = Button.new(); fixture_button.text = "填入指定示例意图"
	fixture_button.pressed.connect(func(): fixture_pressed.emit())
	Craft.apply_button(fixture_button, "secondary", 5.0); row.add_child(fixture_button)
	reset_button = Button.new(); reset_button.text = "重置测试渡口"
	reset_button.pressed.connect(func(): reset_pressed.emit())
	Craft.apply_button(reset_button, "secondary", 5.0); row.add_child(reset_button)
	authority = RichTextLabel.new(); authority.bbcode_enabled = false
	authority.custom_minimum_size.y = 124; authority.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	authority.add_theme_font_size_override("normal_font_size", 14)
	authority.add_theme_color_override("default_color", Color.WHITE)
	authority.add_theme_constant_override("outline_size", 0)
	var bold := FontVariation.new(); bold.base_font = Craft.font("body"); bold.variation_embolden = 0.3
	authority.add_theme_font_override("normal_font", bold)
	authority.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	authority.add_theme_constant_override("shadow_offset_x", 2)
	authority.add_theme_constant_override("shadow_offset_y", 2)
	authority.add_theme_constant_override("shadow_outline_size", 3)
	add_child(authority)

func update_adapter(adapter: RefCounted) -> void:
	if not is_instance_valid(authority): return
	authority.text = adapter.authority_text()
	fixture_button.text = "采用署名夹具评估" if adapter.phase() == "awaiting_assessment" else "填入指定示例意图"
	fixture_button.disabled = adapter.phase() != "idle" and not adapter.fixture_available()
	reset_button.disabled = adapter.phase() != "idle"
