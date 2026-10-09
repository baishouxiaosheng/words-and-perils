extends Control
const TerrainMaterials=preload("res://view/terrain_materials.gd")
const Materials = preload("res://view/miniature_materials.gd")
const Icons = preload("res://view/strategy_icons.gd")
const Craft = preload("res://view/ui_craft.gd")
const Straw = preload("res://view/fullscreen_hud/straw_theme.gd")
const Ornament=preload("res://view/adventure_fieldbook/skin.gd")
const StrategyFrame = preload("res://view/strategy_frame.gd")
const Board = preload("res://view/hex_board.gd")
const Generator = preload("res://core/world_generator.gd")
const SeededWorld = preload("res://core/world_generation_contract.gd")
const Game = preload("res://core/game_state.gd")
const Provider = preload("res://core/json_relay_provider.gd")
const Playtest = preload("res://view/ai_gm_playtest/adapter.gd")
const PlaytestPanel = preload("res://view/ai_gm_playtest/panel.gd")
const Coast = preload("res://view/playable_build/adapter.gd")
const DisplayText = preload("res://view/playable_build/display_text.gd")
const PlayerDetails = preload("res://view/playable_build/player_details.gd")
const SceneEntities = preload("res://view/playable_build/entity_catalog.gd")
const SceneAdapters = preload("res://view/playable_build/scene_adapters.gd")
const SceneCells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const RuntimeAI = preload("res://view/dual_api_settings/actor_controller.gd")
const ActorEntryView=preload("res://view/actor_action_entry/view_adapter.gd")
const ActorEntryBoard=preload("res://view/actor_action_entry/board.gd")
const StatusEntryView=preload("res://view/actor_status_entry_v1/view_adapter.gd")
const StatusEntryBoard=preload("res://view/actor_status_entry_v1/board.gd")
const ActorEntryPanel=preload("res://view/actor_action_entry/panel.gd")
const VillageRuntimeSession=preload("res://view/runtime_ai/village_session.gd")
const RuntimeConnectionPanel = preload("res://view/dual_api_settings/panel.gd")
const WorldBundle = preload("res://view/playable_build/world_bundle.gd")
const CoastBoard = preload("res://private_main_visual/coast_board.gd")
const CoastPanel = preload("res://view/playable_build/panel.gd")
const GeneratedAdventure = preload("res://view/generated_adventure/adapter.gd")
const SeededAdventure = preload("res://view/generated_adventure/seeded_adapter.gd")
const InventoryAdventure = preload("res://view/generated_inventory/adapter.gd")
const GeneratedBoard = preload("res://view/generated_adventure/board.gd")
const GeneratedPanel = preload("res://view/generated_adventure/panel.gd")
const V3Adventure = preload("res://view/generated_v3_adventure/adapter.gd")
const V3Generator = preload("res://core/world_generation_v3/generator.gd")
const V3Board = preload("res://view/generated_v3_adventure/board.gd")
const V3Panel = preload("res://view/generated_v3_adventure/panel.gd")
const V3InventoryAdventure = preload("res://view/generated_v3_inventory/adapter.gd")
const V3InventoryBoard = preload("res://view/generated_v3_inventory/board.gd")
const V3InventoryPanel = preload("res://view/generated_v3_inventory/panel.gd")
const V3RenderResidency=preload("res://view/generated_v3_npc/render_residency.gd")
const V3EquipmentAdventure=preload("res://view/generated_v3_equipment/adapter.gd")
const V3EquipmentBoard=preload("res://view/generated_v3_equipment/board.gd")
const V3EquipmentPanel=preload("res://view/generated_v3_equipment/panel.gd")
const V3EnemyAdventure=preload("res://view/generated_v3_enemy/adapter.gd")
const V3EnemyBoard=preload("res://view/generated_v3_enemy/board.gd")
const V3EnemyPanel=preload("res://view/generated_v3_enemy/panel.gd")
const V3NPCAdventure=preload("res://view/generated_v3_npc/adapter.gd")
const V3NPCBoard=preload("res://view/generated_v3_npc/board.gd")
const V3NPCPanel=preload("res://view/generated_v3_npc/panel.gd")
const V3VillageAdventure = preload("res://view/generated_v3_village/adapter.gd")
const V3VillageBoard = preload("res://view/generated_v3_settlement/board.gd")
const INK = Color("2d403e")
const MUTED = Color("667066")
const PAPER = Color("f2dfa6")
const TEAL = Color("91b9a6")
var game
var provider
var board
var goal: TextEdit
# Presentation-only token for a deliberately chosen signed sample. Never saved.
var _signed_sample_goal := ""
var _signed_sample_display := ""
var journal: RichTextLabel
var status_label: Label
var target_label: Label
var hero_label: Label
var hero_subtitle: Label
var inventory_note: Label
var inventory_box: VBoxContainer
var phase_label: Label
var roll_button: Button
var submit_button: Button
var die_label: Label
var selected = Vector2i(99,99)
var selected_focus:Dictionary={}
var focus_choices:Array=[]
var focus_choice_button:Button
var focus_choice_popup:PopupMenu
var focus_popup_point:=Vector2.ZERO
var resolved_focus: Dictionary = {}
var focus_details_dialog: AcceptDialog
var focus_details_text: RichTextLabel
var route_preview_label: Label
var movement_preview: Dictionary = {}
var _route_preview_key := ""
var last_save_result: Dictionary = {}
var last_load_result: Dictionary = {}
var active_action := ""
var current_request: Dictionary = {}
var file_dialog: FileDialog
var import_dialog: AcceptDialog
var import_text: TextEdit
var import_file_dialog: FileDialog
var import_error_label: Label
var viewport: SubViewport
var demo_step := 0
var demo_button: Button
var relay_mode := true
var help_dialog: AcceptDialog
var wait_started := 0
var timeout_shown := false
var cancel_button: Button
var demo_confirm_dialog: ConfirmationDialog
var restart_confirm_dialog: ConfirmationDialog
var inventory_dialog: AcceptDialog
var clear_target_button: Button
var next_step_label: Label
var relay_row: HBoxContainer
var export_button: Button
var import_button: Button
var board_container: SubViewportContainer
var effects_dialog: AcceptDialog
var world_dialog: AcceptDialog
var seed_input: LineEdit
var radius_input: SpinBox
var world_build_requested := false
var world_build_busy := false
var perf_logged := false
var quality_choice:OptionButton
var quality_label:Label
var software_preview:=false
var qa_input_events := 0
var world_build_seed := 726381
var world_build_seed_token := ""
# Detached audit metadata; never inserted into legacy source/save schemas.
var last_world_generation_metadata: Dictionary = {}
var world_build_radius := 7
var map_title: Label
var map_stats_label: Label
var journal_panel: PanelContainer
var journal_drawer: AcceptDialog
var journal_toggle: Button
var middle_row: HBoxContainer
var tools_menu: MenuButton
var intent_expand_button: Button
var journal_open := false
var ui_presenter:Node
var history_motion:Node
var popup_motion:Node
var compact_layout := false
var intent_expanded := false
var actor_action_mode:=false
var actor_status_mode:=false
var actor_render_error:=""
var actor_entry_restore_requested:=false
var actor_render_suspended:=false
var actor_export_hash:=""
var _enemy_dispatch_generation:=0
var actor_action_adventure:RefCounted
var actor_status_adventure:RefCounted
var actor_action_panel:VBoxContainer
const ACTOR_ENTRY_NEW:=1101
const ACTOR_ENTRY_CONTINUE:=1102
const ACTOR_STATUS_ENTRY_NEW:=1103
const ACTOR_STATUS_ENTRY_CONTINUE:=1104
var playtest_mode := false
var village_runtime_session:RefCounted
var _village_runtime_sessions:Dictionary={}
var runtime_ai: Node
var runtime_connection_panel: VBoxContainer
var _api_input_snapshot: Dictionary = {}
var playtest: RefCounted
var playtest_panel: VBoxContainer
var playtest_reset_dialog: ConfirmationDialog
var scene_test_confirm_dialog: ConfirmationDialog
var relay_note: Label
var coast_mode := false
var coast_adventure: RefCounted
var laboratory: RefCounted
var laboratory_panel: VBoxContainer
var coast_panel: VBoxContainer
var generated_panel: VBoxContainer
var generated_inventory_choice: CheckButton
var generated_adventure: RefCounted
var generated_mode := false
var generated_start_busy := false
var generated_v3_adventure: RefCounted
var generated_v3_mode := false
var generated_v3_inventory_mode := false
var generated_v3_inventory_adventure: RefCounted
var generated_v3_inventory_panel: VBoxContainer
var v3_inventory_choice: CheckButton
var generated_v3_equipment_mode:=false
var generated_v3_equipment_adventure:RefCounted
var generated_v3_equipment_panel:VBoxContainer
var generated_v3_enemy_mode:=false
var generated_v3_enemy_adventure:RefCounted
var generated_v3_enemy_panel:VBoxContainer
var generated_v3_npc_mode:=false
var generated_v3_npc_adventure:RefCounted
var generated_v3_npc_panel:VBoxContainer
var npc_notes_dialog:AcceptDialog
var v3_adventure_style:OptionButton
var v3_vegetation_choice:CheckButton
var v3_legacy_settings:VBoxContainer
var generated_v3_village_mode := false
var generated_v3_village_adventure: RefCounted
var v3_village_choice: CheckButton
var generated_v3_panel: VBoxContainer
var v3_setup_dialog: ConfirmationDialog
var v3_seed_input: LineEdit
var v3_radius_choice: OptionButton
var v3_recipe_choice: OptionButton
var startup_legacy := false
var screenshot_serial := 0
var mode_legend: Label
var action_panel: PanelContainer
var hero_panel: PanelContainer
var area_panel: VBoxContainer
var map_cluster: Control
var minimap: Control
var latest_dialogue: Label
var dialogue_speaker: Label
var turn_counter: Label
var quest_label: Label
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var health_text: Label
var stamina_text: Label
var advanced_scroll: ScrollContainer
var advanced_dialog
var advanced_menu: PopupMenu
var adventure_menu: PopupMenu
var display_menu: PopupMenu
var end_turn_requested := false
var river_entry_controller: Node
const RIVER_EXPERIMENT_MENU_ID := 1001
var natural_coast_entry_controller: Node
const NATURAL_COAST_MENU_ID := 1201
const NATURAL_PLATEAU_MENU_ID := 1202
var end_turn_busy := false
var _enemy_runtime_was_busy := false
var default_window_mode := Window.MODE_MAXIMIZED
var hud_font: Font
var portrait: Control
var history_title: Label
var turn_footer: HBoxContainer
var dialogue_restore_button: Button
var dialogue_hidden_for_map := false
var target_row: HBoxContainer
var speech_panel: PanelContainer
var action_base: PanelContainer
# The legacy Game is a detached visual-inspection model only in release UI.
# Its protocol remains in core for regression, never as an action authority.
const MAP_PREVIEW_NOTICE := "多地貌地图预览（只读） · 尚未接入当前行动规则"
var _mode_epoch := 0
var _import_epoch := -1
var _import_file_epoch := -1
var _export_epoch := -1
var _world_build_epoch := 0
var _mode_ui_snapshots: Dictionary = {}

var private_main_visual:Node
const PRIVATE_VISUAL_MENU_ID=9801
const PrivateMainVisual=preload("res://private_main_visual/controller.gd")
func _ready() -> void:
	# Responsive UI uses actual pixels, never a scaled-down 1440px canvas.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if DisplayServer.get_name() != "headless" and not OS.has_environment("FOGBANK_QA_WINDOWED"):
		get_window().mode=Window.MODE_MAXIMIZED
	game=Game.new();game.new_world();provider=Provider.new()
	runtime_ai=RuntimeAI.new(); runtime_ai.name="OptionalAITransport"; add_child(runtime_ai)
	runtime_ai.assessment_validated.connect(_on_runtime_assessment)
	runtime_ai.narration_received.connect(_on_runtime_narration)
	runtime_ai.status_changed.connect(set_status)
	runtime_ai.changed.connect(_on_runtime_changed)
	runtime_ai.intention_ready.connect(_on_actor_intention_ready)
	make_theme()
	build_ui()
	private_main_visual=PrivateMainVisual.new();private_main_visual.name="PrivateMainVisualBridge";add_child(private_main_visual)
	add_child(preload("res://view/tabletop_interaction/wasd_camera_pan.gd").new(self))
	add_child(preload("res://view/tabletop_interaction/selection_motion.gd").new(self))
	ui_presenter=preload("res://view/ui_motion/presenter.gd").new();ui_presenter.name="UIPresenter";add_child(ui_presenter);ui_presenter.bind(self)
	history_motion=ui_presenter;popup_motion=ui_presenter
	for popup:Window in [tools_menu.get_popup(),adventure_menu,advanced_menu,display_menu,focus_choice_popup,advanced_dialog,runtime_connection_panel.settings_dialog,playtest_reset_dialog,scene_test_confirm_dialog,inventory_dialog,focus_details_dialog,effects_dialog,world_dialog,help_dialog,import_dialog,demo_confirm_dialog,restart_confirm_dialog,journal_drawer,v3_setup_dialog,npc_notes_dialog]:popup_motion.watch(popup)
	add_child(preload("res://view/tabletop_interaction/offline_move_demo.gd").new(self))
	# Default startup replaces this initial legacy board before the first frame.
	# Build its terrain only when requested, or if the coast cannot be opened.
	var legacy_start := startup_legacy or OS.has_environment("FOGBANK_LEGACY_START") or "--legacy-start" in OS.get_cmdline_user_args()
	if legacy_start:
		refresh_world()
		board.focus_player()
	append_journal("地图预览（只读）", "可移动镜头、关注地貌并查看详情。此旧版地图尚未接入当前行动规则；不会提交行动。")
	set_status(MAP_PREVIEW_NOTICE)
	if not legacy_start:
		switch_coast()
		if not coast_mode:
			refresh_world()
			board.focus_player()
	if DisplayServer.get_name() != "headless" and DirAccess.dir_exists_absolute("res://artifacts"):
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("res://artifacts/first_board.png")

func style(bg: Color, border: Color=Color.TRANSPARENT, _radius:=0) -> StyleBox:
	var border_color := border if border.a>0 else bg.darkened(0.18)
	return Materials.frame_style(bg,border_color,12.0,"dark" if bg.get_luminance()<0.25 else "parchment")

func hud_surface(color: Color, pad := 12.0, line := Color(1,1,1,0.12)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = line
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.shadow_color = Color(0.04,0.06,0.10,0.28)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0,3)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: box.set_content_margin(side,pad)
	return box

func style_hud_button(b: Button, primary := false) -> void:
	preload("res://view/fullscreen_hud/button_theme.gd").apply(b, "primary" if primary else "secondary")

func make_theme() -> void:
	var t := Theme.new()
	var bold := FontVariation.new(); bold.base_font = Craft.font("body"); bold.variation_embolden = 0.35
	hud_font = Craft.font("body")
	t.default_font = hud_font
	t.default_font_size = 17
	for type_ in ["Label","Button","TooltipLabel","PopupMenu","RichTextLabel"]:
		t.set_constant("outline_size",type_,0)
		t.set_color("font_shadow_color",type_,Color.TRANSPARENT)
		t.set_constant("shadow_offset_x",type_,1)
		t.set_constant("shadow_offset_y",type_,2)
		t.set_constant("shadow_outline_size",type_,1)
		t.set_color("font_color",type_,INK)
	t.set_color("default_color","RichTextLabel",INK)
	t.set_font("normal_font","RichTextLabel",hud_font)
	t.set_font("bold_font","RichTextLabel",bold)
	t.set_constant("line_separation","RichTextLabel",5)
	t.set_constant("line_spacing","Label",3)
	t.set_constant("line_spacing","TextEdit",3)
	t.set_constant("v_separation","PopupMenu",16)
	t.set_constant("h_separation","PopupMenu",12)
	t.set_font("title_font","Window",bold)
	t.set_font_size("title_font_size","Window",19)
	for state in ["normal","hover","pressed","disabled"]:
		t.set_stylebox(state,"Button",Straw.surface("button",10.0,state))
	for type_ in ["TextEdit","LineEdit"]:
		t.set_stylebox("normal",type_,Straw.surface("writing",12.0))
		t.set_stylebox("focus",type_,Straw.surface("writing",12.0,"hover"))
		t.set_stylebox("read_only",type_,Straw.surface("writing",12.0))
		t.set_color("font_color",type_,INK)
		t.set_color("font_readonly_color",type_,Color("5d6c61"))
		t.set_color("caret_color",type_,INK)
		t.set_color("font_placeholder_color",type_,Color("7b7f65"))
		t.set_color("selection_color",type_,Color("c2d1aa"))
	t.set_stylebox("panel","AcceptDialog",Straw.surface("panel",18.0))
	t.set_stylebox("panel","PopupMenu",Straw.surface("panel",12.0))
	t.set_stylebox("hover","PopupMenu",Straw.surface("button",7.0,"hover"))
	t.set_color("font_hover_color","PopupMenu",INK)
	t.set_color("font_disabled_color","PopupMenu",Color("87939f"))
	t.set_stylebox("panel","TooltipPanel",Straw.surface("panel",12.0))
	var scroll := StyleBoxFlat.new(); scroll.bg_color=Color(0.20,0.28,0.23,0.10)
	var grab := StyleBoxFlat.new(); grab.bg_color=Color(0.40,0.47,0.34,0.6); grab.set_corner_radius_all(3)
	t.set_stylebox("scroll","VScrollBar",scroll)
	for name_ in ["grabber","grabber_highlight","grabber_pressed"]: t.set_stylebox(name_,"VScrollBar",grab)
	theme = t

func label(text: String, size:=16, color: Color=INK) -> Label:
	var l=Label.new();l.text=text;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color)
	l.add_theme_font_override("font",hud_font)
	preload("res://view/ui_typography/style.gd").text(l,20 if size>=19 else (18 if size>=17 else (16 if size==16 else 15)),hud_font,size>=20,color)
	l.add_theme_constant_override("outline_size",0)
	l.add_theme_color_override("font_shadow_color",Color(0.04,0.08,0.08,0.50) if color==Color.WHITE else Color.TRANSPARENT)
	l.add_theme_constant_override("shadow_offset_x",1)
	l.add_theme_constant_override("shadow_offset_y",2)
	l.add_theme_constant_override("shadow_outline_size",1)
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return l

func button(text: String, callback: Callable, primary:=false) -> Button:
	var b=Button.new();b.text=text;b.pressed.connect(callback);b.custom_minimum_size.y=36
	b.action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS
	var icon_kind := ""
	if text.contains("提交"): icon_kind="quill"
	elif text.contains("D20"): icon_kind="die"
	elif text.contains("行囊"): icon_kind="satchel"
	elif text.contains("保存"): icon_kind="save"
	elif text.contains("读取"): icon_kind="book"
	elif text.contains("新世界"): icon_kind="world"
	elif text.contains("清除") or text.contains("取消"): icon_kind="clear"
	elif text.contains("导出"): icon_kind="export"
	elif text.contains("导入"): icon_kind="import"
	elif text.contains("玩法"): icon_kind="help"
	elif text.contains("体验"): icon_kind="die"
	elif text.contains("书写"): icon_kind="quill"
	elif text.contains("手记"): icon_kind="book"
	elif text.contains("近看"): icon_kind="focus"
	elif text.contains("全图"): icon_kind="world"
	if not icon_kind.is_empty():
		b.set_meta("icon_kind",icon_kind)
		b.icon=Icons.small_texture(icon_kind,"ece4c7" if primary else "697759",20)
		b.expand_icon=false
		b.add_theme_constant_override("icon_max_width",20)
		b.add_theme_constant_override("h_separation",8)
	style_hud_button(b,primary)
	return b

func toolbar_button(text: String,callback:Callable)->Button:
	var b=button(text,callback)
	Craft.apply_button(b,"tool",8.0)
	if b.has_meta("icon_kind"): b.icon=Icons.small_texture(b.get_meta("icon_kind"),"c8cbb0",20)
	return b

func panel() -> PanelContainer:
	var p=PanelContainer.new();p.add_theme_stylebox_override("panel",style(PAPER,Color("9b8d6f")))
	return p

func decorate_frame(parent: Control) -> void:
	var frame = StrategyFrame.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(frame)

func heading_strip(content: Control) -> PanelContainer:
	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel",style(INK,Color("aa9160"),0))
	strip.add_child(content)
	return strip

func compact_style(bg: Color, border: Color, pad: float = 5.0, kind: String = "parchment") -> StyleBoxTexture:
	var result = Materials.frame_style(bg, border, pad, kind)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, 4.0)
	return result

func compact_button(text: String, callback: Callable, primary := false) -> Button:
	var b = button(text, callback, primary)
	b.theme = theme
	b.custom_minimum_size.y = 30
	b.add_theme_font_size_override("font_size", 16 if primary else 14)
	b.add_theme_constant_override("icon_max_width", 16)
	b.add_theme_constant_override("h_separation", 7)
	style_hud_button(b,primary)
	if b.has_meta("icon_kind"): b.icon=Icons.small_texture(b.get_meta("icon_kind"),"ece4c7" if primary else "697759",16)
	return b

func compact_tool_button(text: String, callback: Callable) -> Button:
	var b=compact_button(text,callback)
	Craft.apply_button(b,"tool",4.0)
	if b.has_meta("icon_kind"): b.icon=Icons.small_texture(b.get_meta("icon_kind"),"c8cbb0",16)
	return b

func icon_button(kind: String, tooltip: String, callback: Callable) -> Button:
	var b := Button.new(); b.name = "HUD_"+kind
	b.icon = Icons.small_texture(kind,"344740",23)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(42,42)
	b.pressed.connect(callback)
	style_round_button(b)
	return b

func style_round_button(b: Button, turn := false) -> void:
	preload("res://view/fullscreen_hud/button_theme.gd").apply(b, "turn" if turn else "round")
	if turn: b.icon = null

func build_ui() -> void:
	# The world owns the entire client rectangle. Every HUD group floats above it.
	board_container = SubViewportContainer.new()
	board_container.name = "FullScreenWorld"
	board_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_container.stretch = true
	add_child(board_container)
	viewport = SubViewport.new(); viewport.size = Vector2i(1440,900)
	viewport.handle_input_locally = true; viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board_container.add_child(viewport)
	board = Board.new(); board.attention_ui_mode=true
	board.set_meta("diagnosis_skip_startup_sky",not startup_legacy and not OS.has_environment("FOGBANK_LEGACY_START") and not "--legacy-start" in OS.get_cmdline_user_args())
	viewport.add_child(board)
	board.focus_candidates.connect(on_focus_candidates); board.hex_hovered.connect(on_hex_hovered)

	area_panel = VBoxContainer.new(); area_panel.name="AreaTitle"
	area_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	area_panel.add_theme_constant_override("separation",2)
	add_child(area_panel)
	map_title=label("雾河遗迹",25,Color.WHITE); area_panel.add_child(map_title)
	turn_counter=label("探索 · 第 1 回合",15,Color.WHITE); area_panel.add_child(turn_counter)
	quest_label=label("",15,Color.WHITE); quest_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; area_panel.add_child(quest_label); quest_label.hide()

	map_cluster=Control.new(); map_cluster.name="MapControls"; map_cluster.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(map_cluster)
	minimap=preload("res://view/fullscreen_hud/minimap.gd").new()
	minimap.name="Minimap"; map_cluster.add_child(minimap)
	minimap.activated.connect(toggle_overview)
	var focus=icon_button("focus","聚焦旅人",focus_player_view); focus.position=Vector2(23,194); map_cluster.add_child(focus)
	var overview=icon_button("world","查看全图",toggle_overview); overview.position=Vector2(83,215); map_cluster.add_child(overview)
	var inventory=icon_button("satchel","打开行囊",show_inventory); inventory.position=Vector2(143,194); map_cluster.add_child(inventory)
	tools_menu=MenuButton.new(); tools_menu.flat=false; tools_menu.name="AdventureMenu"; tools_menu.icon=Icons.small_texture("menu","344740",23)
	tools_menu.tooltip_text="菜单 · 冒险 / 主持手记 / 连接与高级 / 显示"
	tools_menu.custom_minimum_size=Vector2(42,42); tools_menu.position=Vector2(179,0); style_round_button(tools_menu)
	map_cluster.add_child(tools_menu)
	var menu := tools_menu.get_popup()
	adventure_menu=PopupMenu.new(); adventure_menu.name="Adventure"; menu.add_child(adventure_menu)
	adventure_menu.add_item("保存冒险",1); adventure_menu.add_item("读取冒险",2); adventure_menu.add_item("重新开始",3)
	adventure_menu.add_separator(); adventure_menu.add_item("多地貌地图预览（只读）",12); adventure_menu.add_item("返回海岸冒险",13); adventure_menu.add_item("查看河岸",11); adventure_menu.add_item("玩法说明",0)
	adventure_menu.add_item("以预览地图开始探索（第一阶段）",14); adventure_menu.add_item("继续多地貌探索",15)
	adventure_menu.add_separator(); adventure_menu.add_item("开始探索 / 村庄冒险",16); adventure_menu.add_item("继续村庄冒险",27); adventure_menu.add_item("旅途笔记",28)
	adventure_menu.id_pressed.connect(on_tool_selected)
	advanced_menu=PopupMenu.new(); advanced_menu.name="Advanced"; menu.add_child(advanced_menu)
	advanced_menu.add_item("离线 · 手动 JSON",20); advanced_menu.add_item("高级工具与调试",21); advanced_menu.add_item("AI接口设置（可选）",24)
	advanced_menu.add_separator("旧进度与测试"); advanced_menu.add_item("继续探索（无行囊）",17); advanced_menu.add_item("继续行囊探索",18); advanced_menu.add_item("继续旧村落行囊探索",19); advanced_menu.add_item("继续原村庄冒险",29); advanced_menu.add_item("继续原近战村庄冒险",30)
	advanced_menu.add_item("海岸冒险",10); advanced_menu.add_item("旧版测试场",8); advanced_menu.add_item("地图预览（只读）",9)
	advanced_menu.add_separator("限定实验");advanced_menu.add_item("离线河流测试 · 固定小地图",RIVER_EXPERIMENT_MENU_ID)
	advanced_menu.add_item("自然海岸 · 基础探索",NATURAL_COAST_MENU_ID)
	advanced_menu.add_item("自然高原海岸 · 基础探索",NATURAL_PLATEAU_MENU_ID)
	advanced_menu.add_item("统一行动测试 · 以当前地图新开",ACTOR_ENTRY_NEW)
	advanced_menu.add_item("继续统一行动测试（独立存档）",ACTOR_ENTRY_CONTINUE)
	advanced_menu.add_item("行动状态测试 · 以当前地图新开",ACTOR_STATUS_ENTRY_NEW)
	advanced_menu.add_item("继续行动状态测试（独立存档）",ACTOR_STATUS_ENTRY_CONTINUE)
	advanced_menu.add_item("新场景往返测试（会重置）",25); advanced_menu.add_item("演出测试",4); advanced_menu.add_item("已记录回合",5); advanced_menu.id_pressed.connect(on_tool_selected)
	advanced_menu.add_separator("界面预设示例")
	for example_id:int in preload("res://view/ui_motion/examples.gd").WINDOWS:
		advanced_menu.add_item(preload("res://view/ui_motion/examples.gd").WINDOWS[example_id].title,example_id)
	display_menu=PopupMenu.new(); display_menu.name="Display"; menu.add_child(display_menu)
	display_menu.add_check_item("全屏  ·  F11",22)
	display_menu.add_radio_check_item("低负载 · 无抗锯齿",6)
	display_menu.add_radio_check_item("均衡 · 2× MSAA",26)
	display_menu.add_radio_check_item("精细 · 4× MSAA",7)
	display_menu.add_check_item("有色硬影实验（可撤回）",PRIVATE_VISUAL_MENU_ID)
	display_menu.id_pressed.connect(on_tool_selected)
	menu.add_submenu_item("冒险", "Adventure")
	menu.add_item("主持手记",23)
	menu.add_submenu_item("连接与高级", "Advanced")
	menu.add_submenu_item("显示", "Display")
	menu.id_pressed.connect(on_tool_selected)
	quality_choice=OptionButton.new()
	for quality_label in preload("res://view/render_quality.gd").LABELS: quality_choice.add_item(quality_label)
	quality_choice.hide(); add_child(quality_choice)

	hero_panel=PanelContainer.new(); hero_panel.name="CharacterStatus"
	hero_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(hero_panel)
	var hero_row := HBoxContainer.new(); hero_row.add_theme_constant_override("separation",0); hero_panel.add_child(hero_row)
	portrait=preload("res://view/fullscreen_hud/portrait.gd").new(); portrait.custom_minimum_size=Vector2(100,124); portrait.size_flags_vertical=Control.SIZE_SHRINK_CENTER; hero_row.add_child(portrait)
	var status_mount:=PanelContainer.new(); var status_skin:=Ornament.surface("status",10); status_skin.set_content_margin(SIDE_TOP,24); status_skin.set_content_margin(SIDE_BOTTOM,24); status_skin.set_content_margin(SIDE_LEFT,30); status_skin.set_content_margin(SIDE_RIGHT,24); status_mount.add_theme_stylebox_override("panel",status_skin); status_mount.size_flags_vertical=Control.SIZE_SHRINK_CENTER; hero_row.add_child(status_mount)
	var hero_col:=VBoxContainer.new(); hero_col.custom_minimum_size.x=110; hero_col.add_theme_constant_override("separation",5); hero_col.size_flags_vertical=Control.SIZE_SHRINK_CENTER; status_mount.add_child(hero_col)
	hero_label=label("旅人",21,INK); hero_col.add_child(hero_label)
	hero_subtitle=label("河岸探路者",13,MUTED); hero_subtitle.max_lines_visible=3; hero_col.add_child(hero_subtitle)
	health_bar=make_resource_bar(Color("d28672")); hero_col.add_child(health_bar)
	health_text=resource_text(health_bar)
	stamina_bar=make_resource_bar(Color("9fba7b")); hero_col.add_child(stamina_bar)
	stamina_text=resource_text(stamina_bar)

	action_panel=PanelContainer.new(); action_panel.name="DialogueDock"
	action_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(action_panel)
	var action_col:=VBoxContainer.new(); action_col.add_theme_constant_override("separation",2); action_panel.add_child(action_col)
	speech_panel=PanelContainer.new(); var speech_skin:=Ornament.surface("speech",12); speech_skin.set_content_margin(SIDE_TOP,26); speech_skin.set_content_margin(SIDE_BOTTOM,34); speech_skin.set_content_margin(SIDE_LEFT,34); speech_skin.set_content_margin(SIDE_RIGHT,34); speech_panel.add_theme_stylebox_override("panel",speech_skin); action_col.add_child(speech_panel)
	var speech_col:=VBoxContainer.new(); speech_col.add_theme_constant_override("separation",4); speech_panel.add_child(speech_col)
	var dialogue_head:=HBoxContainer.new(); dialogue_head.add_theme_constant_override("separation",8); speech_col.add_child(dialogue_head)
	var dialogue_mark:=TextureRect.new(); dialogue_mark.texture=Icons.small_texture("chat","87613f",18); dialogue_mark.custom_minimum_size=Vector2(18,18); dialogue_mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; dialogue_mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER; dialogue_mark.mouse_filter=Control.MOUSE_FILTER_IGNORE; dialogue_head.add_child(dialogue_mark)
	dialogue_speaker=label("主持人",18,Color("754c37")); dialogue_speaker.size_flags_horizontal=Control.SIZE_EXPAND_FILL; dialogue_head.add_child(dialogue_speaker)
	journal_toggle=button("对话记录",toggle_journal); journal_toggle.name="HistoryToggle"; journal_toggle.custom_minimum_size.y=30; journal_toggle.add_theme_font_size_override("font_size",14); compact_hud_control(journal_toggle); dialogue_head.add_child(journal_toggle)
	latest_dialogue=label("晨雾尚未散去，海岸上的旧灯已经熄了三夜。",17,INK)
	latest_dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; latest_dialogue.custom_minimum_size.y=27; latest_dialogue.max_lines_visible=2; latest_dialogue.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	speech_col.add_child(latest_dialogue)
	action_base=PanelContainer.new(); action_base.add_theme_stylebox_override("panel",Ornament.surface("dock",12)); action_col.add_child(action_base)
	var body_col:=VBoxContainer.new(); body_col.add_theme_constant_override("separation",4); action_base.add_child(body_col)
	target_row=HBoxContainer.new(); target_row.add_theme_constant_override("separation",6); speech_col.add_child(target_row); target_row.hide()
	target_label=label("未选中目标",14,MUTED); target_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; target_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; target_row.add_child(target_label)
	var detail_button=icon_button("book","查看目标详情",show_focus_details); detail_button.custom_minimum_size=Vector2(30,28); compact_hud_control(detail_button); target_row.add_child(detail_button)
	route_preview_label=label("",13,MUTED); route_preview_label.name="ReadOnlyRoutePreview"; route_preview_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; route_preview_label.max_lines_visible=2; speech_col.add_child(route_preview_label); route_preview_label.hide()
	focus_choice_button=icon_button("target","更换关注对象",show_focus_choices); focus_choice_button.custom_minimum_size=Vector2(30,28); compact_hud_control(focus_choice_button); focus_choice_button.hide(); target_row.add_child(focus_choice_button)
	focus_choice_popup=PopupMenu.new(); focus_choice_popup.id_pressed.connect(_choose_focus); add_child(focus_choice_popup)
	clear_target_button=icon_button("clear","取消关注",clear_target); clear_target_button.custom_minimum_size=Vector2(30,28); compact_hud_control(clear_target_button); clear_target_button.disabled=true; target_row.add_child(clear_target_button)
	intent_expand_button=icon_button("quill","展开 / 收起书写",toggle_intent); intent_expand_button.custom_minimum_size=Vector2(30,28); compact_hud_control(intent_expand_button); dialogue_head.add_child(intent_expand_button)
	var input_row:=HBoxContainer.new(); input_row.add_theme_constant_override("separation",10); body_col.add_child(input_row)
	goal=TextEdit.new(); goal.name="PlayerIntent"; goal.custom_minimum_size.y=64; goal.size_flags_vertical=Control.SIZE_SHRINK_CENTER; goal.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	goal.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; goal.language="zh_CN"
	goal.placeholder_text="你想做什么？"; input_row.add_child(goal)
	goal.text_changed.connect(invalidate_sample_draft)
	goal.text_set.connect(invalidate_sample_draft)
	goal.lines_edited_from.connect(func(_from: int, _to: int): invalidate_sample_draft())
	submit_button=button("结束\n回合",end_turn,true); submit_button.name="EndTurn"; style_round_button(submit_button,true); submit_button.custom_minimum_size=Vector2(88,88); submit_button.tooltip_text="提交你的意图；取得有效裁定后，完成一次回合"; input_row.add_child(submit_button)
	var footer:=HBoxContainer.new(); turn_footer=footer; footer.add_theme_constant_override("separation",12); speech_col.add_child(footer)
	phase_label=label("等待你的行动",14,Color("4e7153")); footer.add_child(phase_label)
	next_step_label=label("",14,MUTED); next_step_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; next_step_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; next_step_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; footer.add_child(next_step_label)

	journal_panel=PanelContainer.new(); journal_panel.name="HistoryPanel"
	var history_skin:=Ornament.surface("history",30.0); history_skin.set_content_margin(SIDE_LEFT,34); history_skin.set_content_margin(SIDE_RIGHT,34); journal_panel.add_theme_stylebox_override("panel",history_skin)
	add_child(journal_panel); journal_panel.hide()
	var history_col:=VBoxContainer.new(); history_col.add_theme_constant_override("separation",10); journal_panel.add_child(history_col)
	var history_head:=HBoxContainer.new(); history_col.add_child(history_head)
	history_title=label("对话记录",19,INK); history_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; history_head.add_child(history_title)
	var close_history:=icon_button("clear","收起对话记录",toggle_journal); close_history.custom_minimum_size=Vector2(32,30); history_head.add_child(close_history)
	journal=RichTextLabel.new(); journal.name="ConversationHistory"; journal.bbcode_enabled=true
	journal.tooltip_text="叙事文字只是记录；生命、物品与行动结果以游戏中已结算的状态为准。"
	journal.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; journal.fit_content=false
	journal.scroll_active=true; journal.scroll_following=true; journal.selection_enabled=true
	journal.size_flags_horizontal=Control.SIZE_EXPAND_FILL; journal.size_flags_vertical=Control.SIZE_EXPAND_FILL
	journal.add_theme_font_size_override("normal_font_size",17); journal.language="zh_CN"
	# Reserve breathing room inside the shaped frame, also when a scrollbar is
	# present. Wrap full paragraphs; never ellipsize or horizontally crop history.
	var history_text_inset:=StyleBoxEmpty.new()
	history_text_inset.set_content_margin(SIDE_LEFT,2); history_text_inset.set_content_margin(SIDE_RIGHT,16)
	history_text_inset.set_content_margin(SIDE_TOP,2); history_text_inset.set_content_margin(SIDE_BOTTOM,6)
	journal.add_theme_stylebox_override("normal",history_text_inset)
	history_col.add_child(journal)

	dialogue_restore_button=icon_button("chat","显示对话，保留当前镜头",func(): set_map_dialogue_hidden(false))
	dialogue_restore_button.name="RestoreDialogue"; add_child(dialogue_restore_button); dialogue_restore_button.hide()

	# Low-frequency transport, regressions and numerical traces live off the map.
	advanced_dialog=preload("res://view/ui_motion/modal_window.gd").new(); advanced_dialog.configure(&"large",{"preferred":Vector2(800,660)}); advanced_dialog.name="AdvancedTools"; advanced_dialog.title="连接与高级"; advanced_dialog.ok_button_text="返回冒险"; advanced_dialog.size=Vector2i(760,650); add_child(advanced_dialog)
	advanced_scroll=ScrollContainer.new(); advanced_scroll.custom_minimum_size=Vector2(700,540); advanced_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; advanced_dialog.add_child(advanced_scroll)
	var advanced_col:=VBoxContainer.new(); advanced_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL; advanced_col.add_theme_constant_override("separation",14); advanced_scroll.add_child(advanced_col)
	relay_note=label("当前为离线模式，尚未连接 AI。
结束回合会等待人工裁定，不会自动生成回复。",17,Color.WHITE); relay_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; relay_note.custom_minimum_size.x=650; advanced_col.add_child(relay_note)
	relay_row=HBoxContainer.new(); relay_row.add_theme_constant_override("separation",10); advanced_col.add_child(relay_row)
	export_button=button("导出请求 JSON",export_request); relay_row.add_child(export_button)
	import_button=button("导入裁定 JSON",show_import); relay_row.add_child(import_button)
	cancel_button=button("取消等待",cancel_pending); advanced_col.add_child(cancel_button)
	status_label=label("",15,MUTED); status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status_label.custom_minimum_size.x=650; advanced_col.add_child(status_label)
	map_stats_label=label("",14,MUTED); advanced_col.add_child(map_stats_label)
	mode_legend=label("",14,MUTED); advanced_col.add_child(mode_legend)
	runtime_connection_panel=RuntimeConnectionPanel.new(); runtime_connection_panel.name="OptionalAIConnection"; runtime_connection_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; advanced_col.add_child(runtime_connection_panel); runtime_connection_panel.bind_runtime(runtime_ai)
	runtime_connection_panel.modal_visibility_changed.connect(_on_api_modal_visibility)
	# Settings emit before their final refresh. Reflect applied/dirty/consent
	# state on the next UI frame without issuing a request or changing choices.
	runtime_connection_panel.configuration_applied.connect(func(_result):_on_runtime_changed.call_deferred())
	for input in [runtime_connection_panel.endpoint_input,runtime_connection_panel.model_input,runtime_connection_panel.reasoning_input,runtime_connection_panel.key_input,runtime_connection_panel.budget_bytes_input]:
		input.text_changed.connect(func(_text):_on_runtime_changed.call_deferred())
	for toggle in [runtime_connection_panel.consent_input,runtime_connection_panel.localhost_input,runtime_connection_panel.automatic_assessment_input,runtime_connection_panel.automatic_narration_input]:
		toggle.toggled.connect(func(_value):_on_runtime_changed.call_deferred())
	runtime_connection_panel.budget_profile_input.item_selected.connect(func(_index):_on_runtime_changed.call_deferred())
	runtime_connection_panel.timeout_input.value_changed.connect(func(_value):_on_runtime_changed.call_deferred())
	runtime_connection_panel.clear_button.pressed.connect(func():_on_runtime_changed.call_deferred())
	playtest_panel=PlaytestPanel.new(); advanced_col.add_child(playtest_panel); playtest_panel.hide(); laboratory_panel=playtest_panel
	coast_panel=CoastPanel.new(); advanced_col.add_child(coast_panel); coast_panel.hide()
	coast_panel.fixture_pressed.connect(playtest_fixture); coast_panel.reset_pressed.connect(ask_reset_playtest); coast_panel.sample_requested.connect(fill_coast_sample)
	generated_panel=GeneratedPanel.new(); advanced_col.add_child(generated_panel); generated_panel.hide()
	generated_panel.fixture_pressed.connect(playtest_fixture); generated_panel.reset_pressed.connect(ask_reset_playtest); generated_panel.sample_requested.connect(fill_generated_sample)
	generated_v3_panel=V3Panel.new(); advanced_col.add_child(generated_v3_panel); generated_v3_panel.hide()
	generated_v3_panel.fixture_pressed.connect(playtest_fixture); generated_v3_panel.reset_pressed.connect(ask_reset_playtest); generated_v3_panel.sample_requested.connect(fill_generated_sample)
	generated_v3_inventory_panel=V3InventoryPanel.new();advanced_col.add_child(generated_v3_inventory_panel);generated_v3_inventory_panel.hide()
	generated_v3_inventory_panel.fixture_pressed.connect(playtest_fixture);generated_v3_inventory_panel.reset_pressed.connect(ask_reset_playtest);generated_v3_inventory_panel.sample_requested.connect(fill_generated_sample)
	generated_v3_npc_panel=V3NPCPanel.new();advanced_col.add_child(generated_v3_npc_panel);generated_v3_npc_panel.hide()
	generated_v3_npc_panel.fixture_pressed.connect(playtest_fixture);generated_v3_npc_panel.reset_pressed.connect(ask_reset_playtest);generated_v3_npc_panel.sample_requested.connect(fill_generated_sample)
	generated_v3_npc_panel.notes_requested.connect(show_npc_notes)
	generated_v3_enemy_panel=V3EnemyPanel.new();advanced_col.add_child(generated_v3_enemy_panel);generated_v3_enemy_panel.hide()
	generated_v3_enemy_panel.fixture_pressed.connect(playtest_fixture);generated_v3_enemy_panel.reset_pressed.connect(ask_reset_playtest);generated_v3_enemy_panel.sample_requested.connect(fill_generated_sample);generated_v3_enemy_panel.notes_requested.connect(show_npc_notes)
	generated_v3_equipment_panel=V3EquipmentPanel.new();advanced_col.add_child(generated_v3_equipment_panel);generated_v3_equipment_panel.hide()
	generated_v3_equipment_panel.fixture_pressed.connect(playtest_fixture);generated_v3_equipment_panel.reset_pressed.connect(ask_reset_playtest);generated_v3_equipment_panel.sample_requested.connect(fill_generated_sample);generated_v3_equipment_panel.notes_requested.connect(show_npc_notes)
	actor_action_panel=ActorEntryPanel.new();advanced_col.add_child(actor_action_panel);actor_action_panel.hide()
	actor_action_panel.decision_requested.connect(_request_actor_decision)
	actor_action_panel.cancel_requested.connect(cancel_pending)
	actor_action_panel.consent_changed.connect(func(enabled:bool):runtime_ai.authorize_intention_requests(enabled))
	npc_notes_dialog=AcceptDialog.new();npc_notes_dialog.title="旅途笔记";npc_notes_dialog.ok_button_text="关闭";add_child(npc_notes_dialog);npc_notes_dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	build_v3_setup_dialog()
	playtest_panel.fixture_pressed.connect(playtest_fixture); playtest_panel.reset_pressed.connect(ask_reset_playtest)
	roll_button=button("推进调试阶段",roll_dice); advanced_col.add_child(roll_button)
	die_label=label("D20 / —",16,Color.WHITE); advanced_col.add_child(die_label)
	demo_button=button("已记录的回合",start_demo); advanced_col.add_child(demo_button)
	advanced_col.move_child(runtime_connection_panel,advanced_col.get_child_count()-1)
	journal_drawer=AcceptDialog.new(); journal_drawer.title="主持手记"; add_child(journal_drawer)
	build_dialogs(); style_dialog_buttons(); restyle_advanced_text(advanced_dialog)
	set_quality(preload("res://view/render_quality.gd").default_preset(RenderingServer.get_video_adapter_name()))
	action_panel.minimum_size_changed.connect(func(): apply_responsive_layout.call_deferred())
	hero_panel.minimum_size_changed.connect(func(): apply_responsive_layout.call_deferred())
	get_viewport().size_changed.connect(apply_responsive_layout)
	apply_responsive_layout(); update_turn_controls()

func compact_hud_control(b: Button) -> void:
	preload("res://view/fullscreen_hud/button_theme.gd").apply(b, "compact_round" if b.text.is_empty() else "compact")

func restyle_advanced_text(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color",INK)
		node.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	elif node is RichTextLabel:
		node.add_theme_color_override("default_color",INK)
		node.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	elif node is Button:
		style_hud_button(node)
	for child in node.get_children(): restyle_advanced_text(child)

func make_resource_bar(color: Color) -> ProgressBar:
	var bar:=ProgressBar.new(); bar.custom_minimum_size.y=20; bar.show_percentage=false
	bar.add_theme_stylebox_override("background",Straw.surface("well",0.0))
	var fill:=StyleBoxFlat.new(); fill.bg_color=color; fill.border_color=color.lightened(0.22); fill.border_width_top=2; fill.set_corner_radius_all(2); bar.add_theme_stylebox_override("fill",fill)
	return bar

func resource_text(parent: Control) -> Label:
	var text_=label("",13,Color("253e37")); text_.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; text_.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); parent.add_child(text_); return text_

func update_character_status(actor: Dictionary, turn: int, state: Dictionary) -> void:
	var status_actor:Dictionary={"status_details":playtest.status_payload(str(actor.id))} if actor_action_mode else PlayerDetails.adapt_actor(state,actor)
	hero_label.text=actor.name
	hero_subtitle.text=PlayerDetails.status_caption(status_actor).replace(" · ","\n") if PlayerDetails.has_statuses(status_actor) else ("新地形旅人" if generated_v3_mode else "河岸探路者")
	hero_subtitle.tooltip_text="\n".join(PlayerDetails.status_lines(status_actor))
	health_bar.max_value=actor.health.max; health_bar.value=actor.health.current
	stamina_bar.max_value=actor.stamina.max; stamina_bar.value=actor.stamina.current
	health_text.text="生命  %d / %d" % [actor.health.current,actor.health.max]
	stamina_text.text="体力  %d / %d" % [actor.stamina.current,actor.stamina.max]
	turn_counter.text="探索 · 第 %d 回合" % (turn+1)
	if coast_mode and actor.get("scene_id","scene_coast")!="scene_coast":
		quest_label.text="场景框架测试 · 可从入口原路返回"; quest_label.tooltip_text="仅验证场景切换、独立坐标和持久状态；正式室内内容尚未制作。"; quest_label.show()
	elif coast_mode and playtest!=null and playtest.has_method("story_goal"):
		quest_label.text=playtest.story_goal(); quest_label.tooltip_text=quest_label.text; quest_label.show()
	elif generated_mode:
		var with_inventory: bool=state.get("generated_world",{}).get("inventory_profile") in ["generated_inventory/v1","generated_v3_inventory/v1"]
		quest_label.text="探索 · 移动 / 观察 / 休息"+(" / 行礼包" if with_inventory else "")
		quest_label.tooltip_text=("行礼包可经评估整件放下、拾回；" if with_inventory else "")+(("河流、城镇尚未开放；行囊只支持整件放下和拾回" if generated_v3_inventory_mode else "河流、城镇和物品互动尚未开放；只在已验证的干地上行走") if generated_v3_mode else "树木、桥梁、聚落、战斗和海岸故事尚未迁移");quest_label.show()
	else:quest_label.hide()
	if generated_v3_village_mode:
		quest_label.text="探索 · 移动 / 村落 / 行礼包"
		quest_label.tooltip_text="房屋会阻挡实际通路；可沿路靠近村落，点击查看建筑和道路。暂无人物、进屋、交易或实体河流。"
	if generated_v3_npc_mode:
		quest_label.text="村庄冒险 · 探索 / 行囊 / 交谈"
		quest_label.tooltip_text="靠近守路村民，写下交谈意图；登记信息会保存。点击只查看。"
	if generated_v3_enemy_mode:
		quest_label.text="村庄冒险 · 探索 / 交谈 / 近战";quest_label.tooltip_text="固定拦路者；双方分别评估。敌人倒下仍占格，中毒按每次已提交行动结算。"
	if actor_action_mode:
		quest_label.text="行动状态测试 · 普通行动 / 公开状态" if actor_status_mode else "统一行动测试 · 普通行动 / 原子回合";quest_label.tooltip_text="双方按已登记能力行动；无武器不取消普通行动资格，倒下仍占格。"
	minimap.set_world(SceneAdapters.projection(state,actor.scene_id) if coast_mode else state)

func focus_player_view() -> void:
	board.focus_player()
	set_map_dialogue_hidden(false)

func toggle_overview() -> void:
	if (coast_mode or generated_v3_mode) and board.world_view.overview:
		focus_player_view()
	else:
		board.reset_camera()
		set_map_dialogue_hidden(true)

func set_map_dialogue_hidden(hidden: bool) -> void:
	dialogue_hidden_for_map=hidden
	action_panel.visible=not hidden
	# History visibility is committed by the motion seam after responsive layout.
	dialogue_restore_button.visible=hidden
	apply_responsive_layout()

func toggle_fullscreen() -> void:
	if get_window().mode==Window.MODE_FULLSCREEN: get_window().mode=Window.MODE_MAXIMIZED
	else: get_window().mode=Window.MODE_FULLSCREEN
	display_menu.set_item_checked(display_menu.get_item_index(22),get_window().mode==Window.MODE_FULLSCREEN)

func show_advanced() -> void:
	if is_instance_valid(popup_motion):popup_motion.prepare_reopen(advanced_dialog)
	advanced_dialog.popup_centered(advanced_dialog.adapted_extent(get_viewport_rect().size))
	advanced_scroll.scroll_vertical=0

func show_ai_connection() -> void:
	if is_instance_valid(popup_motion):popup_motion.prepare_reopen(runtime_connection_panel.settings_dialog)
	runtime_connection_panel.open_settings()

func close_tool_menus() -> void:
	# Child popups can otherwise outlive their parent when a command opens a
	# modal window. Close the entire menu chain before changing UI focus.
	for popup in [adventure_menu, advanced_menu, display_menu]:
		if is_instance_valid(popup): popup.hide()
	if is_instance_valid(tools_menu): tools_menu.get_popup().hide()

func on_tool_selected(id: int) -> void:
	if preload("res://view/ui_motion/examples.gd").WINDOWS.has(id):
		close_tool_menus();preload("res://view/ui_motion/examples.gd").show_window(self,ui_presenter,id);return
	if id!=PRIVATE_VISUAL_MENU_ID and is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	if id!=PRIVATE_VISUAL_MENU_ID and is_instance_valid(private_main_visual):private_main_visual.after_world_change.call_deferred()
	close_tool_menus()
	match id:
		PRIVATE_VISUAL_MENU_ID:
			private_main_visual.toggle(self)
			display_menu.set_item_checked(display_menu.get_item_index(PRIVATE_VISUAL_MENU_ID),private_main_visual.requested)
			set_status("这幅地图还未完成表现登记，原来的显示已保留" if not private_main_visual.last_error.is_empty() else ("有色硬影实验已启用" if private_main_visual.requested else "实验表现已撤回"))
		0: show_help()
		1: save_game()
		2: load_game()
		3: ask_restart_game()
		4: show_effects()
		5: start_demo()
		6: set_quality(0)
		7: set_quality(1)
		8: switch_playtest(true)
		9: show_map_preview_selector()
		10: switch_coast()
		11: view_trial_river()
		12: show_map_preview_selector()
		13: return_from_map_preview()
		14: start_generated_from_preview()
		15: continue_generated_adventure()
		16: show_v3_setup()
		17: continue_v3_adventure()
		18: continue_v3_inventory_adventure()
		19: continue_v3_village_adventure()
		27: continue_v3_equipment_adventure()
		30: continue_v3_enemy_adventure()
		29: continue_v3_npc_adventure()
		28: show_npc_notes()
		20,21: show_advanced()
		22: toggle_fullscreen()
		23: toggle_journal()
		24: show_ai_connection()
		25: ask_scene_framework_test()
		26: set_quality(2)
		RIVER_EXPERIMENT_MENU_ID: open_river_experiment()
		NATURAL_COAST_MENU_ID: open_natural_coast_experiment("coastal_range")
		NATURAL_PLATEAU_MENU_ID: open_natural_coast_experiment("plateau_hinterland")
		ACTOR_ENTRY_NEW: start_actor_action_test()
		ACTOR_ENTRY_CONTINUE: continue_actor_action_test()
		ACTOR_STATUS_ENTRY_NEW: start_actor_status_test()
		ACTOR_STATUS_ENTRY_CONTINUE: continue_actor_status_test()

func toggle_intent() -> void:
	intent_expanded = not intent_expanded
	goal.custom_minimum_size.y = 134 if intent_expanded else 62
	apply_responsive_layout.call_deferred()

func update_journal_toggle() -> void:
	journal_toggle.text = "收起记录" if journal_open else "对话记录"
	journal_toggle.tooltip_text = "收起对话记录" if journal_open else "查看完整对话记录"
	journal_toggle.set_pressed_no_signal(journal_open)

func toggle_journal() -> void:
	if dialogue_hidden_for_map:
		set_map_dialogue_hidden(false)
		journal_open=true
	else:
		journal_open = not journal_open
	update_journal_toggle()
	apply_responsive_layout()

func apply_responsive_layout() -> void:
	if not is_instance_valid(action_panel): return
	preload("res://view/fullscreen_hud/readability.gd").configure(self)
	preload("res://view/ui_typography/style.gd").prepare_scene(self)
	if is_instance_valid(history_motion):history_motion.before_layout()
	preload("res://view/fullscreen_hud/responsive_layout.gd").apply(self)
	preload("res://view/ui_typography/style.gd").finish_layout(self)
	if is_instance_valid(history_motion):history_motion.after_layout()
	update_journal_toggle()
	_update_feedback_safe_rect()

func _update_feedback_safe_rect() -> void:
	if not is_instance_valid(board) or not board.has_method("set_presentation_safe_rect"): return
	var bounds := get_viewport_rect().size
	var screen := Rect2(Vector2(24,24),bounds-Vector2(48,48))
	var free_regions:Array[Rect2]=[screen]
	# Keep actual free space, including a side region when open history occupies
	# most of the middle. No fallback rectangle is invented over a visible HUD.
	for control in [area_panel,map_cluster,hero_panel,action_panel,journal_panel]:
		if not is_instance_valid(control) or not control.visible: continue
		var obstruction:Rect2=control.get_global_rect()
		if control==hero_panel:
			obstruction.size=obstruction.size.max(hero_panel.get_combined_minimum_size())
		obstruction=obstruction.grow(20.0).intersection(screen)
		var remaining:Array[Rect2]=[]
		for region in free_regions:
			if not region.intersects(obstruction):remaining.append(region);continue
			var overlap:Rect2=region.intersection(obstruction)
			var pieces:Array[Rect2]=[
				Rect2(region.position,Vector2(overlap.position.x-region.position.x,region.size.y)),
				Rect2(Vector2(overlap.end.x,region.position.y),Vector2(region.end.x-overlap.end.x,region.size.y)),
				Rect2(region.position,Vector2(region.size.x,overlap.position.y-region.position.y)),
				Rect2(Vector2(region.position.x,overlap.end.y),Vector2(region.size.x,region.end.y-overlap.end.y))]
			for piece in pieces:
				if piece.size.x>=48.0 and piece.size.y>=48.0:remaining.append(piece)
		free_regions=remaining
	var best:=Rect2()
	for region in free_regions:
		if region.size.x>=120.0 and region.size.y>=120.0 and region.get_area()>best.get_area():best=region
	board.set_presentation_safe_rect(best)

func set_quality(index:int)->void:
	var quality = preload("res://view/render_quality.gd")
	var profile:Dictionary=quality.apply(viewport,get_viewport(),board_container,index)
	index=int(profile.index)
	software_preview=bool(profile.software_preview)
	TerrainMaterials.set_software_preview(software_preview)
	quality_choice.select(index)
	if is_instance_valid(tools_menu):
		for preset_index in range(quality.MENU_IDS.size()):
			display_menu.set_item_checked(display_menu.get_item_index(quality.MENU_IDS[preset_index]),index==preset_index)
		tools_menu.tooltip_text="菜单 · 冒险 / 主持手记 / 连接与高级 / 显示\n当前："+str(profile.label)
	if is_instance_valid(status_label):
		set_status(quality.status(index))

func build_dialogs() -> void:
	playtest_reset_dialog = ConfirmationDialog.new()
	playtest_reset_dialog.title = "重置 AI-GM 测试渡口？"
	playtest_reset_dialog.dialog_text = "将替换本测试模式的当前进度。要保留请先取消并保存测试冒险。原v9冒险独立保留。"
	playtest_reset_dialog.ok_button_text = "重置测试渡口"
	playtest_reset_dialog.cancel_button_text = "保留进度"
	playtest_reset_dialog.confirmed.connect(reset_playtest)
	add_child(playtest_reset_dialog)
	scene_test_confirm_dialog=ConfirmationDialog.new();scene_test_confirm_dialog.title="新建场景框架测试？";scene_test_confirm_dialog.dialog_autowrap=true;scene_test_confirm_dialog.dialog_text="这会替换当前未保存进度，已有存档不会自动覆盖。测试只增加一个明确标注的七格房间，用于验证评估、往返和保存；它不是已完成的室内剧情。要保留当前冒险，请先取消并保存。";scene_test_confirm_dialog.ok_button_text="新建测试";scene_test_confirm_dialog.cancel_button_text="保留冒险";scene_test_confirm_dialog.confirmed.connect(start_scene_framework_test);add_child(scene_test_confirm_dialog)
	world_dialog=AcceptDialog.new();world_dialog.title="多地貌地图预览（只读）";world_dialog.size=Vector2i(560,390);world_dialog.ok_button_text="返回冒险"
	var world_col=VBoxContainer.new();world_col.add_theme_constant_override("separation",12);world_dialog.add_child(world_col)
	world_col.add_child(label("只读查看沙漠、草原、高原、丛林与海洋。
尚未接入当前行动规则；海岸冒险与存档保持不变。",14,MUTED))
	var seed_row=HBoxContainer.new();world_col.add_child(seed_row)
	seed_row.add_child(label("世界种子",14));seed_input=LineEdit.new();seed_input.text="726381";seed_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;seed_row.add_child(seed_input)
	seed_row.add_child(label("地图半径",14));radius_input=SpinBox.new();radius_input.min_value=4;radius_input.max_value=24;radius_input.step=1;radius_input.value=7;radius_input.tooltip_text="半径 24 为大型慢速实验：云端构建约 40 秒，Godot 静态内存增量约 1 GiB。不同电脑须实测。";seed_row.add_child(radius_input)
	generated_inventory_choice=CheckButton.new();generated_inventory_choice.text="新探索携带行礼包（可放下、拾回）";generated_inventory_choice.tooltip_text="仅在以预览开始新探索时生效；不会给旧存档补发物品。放下和拾回仍须提交文字、经过有效评估。";Craft.apply_button(generated_inventory_choice,"secondary");generated_inventory_choice.add_theme_color_override("font_hover_pressed_color",INK);world_col.add_child(generated_inventory_choice)
	world_col.add_child(button("生成多地貌预览（只读）",func():request_world_build(true),true))
	world_col.add_child(button("469 格多地貌预览（只读） · 半径 12",request_showcase_world))
	world_col.add_child(button("查看旧版雾河遗迹（只读）",func():request_world_build(false)))
	world_col.add_child(button("返回海岸冒险",return_from_map_preview))
	world_col.add_child(label("半径 12 云端约 9 秒；半径 24 大型慢速实验约 40 秒。\n生成时界面会暂时停顿。这里只查看地图，不能提交回合。",12,MUTED))
	add_child(world_dialog)
	effects_dialog = AcceptDialog.new()
	effects_dialog.title = "视觉演出预览 · 不提交行动"
	effects_dialog.size = Vector2i(520,300)
	var effects_col=VBoxContainer.new();effects_col.add_theme_constant_override("separation",10)
	effects_dialog.add_child(effects_col)
	var effects_note=label("以下是美术演示，不是 GM 裁定，不造成伤害或消耗。
实际移动仅在最终裁定提交后播放；真实受击来自生命变化。",13,MUTED)
	effects_note.custom_minimum_size.x=450
	effects_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	effects_col.add_child(effects_note)
	for pair in [["magic","魔法 · 符环与弧光"],["gunfire","枪火 · 闪焰与弹道"],["melee","攻击 · 弧刃"],["hit","受击 · 冲击与碎屑"]]:
		var kind: String=pair[0]
		effects_col.add_child(button(pair[1],func():
			effects_dialog.hide()
			board.showcase_effect(kind)
			set_status("演出预览："+kind+" · 没有提交行动或改变状态")))
	add_child(effects_dialog)
	restart_confirm_dialog = ConfirmationDialog.new()
	restart_confirm_dialog.title = "建立新世界？"
	restart_confirm_dialog.dialog_text = "当前进度和待处理请求会被替换。要保留这段冒险，请先取消并保存。"
	restart_confirm_dialog.ok_button_text = "建立新世界"
	restart_confirm_dialog.cancel_button_text = "返回冒险"
	restart_confirm_dialog.confirmed.connect(begin_world_build)
	add_child(restart_confirm_dialog)
	inventory_dialog = AcceptDialog.new()
	inventory_dialog.title = "旅人的行囊与状态"
	inventory_dialog.size = Vector2i(560, 510)
	inventory_dialog.ok_button_text = "返回地图"
	var satchel = VBoxContainer.new()
	satchel.add_theme_constant_override("separation", 12)
	inventory_dialog.add_child(satchel)
	var note = label("把想使用的物品写进行动里，具体效果交由 GM 裁定。", 13, MUTED)
	note.custom_minimum_size.x=460
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	satchel.add_child(note);inventory_note=note
	var item_scroll = ScrollContainer.new()
	item_scroll.custom_minimum_size = Vector2(460, 300)
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	satchel.add_child(item_scroll)
	inventory_box = VBoxContainer.new()
	inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_box.add_theme_constant_override("separation", 12)
	item_scroll.add_child(inventory_box)
	add_child(inventory_dialog)
	focus_details_dialog=AcceptDialog.new(); focus_details_dialog.title="目标详情"; focus_details_dialog.ok_button_text="返回地图"; focus_details_dialog.size=Vector2i(540,340); add_child(focus_details_dialog)
	focus_details_text=RichTextLabel.new(); focus_details_text.custom_minimum_size=Vector2(480,230); focus_details_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; focus_details_text.selection_enabled=true; focus_details_text.add_theme_font_size_override("normal_font_size",17); focus_details_dialog.add_child(focus_details_text)
	demo_confirm_dialog=ConfirmationDialog.new();demo_confirm_dialog.title="重新开始记录回放？"
	demo_confirm_dialog.dialog_text="记录回放需要从初始世界开始，会替换当前世界的进度。\n如需保留当前冒险，请先取消并保存。"
	demo_confirm_dialog.ok_button_text="重置并开始回放";demo_confirm_dialog.cancel_button_text="保留当前世界"
	demo_confirm_dialog.confirmed.connect(_begin_demo);add_child(demo_confirm_dialog)
	file_dialog=FileDialog.new();file_dialog.access=FileDialog.ACCESS_FILESYSTEM;file_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;file_dialog.filters=PackedStringArray(["*.json ; JSON 请求"]);file_dialog.file_selected.connect(on_file_selected);add_child(file_dialog)
	import_dialog=AcceptDialog.new();import_dialog.title="导入模型裁定 · JSON";import_dialog.size=Vector2i(760,540);import_dialog.ok_button_text="校验并应用";import_dialog.dialog_hide_on_ok=false
	var import_col=VBoxContainer.new();import_col.add_theme_constant_override("separation",10);import_dialog.add_child(import_col)
	import_text=TextEdit.new();import_text.custom_minimum_size=Vector2(710,410);import_text.size_flags_vertical=Control.SIZE_EXPAND_FILL;import_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;import_text.placeholder_text="粘贴与当前 action_id / state_version 匹配的 planning 或 resolution JSON。\n这里只检查结构与状态完整性，不替 GM 决定药剂或地形效果。";import_col.add_child(import_text)
	import_error_label=label("",14,Color("a45438"));import_error_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;import_col.add_child(import_error_label)
	import_col.add_child(button("从 JSON 文件载入 · 先预览",show_import_file))
	import_dialog.confirmed.connect(import_decision);add_child(import_dialog)
	import_file_dialog=FileDialog.new();import_file_dialog.access=FileDialog.ACCESS_FILESYSTEM;import_file_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;import_file_dialog.filters=PackedStringArray(["*.json ; 模型裁定 JSON"])
	import_file_dialog.file_selected.connect(_on_import_file_selected)
	import_file_dialog.canceled.connect(_on_import_file_canceled)
	add_child(import_file_dialog)
	help_dialog=AcceptDialog.new();help_dialog.title="怎么玩";help_dialog.size=Vector2i(700,560)
	var help=RichTextLabel.new();help.bbcode_enabled=true;help.custom_minimum_size=Vector2(650,480);help.text="[b]模型主持的自由叙事沙盘[/b]\n\n1. 左键关注角色、树、山地、地格或聚落。点击只是补充关注对象，不会开始行动。\n2. 必须写下你想做什么；可以把物品、移动、交谈等复合意图写在同一段话里，再提交。\n3. GM 先读取明确文字意图，再看相关关注事实和周围世界。文字中的明确目标优先；GM 决定效果、检定和难度。\n4. 点击 D20。把结果连同上下文交给 GM，最终可能成功、部分成功或失败。\n5. 只有通过完整性校验的最终裁定才更新数值状态。\n\n[b]当前连接：离线中继[/b]\n本项目没有伪装成已连接的实时 API。导出 JSON 请求，通过模型得到裁定，再导入 JSON；示例回合是实际模型产生的已记录结果，不能替代任意输入的实时 GM。\n\n物品仅展示名字和自然语言描述，没有饮用按钮或药剂效果解析器。黄色范围只作几何参考。关注不是目的地，也不会绑定移动、消耗或伤害规则。\n\n保存包含精确数值状态、事件与待处理回合的冻结关注。新点击可以改变下一次关注，不会改写当前请求。重复导入不会重复伤害，也不能重掷同一行动。";help.add_theme_constant_override("line_separation",3);help.language="zh_CN";help_dialog.add_child(help);add_child(help_dialog)


func style_dialog_buttons() -> void:
	for dialog in [advanced_dialog,playtest_reset_dialog,scene_test_confirm_dialog,inventory_dialog,focus_details_dialog,effects_dialog,world_dialog,help_dialog,import_dialog,demo_confirm_dialog,restart_confirm_dialog,journal_drawer,v3_setup_dialog,npc_notes_dialog]:
		var ok:Button=dialog.get_ok_button()
		style_hud_button(ok)
		ok.custom_minimum_size.y = 42
		if dialog is ConfirmationDialog:
			var cancel: Button = dialog.get_cancel_button()
			style_hud_button(cancel)
			cancel.custom_minimum_size.y = 42
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			ok.add_theme_color_override(state,INK)
		ok.add_theme_color_override("font_disabled_color",MUTED)

func show_import_file() -> void:
	if _block_preview_action() or _import_epoch != _mode_epoch: return
	_import_file_epoch = _mode_epoch
	import_dialog.hide()
	import_file_dialog.popup_centered_ratio(0.72)

func show_effects() -> void:
	if coast_mode:set_status("海岸演出只来自已提交的行动；可通过高级行动样例验证。");return
	effects_dialog.popup_centered()
func show_help() -> void:
	if actor_status_mode:
		append_journal("行动状态测试指南","双方的普通行动、登记物品与状态能力都先提交意图，再取得独立有效评估。点击只关注，不会使用物品或改变状态；敌方意图候选也需另行评估。状态只显示当前观察者可见的信息，移动以冻结路线和实际支撑校验为准。默认不发送意图请求；独立存档保留待处理阶段和已锁定结果。")
		if not journal_open:toggle_journal()
		return
	if generated_v3_equipment_mode:
		append_journal("取走与换装","敌人倒下后，可从真实干地连通的相邻格取走现有苦叶短刃，原格仍被占据。拾取与装备是两个分别评估的行动，点击示例只填入意图；换装后原武器仍在行囊里。两种操作不扣体力，但都提交一个行动，已有中毒会结算一次。不能从活着的敌人手里取走武器，也不能丢弃、转交或复制武器。当前只有这一个敌人，取走之后没有新的攻击目标；短刃的中毒能力会作为登记属性保留。")
		if not journal_open:toggle_journal()
		return
	if generated_v3_enemy_mode:
		append_journal("村庄遭遇指南","双方所有行动都必须取得各自的有效评估。近战只限真实干地通路连通的相邻格，每次耗费1体力。敌方固定守在原格，倒下后仍占格。苦叶短刃完整命中会施毒，后续每次已提交行动都会结算一次，敌方行动也计入。生命为零后不能行动，可读取存档或重新开始。高级示例是离线预设裁定，没有真实供应商调用。")
		if not journal_open:toggle_journal()
		return
	if generated_v3_npc_mode:
		append_journal("村庄冒险指南","点击只选择目标；写下行动并结束回合后，必须取得有效评估，游戏才会结算。默认离线，可导入评估或采用示例的预设裁定。在“连接与高级”配置接口、确认可能计费并启用自动评估后，自由文字可直接等待模型回复；未完成或无效的回复不会执行。交谈仍限登记话题，需先靠近村民。行礼包可放下和拾回。可选叙述只描写已提交结果，失败不影响回合，保存时另存文字记录。村庄资料上限仍为64 KiB，连接上限不会扩大行动范围；锁定结果不会重掷。旧进度保留在高级菜单。")
		if not journal_open:toggle_journal()
		return
	if generated_v3_mode:
		append_journal("新地形探索指南","左键关注旅人或地格，右键旋转、中键平移、滚轮缩放。点击不会行动。当前可移动、观察和休息；在“连接与高级”中选择示例，结束回合后应用预设裁定。自由文字须导入离线评估，尚未接入实时AI。冒险菜单可独立保存、读取或重新开始；已锁定的结果不会重掷。河流、城镇与物品互动尚未开放。" if not generated_v3_inventory_mode else "左键只关注，行动先描述再评估。行囊里可查看行礼包；在“连接与高级”选择移动、观察、休息、放下或拾回示例，结束回合后应用预设裁定。自由文字须导入离线评估，尚未接入实时AI。行礼包只可整件放下或拾回，不会因点击转移；没有拆分、装备或特殊效果。此模式单独保存，普通新地形探索和海岸进度保留。")
		if not journal_open:toggle_journal()
		return
	if is_map_preview():
		append_journal("地图预览指南", "这里是只读地图预览，尚未接入当前行动规则。右键旋转、中键平移、滚轮缩放；左键关注地貌，点击目标详情查看。菜单可选择种子与半径4–24，或返回原来的海岸冒险。旧版存档仅供查看，待处理行动不会恢复执行，也不会覆盖原文件。")
		set_status(MAP_PREVIEW_NOTICE)
		return
	if coast_mode:
		append_journal("冒险指南", "左键选定目标，右键旋转，中键平移，滚轮缩放。右上可聚焦旅人、查看全图、打开行囊。写下行动后点击结束回合；当前为离线模式，须从连接与高级导入有效裁定，等待期间世界不会改变。有效裁定会自动完成一次回合。高级窗口中的署名功能样例是手写演示。菜单的冒险页可保存或读取；已锁定的结果不会重掷。F11切换全屏，Esc收起历史或退出全屏。")
		if compact_layout and not journal_open: toggle_journal()
		return
	if playtest_mode:
		append_journal("测试模式 · 操作说明", "所有意图先经评估。点击仅关注，文字目标优先。可填入指定初始示例，提交后采用署名夹具评估；任意自由输入须手工导入ai_gm_assessment/v1。正式Decision Model与calculator未接入，当前rule A仅演示。准备后依次一次结算、暂存预览、提交数值。叙事可选，失败不会重掷或阻塞提交。单独保存为ai_gm_playtest_save.json；掷前允许取消，掷后不可取消。gate/listen是固定演示后果，不支持其他玩法。详细JSON字段见docs/ai_gm_playtest/HOW_TO_PLAY.md。")
		set_status("测试说明已写入主持手记")
		if not journal_open: toggle_journal()
		return
	help_dialog.popup_centered()
func show_inventory() -> void:
	var with_inventory: bool=generated_mode and playtest.state_copy().get("generated_world",{}).get("inventory_profile") in ["generated_inventory/v1","generated_v3_inventory/v1"]
	inventory_note.text="写下放下或拾回，经有效评估后由固定程序执行。" if with_inventory else ("这段探索尚未开放物品互动。" if generated_v3_mode else "把想使用的物品写进行动里，具体效果交由 GM 裁定。")
	if generated_v3_equipment_mode:inventory_note.text="行礼包可经评估放下或拾回；木杖与短刃只能经评估换装，不能丢弃或转交。换下的武器仍在行囊里。"
	inventory_dialog.reset_size()
	inventory_dialog.popup_centered(Vector2i(560,510))
func ask_restart_game() -> void:
	if playtest_mode: ask_reset_playtest(); return
	world_dialog.popup_centered()

func request_showcase_world() -> void:
	radius_input.value=12
	request_world_build(true)

func request_world_build(generated: bool) -> void:
	if world_build_busy or not _can_leave_current_adventure(): return
	var requested_radius := int(radius_input.value)
	if generated:
		var prepared_request := SeededWorld.make_request(seed_input.text,"coast_exploration",requested_radius)
		if not prepared_request.ok:
			set_status("种子设置无效 · 请填写1–256字节的文字或整数，半径须为4–24；原世界保留")
			return
		world_build_seed_token=prepared_request.request.seed_token
		world_build_seed=int(prepared_request.request.normalized_seed)
	world_build_requested=generated
	world_build_radius=requested_radius
	world_dialog.hide()
	if not is_map_preview(): _switch_mode("legacy")
	if not is_map_preview(): return
	begin_world_build()

func begin_world_build() -> void:
	if not is_map_preview() or world_build_busy: return
	world_build_busy=true
	_world_build_epoch += 1
	set_status("生成只读预览中 · 海岸冒险与存档保留；大地图会暂时停顿")
	call_deferred("_run_requested_world_build",_world_build_epoch)

func _run_requested_world_build(epoch: int = -1) -> void:
	# A cancelled/back navigation invalidates this deferred generation before it
	# can publish into a newer mode. Mesh construction itself is synchronous.
	if epoch < 0: epoch = _world_build_epoch
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	if epoch != _world_build_epoch or not world_build_busy or not is_map_preview(): return
	build_selected_world()
	if epoch == _world_build_epoch: world_build_busy=false

func cancel_world_build() -> void:
	_world_build_epoch += 1
	world_build_busy=false
	world_dialog.hide()
	restart_confirm_dialog.hide()

func prepare_world_candidate(generated: Variant = null) -> Dictionary:
	# Generation and validation never touch the live state, pending die or UI.
	if generated!=null and (not generated is Dictionary or generated.is_empty()):
		return {"ok":false,"errors":["Generated world must be a nonempty object."]}
	var fresh=Game.new()
	var candidate:Dictionary=fresh.state.duplicate(true)
	if generated!=null:
		if not generated.get("hexes") is Dictionary or not generated.get("actor_spawn_hexes") is Dictionary or not generated.has("board_radius"):
			return {"ok":false,"errors":["Generated world is missing cells, radius or actor spawns."]}
		candidate.hexes=generated.hexes.duplicate(true)
		candidate.board_radius=generated.board_radius
		candidate["generated_world"]=generated.duplicate(true)
		for id in candidate.actors:
			if not generated.actor_spawn_hexes.has(id) or not generated.actor_spawn_hexes[id] is Array:
				return {"ok":false,"errors":["Generated world is missing a valid actor spawn: "+str(id)]}
			candidate.actors[id].hex=generated.actor_spawn_hexes[id].duplicate()
	var errors:Array=fresh._validate_state(candidate)
	return {"ok":errors.is_empty(),"errors":errors,"candidate":candidate}

func commit_world_candidate(candidate: Dictionary) -> Dictionary:
	if not is_map_preview():
		return {"ok":false,"code":"PREVIEW_ONLY","errors":["地图候选只能替换只读预览，不能替换当前冒险。"]}
	var errors:Array=game._validate_state(candidate)
	if not errors.is_empty():
		set_status("生成失败 · 原世界与待处理行动保留："+str(errors))
		return {"ok":false,"errors":errors}
	game.state=candidate.duplicate(true)
	reset_world_controls()
	refresh_world()
	board.focus_player()
	return {"ok":true}

func build_selected_world() -> void:
	if not is_map_preview(): return
	var generated:Variant=null
	var generation_metadata:Dictionary={}
	var generation_notice:=""
	if world_build_requested:
		var requested_seed:Variant=world_build_seed_token if not world_build_seed_token.is_empty() else world_build_seed
		var result:=SeededWorld.generate(requested_seed,"coast_exploration",world_build_radius)
		if not result.ok:
			var failure_notice:="该种子的3个确定性候选均未通过预设校验" if result.get("code","")=="SEED_ATTEMPTS_EXHAUSTED" else "种子或尺寸无效"
			set_status("地图候选未通过校验 · 原世界与待处理行动保留；"+failure_notice)
			return
		generated=result.source
		generation_metadata=result.metadata
		generation_notice=result.notice
	var prepared:Dictionary=prepare_world_candidate(generated)
	if not prepared.ok:
		set_status("生成失败 · 原世界与待处理行动保留："+str(prepared.errors))
		return
	if not commit_world_candidate(prepared.candidate).ok:return
	last_world_generation_metadata=generation_metadata.duplicate(true)
	if not world_build_requested:
		board.reset_camera()
		append_journal("旧版地图预览（只读）", "原始61格仅供查看，不会执行旧版裁定或记录回放。")
		set_status(MAP_PREVIEW_NOTICE)
		return
	var display_seed:String=generation_metadata.request.seed_token.replace("[","［").replace("]","］")
	append_journal("多地貌地图预览（只读）", "输入种子 %s · 实际种子 %d · %d格。%s。预设源结构已校验；预览不代表全部视觉品质或通行已验收。可查看地形、河网、聚落、道路与桥梁；返回海岸可继续原来的固定地图冒险。"%[display_seed,generated.seed,generated.hexes.size(),generation_notice])
	set_status(MAP_PREVIEW_NOTICE+" · 实际种子 %d · %d 格 · %s"%[generated.seed,generated.hexes.size(),generation_notice])

func clear_target() -> void:
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	if is_instance_valid(private_main_visual):private_main_visual.after_world_change.call_deferred()
	selected_focus.clear();resolved_focus.clear();focus_choices.clear()
	if is_instance_valid(focus_details_dialog): focus_details_dialog.hide()
	if is_instance_valid(focus_choice_popup):focus_choice_popup.hide()
	if is_instance_valid(focus_choice_button):focus_choice_button.visible=false
	selected = Vector2i(99, 99)
	board.selected_hex = selected
	board.hover_hex = selected
	board.clear_actor_selection()
	board.draw_overlay()
	target_label.text = "未选中目标"
	target_label.tooltip_text=target_label.text
	clear_target_button.disabled = true
	clear_target_button.hide(); target_row.hide()
	update_movement_preview()

func update_turn_controls() -> void:
	if not is_instance_valid(next_step_label): return
	if playtest_mode:
		update_playtest_controls()
		return
	_update_map_preview_controls()

func set_status(text: String) -> void:
	status_label.text=text
	status_label.tooltip_text=text
	update_turn_controls()
	if coast_mode and OS.has_environment("FOGBANK_QA_CAPTURE") and DisplayServer.get_name() != "headless":
		screenshot_serial += 1
		capture_board("playable_build_20261002/native_%03d.png" % screenshot_serial)
func append_journal(speaker: String, text: String, update_latest: bool = true) -> void:
	if speaker.begins_with("你"): text=DisplayText.player_intent(text)
	var paragraph_gap := "\n\n" if not journal.get_parsed_text().is_empty() else ""
	journal.append_text(paragraph_gap+"[color=#77543c][b]"+speaker+"[/b][/color]\n"+text.replace("[","［").replace("]","］")+"")
	if not update_latest: return
	if speaker.contains("夹具") or speaker.contains("评估"): return
	dialogue_speaker.text = speaker
	latest_dialogue.text = text
	latest_dialogue.tooltip_text = text

func refresh_world(animate_changes: bool = false) -> void:
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	if is_instance_valid(private_main_visual):private_main_visual.after_world_change.call_deferred()
	if has_node("SelectionMotion"): get_node("SelectionMotion").cancel()
	if playtest_mode:
		refresh_playtest_world(animate_changes)
		return
	board.set_world(game.state,animate_changes)
	TerrainMaterials.set_software_preview(software_preview)
	var actor:Dictionary=game.state.actors.actor_player
	map_title.text="多地貌地图预览（只读）" if game.state.has("generated_world") else "旧版地图预览（只读）"
	map_stats_label.text="%d 格 / 只读 / 尚未接入当前行动规则"%game.state.hexes.size()
	hero_subtitle.text="地图查看 · 不执行行动"
	update_character_status(actor,int(game.state.state_version),game.state)
	turn_counter.text="只读预览 · 尚未接入当前行动规则"
	hero_label.tooltip_text = hero_label.text + " · " + hero_subtitle.text
	for child in inventory_box.get_children(): child.queue_free()
	var statuses: Array[String]=PlayerDetails.status_lines(PlayerDetails.adapt_actor(game.state,actor))
	inventory_box.add_child(label("当前状态",18))
	if statuses.is_empty(): inventory_box.add_child(label("没有持续状态",15,MUTED))
	for line in statuses:
		var status_text=label(line,15,MUTED); status_text.custom_minimum_size.x=420; status_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; inventory_box.add_child(status_text)
	inventory_box.add_child(label("随身物品",18))
	for id in actor.inventory:
		if not game.state.items.has(id): continue
		var item:Dictionary=game.state.items[id]
		var name_label=label("%s  ×%s" % [item.name,item.get("quantity",1)],18)
		inventory_box.add_child(name_label)
		var desc=label(String(item.description),15,MUTED);desc.custom_minimum_size.x=420;desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inventory_box.add_child(desc)

func _refresh_transient_focus()->void:
	if playtest_mode:
		if selected_focus.is_empty(): return
		var current: Dictionary = selected_focus.duplicate(true)
		var state: Dictionary = playtest.state_copy()
		if current.get("catalog_version")=="source-npc-focus/v1" and playtest.has_method("npc_reference"):current=playtest.npc_reference()
		elif current.get("catalog_version")=="source-vegetation-focus/v1" and playtest.has_method("vegetation_reference"):current=playtest.vegetation_reference(current.id)
		elif current.get("kind") == "actor" and state.actors.has(current.get("id", "")): current.hex = state.actors[current.id].hex.duplicate()
		elif current.get("catalog_version")==SceneEntities.VERSION: current=SceneEntities.make_reference(current.id,state,current.get("hex",[]))
		elif current.get("catalog_version")=="source-static-focus/v1" and playtest.source.has_method("static_reference"):
			current=playtest.source.static_reference(current.id,current.get("hex",[]))
			if current.is_empty():clear_target();return
		elif current.get("catalog_version") in ["generated-inventory-focus/v1","source-entity-focus/v1"] and playtest.has_method("item_reference"):
			current=playtest.item_reference(current.id)
			if current.is_empty():clear_target();return
		if not playtest.attention(current).ok: clear_target(); return
		_apply_focus(current)
		return
	if selected_focus.is_empty():return
	var current:Dictionary=selected_focus.duplicate(true)
	if current.get("kind")=="actor" and game.state.actors.has(current.get("id","")):current["hex"]=game.state.actors[current.id].hex.duplicate()
	var resolved:Dictionary=game.focus_contract.resolve(current,game._snapshot())
	if not resolved.ok:clear_target();return
	_apply_focus(current)

func on_focus_candidates(candidates:Array,point:Vector2)->void:
	# A new click supersedes a previous overlap chooser even when it resolves
	# immediately to one foreground subject. Never leave old target labels open.
	focus_choice_popup.hide()
	if candidates.is_empty():return
	focus_choices=candidates.duplicate(true);focus_popup_point=point
	_choose_focus(0)
	focus_choice_button.visible=focus_choices.size()>1
	# Close geometric overlaps get a small chooser; ordinary object clicks take
	# the front subject immediately, and alternatives remain one button away.
	if candidates.size()>1 and absf(float(candidates[0].distance)-float(candidates[1].distance))<0.15:show_focus_choices()

func show_focus_choices()->void:
	if focus_choices.is_empty():return
	focus_choice_popup.clear()
	for i in range(focus_choices.size()):focus_choice_popup.add_item(String(focus_choices[i].label),i)
	var local=board_container.global_position+focus_popup_point*Vector2(board_container.size)/Vector2(viewport.size)
	# Embedded subwindows use parent-window coordinates; native subwindows use
	# desktop coordinates. Adding the parent origin twice shifts the chooser.
	var position_=_attention_popup_position(local,get_window().position,focus_choice_popup.is_embedded())
	focus_choice_popup.popup(Rect2i(position_,Vector2i(0,0)))

static func _attention_popup_position(local:Vector2,parent_origin:Vector2i,embedded:bool)->Vector2i:
	return Vector2i(local)+(Vector2i.ZERO if embedded else parent_origin)

func _choose_focus(index:int)->void:
	if index<0 or index>=focus_choices.size():return
	_apply_focus(focus_choices[index].reference)

func _focus_caption(focus:Dictionary,prefix:String="关注")->String:
	if focus.get("catalog_version")=="source-npc-focus/v1":return prefix+"："+str(focus.facts.actor.name)+" · 村民"
	if focus.get("catalog_version")=="source-vegetation-focus/v1":return prefix+"："+V3NPCBoard.PLANT_NAMES.get(focus.facts.descriptor.asset_id,"植被")
	return PlayerDetails.caption(focus,prefix)

func show_focus_details() -> void:
	if resolved_focus.is_empty(): return
	focus_details_text.text=_focus_details_description()
	# Read-only text inset: preserve the current C paper style and give prose air.
	var detail_surface:StyleBox=focus_details_text.get_theme_stylebox("normal").duplicate()
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:detail_surface.set_content_margin(side,16)
	focus_details_text.add_theme_stylebox_override("normal",detail_surface)
	var expanded_item:bool=resolved_focus.get("catalog_version") in ["source-entity-focus/v1","source-static-focus/v1","source-npc-focus/v1","source-vegetation-focus/v1"]
	var extent:Vector2i=focus_details_extent(Vector2i(get_viewport_rect().size),expanded_item)
	focus_details_text.custom_minimum_size=Vector2(maxi(120,extent.x-60),maxi(120,extent.y-100)) if expanded_item else Vector2(480,230)
	focus_details_text.scroll_active=true
	focus_details_dialog.popup_centered(extent)
	focus_details_text.scroll_to_line(0)

static func focus_details_extent(viewport_size:Vector2i,expanded_item:bool) -> Vector2i:
	if not expanded_item:return Vector2i(mini(540,viewport_size.x-48),340)
	return Vector2i(mini(540,maxi(160,viewport_size.x-48)),mini(420,maxi(180,viewport_size.y-80)))

func _focus_details_description() -> String:
	if actor_action_mode:return PlayerDetails.description(resolved_focus)+("\n行动状态测试：只显示当前角色可见对象与公开状态，行动能力以请求目录为准。" if actor_status_mode else "\n统一行动测试：只显示当前角色可见对象，行动能力以请求目录为准。")
	if resolved_focus.get("catalog_version")=="source-npc-focus/v1":
		var f:Dictionary=resolved_focus.facts
		return "守路村民\n"+str(f.descriptor.description)+"\n位置：（%d，%d）\n已交谈：%d次\n话题：询问村落入口\n交谈需要同格或实际连通的相邻地格，耗费1点体力和1回合。\n点击只查看；自由意图需要有效评估。"%[resolved_focus.hex[0],resolved_focus.hex[1],f.public_state.conversation_count]
	if resolved_focus.get("catalog_version")=="source-vegetation-focus/v1":
		var d:Dictionary=resolved_focus.facts.descriptor
		return V3NPCBoard.PLANT_NAMES.get(d.asset_id,"植被")+"\n生态："+v3_biome_name(d.biome)+"\n根部地格：（%d，%d）\n可选择查看，或提交观察意图；尚无砍伐、采集和物品产出。\n点击不消耗回合。"%resolved_focus.hex
	if generated_v3_equipment_mode and resolved_focus.get("kind")=="actor":
		var current:Dictionary=playtest.state_copy()
		if resolved_focus.id==playtest.source.enemy_id:
			return PlayerDetails.description(resolved_focus)+("\n短刃仍由他持有；倒下后可从干地连通邻格经评估取走。" if current.items.item_raider_blade.owner_actor_id==playtest.source.enemy_id else "\n短刃已由旅人取走；倒下人物仍占据原格。")
		if resolved_focus.id=="actor_player":return PlayerDetails.description(resolved_focus)+"\n当前装备："+str(current.items[current.actors.actor_player.equipment.weapon].name)+"。可在行囊查看登记能力，换装需单独评估。"
	if generated_v3_npc_mode and resolved_focus.get("kind")=="tile":return PlayerDetails.description(resolved_focus)+"\n房屋会阻挡通路，请以移动预览为准。可沿路靠近守路村民，再提出交谈。"
	if generated_v3_village_mode and resolved_focus.get("kind")=="tile":
		return PlayerDetails.description(resolved_focus)+"\n村落房屋会阻挡部分通路；实际可走路线以移动预览为准。道路不减体力消耗，暂无人物、进屋与河流互动。"
	if generated_v3_mode and resolved_focus.get("kind")=="tile":
		var facts:Dictionary=resolved_focus.get("facts",{})
		return PlayerDetails.description(resolved_focus)+"\n生态：%s\n源高度：%.3f · 温度：%.3f · 湿度：%.3f\n这张地图可移动、观察和休息；水系数据仅供描述，暂无河流或城镇互动。"%[v3_biome_name(str(facts.get("biome",""))),float(facts.get("elevation",0)),float(facts.get("temperature",0)),float(facts.get("moisture",0))]
	if generated_mode and resolved_focus.get("kind")=="tile":
		var facts: Dictionary=resolved_focus.get("facts",{})
		return PlayerDetails.description(resolved_focus)+"\n生态：%s · 地貌：%s\n源高度：%.3f · 温度：%.3f · 湿度：%.3f\n高原区域：%s\n道路、桥梁和树木尚无额外行动能力"%[str(facts.get("biome","")),str(facts.get("landform","")),float(facts.get("elevation_q4096",0))/4096.0,float(facts.get("temperature_q4096",0))/4096.0,float(facts.get("moisture_q4096",0))/4096.0,str(facts.get("plateau_region",""))]
	if not is_map_preview():
		var text_:String=PlayerDetails.description(resolved_focus)
		return text_.replace("暂无人物、进屋、交易、城门或拆建能力。","可向守路村民询问登记话题；暂无进屋、交易、城门或拆建能力。") if generated_v3_npc_mode else text_
	var hex: Array=resolved_focus.get("hex",[])
	if hex.size()!=2: return MAP_PREVIEW_NOTICE
	var point:=Vector2i(hex[0],hex[1])
	var cell: Dictionary=game.state.hexes.get(board.tile_key(point),{})
	var lines: Array[String]=[_focus_caption(resolved_focus,"只读目标"),"地貌："+terrain_description(point,str(cell.get("terrain","")))]
	if cell.has("elevation"): lines.append("地形高度：%.3f（生成器归一值）"%float(cell.elevation))
	if cell.has("temperature"): lines.append("温度：%.3f · 湿度：%.3f（生成器归一值）"%[float(cell.temperature),float(cell.get("moisture",0))])
	if cell.get("landform","")=="plateau": lines.append("高原区域："+str(cell.get("plateau_region","")))
	lines.append(MAP_PREVIEW_NOTICE)
	return "\n".join(lines)

func update_movement_preview() -> void:
	if not is_instance_valid(route_preview_label): return
	if not (coast_mode or generated_mode) or playtest == null:
		route_preview_label.hide(); movement_preview.clear(); _route_preview_key=""; return
	var state: Dictionary=playtest.state_copy()
	var key_: String = str(state.get("state_version",0))+"|"+playtest.phase()+"|"+str(selected_focus)+"|"+playtest.active_action
	if key_==_route_preview_key: return
	_route_preview_key=key_
	movement_preview=playtest.frozen_movement_preview()
	var frozen := not movement_preview.is_empty()
	if not frozen and selected_focus.get("kind")=="tile": movement_preview=playtest.movement_preview(selected_focus.hex)
	var route: Array=movement_preview.get("route",[]) if movement_preview.get("ok",false) else []
	if board.has_method("set_route_preview"): board.set_route_preview(route)
	route_preview_label.visible=not movement_preview.is_empty()
	if not route_preview_label.visible: return
	var flying: bool=playtest.movement_is_flight(str(movement_preview.get("actor_id",""))) if actor_status_mode else preload("res://core/ai_gm_rebuilt/traversal.gd").flight(state.actors.actor_player,state)
	if movement_preview.get("ok",false):
		route_preview_label.text="%s：%d格 · %d体力 · 整段1回合%s" % ["本回合路线" if frozen else ("飞行参考" if flying else "步行参考"),maxi(0,route.size()-1),int(movement_preview.cost),"（成功后扣除）" if frozen else "（尚未行动）"]
		route_preview_label.tooltip_text="体力消耗以当前路线的实际地面代价为准；整段只推进1回合，巡逻和持续状态只结算一次。路线显示不等于行动，仍须写下意图并取得有效裁定。"
	elif selected_focus.get("kind")=="tile" and selected_focus.get("hex",[])==state.actors.actor_player.hex and selected_focus.get("scene_id",state.actors.actor_player.scene_id)==state.actors.actor_player.scene_id:
		route_preview_label.text="当前位置：你已在选中的落脚处"
		route_preview_label.tooltip_text="当前无需移动；可选其它目的地，或写下其它行动等待裁定。"
	else:
		var errors: Array=movement_preview.get("errors",[])
		route_preview_label.text=("飞行参考：" if flying else "步行参考：")+(str(errors[0]) if not errors.is_empty() else "当前无法到达；可提出其它行动等待评估")
		route_preview_label.tooltip_text=route_preview_label.text

func _apply_focus(reference:Dictionary)->void:
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	if is_instance_valid(private_main_visual):private_main_visual.after_world_change.call_deferred()
	if playtest_mode:
		var resolved_new: Dictionary = playtest.attention(reference)
		if not resolved_new.ok: set_status("关注失效：" + str(resolved_new)); return
		resolved_focus=resolved_new.focus.duplicate(true)
		selected_focus = playtest.focus_contract.reference_for(resolved_new.focus)
		selected = Vector2i(resolved_new.focus.hex[0], resolved_new.focus.hex[1])
		board.select_attention(selected_focus)
		clear_target_button.disabled = false; clear_target_button.show(); target_row.show()
		target_label.text = _focus_caption(resolved_new.focus, "下一次关注" if playtest.phase()!="idle" else "关注")
		target_label.tooltip_text = _focus_details_description()+( "\n当前行动的目标已经确定；新点击只改变下一次目标。" if playtest.phase()!="idle" else "")
		if focus_details_dialog.visible: focus_details_text.text=_focus_details_description()
		update_movement_preview()
		return
	var resolved:Dictionary=game.focus_contract.resolve(reference,game._snapshot())
	if not resolved.ok:set_status("关注已失效，请重新点击场景："+str(resolved.errors));return
	resolved_focus=resolved.focus.duplicate(true)
	selected_focus=game.focus_contract.reference_for(resolved.focus)
	selected=Vector2i(resolved.focus.hex[0],resolved.focus.hex[1])
	board.select_attention(selected_focus)
	clear_target_button.disabled=false;clear_target_button.show();target_row.show()
	target_label.text=_focus_caption(resolved.focus,"只读目标")+" · "+terrain_description(selected,str(game.state.hexes.get(board.tile_key(selected),{}).get("terrain","")))
	target_label.tooltip_text=_focus_details_description()

	if focus_details_dialog.visible: focus_details_text.text=_focus_details_description()

func on_hex_selected(hex: Vector2i) -> void:
	if playtest_mode:
		var state: Dictionary = playtest.state_copy()
		var scene_id: String=state.actors.actor_player.scene_id
		var cells: Dictionary=SceneCells.cells(state,scene_id) if coast_mode else state.hexes
		if not cells.has(board.tile_key(hex)): return
		focus_choices.clear(); focus_choice_button.visible = false
		var reference: Dictionary={"world_id": state.world_id, "kind": "tile", "id": cells[board.tile_key(hex)].id, "hex": [hex.x, hex.y]}
		if coast_mode and scene_id!="scene_coast":reference.scene_id=scene_id
		_apply_focus(reference)
		return
	# Kept for explicit demo/test callers; UI clicks use true object candidates.
	if not game.state.hexes.has(board.tile_key(hex)):return
	focus_choices.clear();focus_choice_button.visible=false
	_apply_focus({"world_id":game.state.world_id,"kind":"tile","id":game.state.hexes[board.tile_key(hex)].id,"hex":[hex.x,hex.y]})

func terrain_name(name: String) -> String:
	return {"plain":"草原","plains":"草原","swamp":"沼泽","river":"河流","bridge":"木桥","wall":"古墙","mountain":"山地","ocean":"海洋","forest":"林地","hill":"丘陵"}.get(name,name)

func terrain_description(hex: Vector2i, fallback: String) -> String:
	if generated_v3_mode and playtest!=null:
		return v3_biome_name(str(playtest.state_copy().get("hexes",{}).get(board.tile_key(hex),{}).get("biome",fallback)))
	var metadata=game.state.get("generated_world",{})
	if not metadata is Dictionary or metadata.get("generator_version","")!=Generator.BIOMES_VERSION:return terrain_name(fallback)
	var cell:Dictionary=game.state.hexes.get(board.tile_key(hex),{})
	var biome=String(cell.get("biome",""))
	var biome_name=String({"desert":"沙漠","grassland":"草原","jungle":"丛林","ocean":"海洋","temperate_forest":"林地","alpine":"高山","wetland":"湿地"}.get(biome,terrain_name(fallback)))
	var landform=String(cell.get("landform",""))
	var landform_name=String({"plateau":"高原","slope":"高原坡地","ridge":"山脊"}.get(landform,""))
	if fallback in ["bridge","river","wall"]:return terrain_name(fallback)+" · "+biome_name
	return biome_name+(" · "+landform_name if not landform_name.is_empty() else "")

func on_hex_hovered(hex: Vector2i, terrain: String, estimate: float) -> void:
	if is_map_preview():
		if selected_focus.is_empty(): target_label.text="只读地貌 (%d, %d) · %s" % [hex.x,hex.y,terrain_description(hex,terrain)]
		return
	if coast_mode:
		if selected_focus.is_empty(): target_label.text = "地面 · 点击只选择目标"
		return
	if selected_focus.is_empty(): target_label.text="悬停 (%d, %d) · %s · 点击关注；行动仍需文字" % [hex.x,hex.y,terrain_description(hex,terrain)]

func submit_action(legacy_replay:bool=false) -> void:
	if _block_preview_action(): return
	if playtest_mode: submit_playtest(); return
	if world_build_busy:return
	if not active_action.is_empty():
		set_status("当前行动尚未完成；先导入裁定，避免丢失上下文")
		return
	if goal.text.strip_edges().is_empty():
		set_status("已关注对象。请写下你想做什么；点击本身不会开始行动。" if not selected_focus.is_empty() else "请先写下你想做什么")
		return
	# Only the explicit recorded demo uses the unchanged old transport shape.
	var result:Dictionary=game.request(goal.text.strip_edges(),selected) if legacy_replay else game.request_intent(goal.text,selected_focus)
	if not result.get("ok",false): set_status(str(result));return
	current_request=result.request;active_action=String(current_request.action_id)
	die_label.text="D20  /  —";roll_button.disabled=true;roll_button.text="掷 D20 · 等待 GM 要求"
	wait_started=Time.get_ticks_msec();timeout_shown=false;cancel_button.disabled=false
	append_journal("你 · 意图",goal.text)
	phase_label.text="① 意图评估 · 等待 GM"
	submit_button.disabled=true
	set_status("请求已生成 · action_id: "+active_action+" · 导出 JSON 交给模型，再导入 planning 裁定")
	auto_export()

func auto_export() -> void:
	if _block_preview_action(): return
	if playtest_mode:
		if not playtest.request().is_empty(): playtest.export_request(playtest.default_request_path() if generated_v3_mode else ("user://generated_adventure_request_v1.json" if generated_mode else (Coast.COAST_REQUEST if coast_mode else Playtest.REQUEST_PATH)))
		return
	if current_request.is_empty(): return
	provider.export_request(current_request,"user://current_request.json")

func export_request() -> void:
	if _block_preview_action(): return
	if actor_action_mode:current_request=playtest.request()
	if current_request.is_empty(): set_status("还没有待处理请求，先提交意图");return
	_export_epoch = _mode_epoch
	actor_export_hash=ActorEntryView.C.digest(current_request) if actor_action_mode else ""
	file_dialog.current_file=playtest.default_request_path().get_file() if actor_action_mode else "turn_request_%s.json" % current_request.phase
	advanced_dialog.hide()
	file_dialog.popup_centered_ratio(0.7)

func on_file_selected(path: String) -> void:
	if _block_preview_action() or _export_epoch != _mode_epoch: return
	if actor_action_mode and ActorEntryView.C.digest(playtest.request())!=actor_export_hash:set_status("请求已取消或改变，请重新打开导出；没有导出其他回合。");return
	if playtest_mode:
		var exported: Dictionary = playtest.export_request(path)
		set_status("测试请求已导出：" + path if exported.ok else "导出失败：" + str(exported))
		return
	var result=provider.export_request(current_request,path)
	set_status("请求已导出："+path if result.get("ok",false) else "导出失败："+str(result))

func show_import() -> void:
	if _block_preview_action(): return
	_import_epoch = _mode_epoch
	if playtest_mode:
		if playtest.request().is_empty(): set_status("请先提交意图；暂存/提交后也可导入可选叙事JSON"); return
		import_error_label.text = ""
		advanced_dialog.hide()
		import_dialog.popup_centered()
		return
	if active_action.is_empty(): set_status("先提交一个意图，再导入对应裁定");return
	advanced_dialog.hide()
	import_dialog.popup_centered()

func import_decision() -> void:
	if _block_preview_action() or _import_epoch != _mode_epoch: return
	var parser=JSON.new()
	var error=parser.parse(import_text.text)
	if error!=OK or not parser.data is Dictionary:
		import_error_label.text="JSON 解析失败，状态没有改变："+parser.get_error_message()
		set_status(import_error_label.text)
		return
	if apply_decision(parser.data):
		import_error_label.text=""
		import_dialog.hide()
	else:
		import_error_label.text=status_label.text

func apply_decision(decision: Dictionary) -> bool:
	if _block_preview_action(): return false
	if playtest_mode: return apply_playtest_reply(decision)
	if decision.get("phase","")=="planning":
		var result:Dictionary=game.apply_planning(decision)
		if not result.get("ok",false): set_status("拒绝裁定："+str(result));return false
		append_journal("GM · 裁定预览（尚未执行）",String(decision.get("narration","")))
		if result.get("needs_roll",false):
			phase_label.text="② 掷骰 · GM 难度 %s" % decision.get("difficulty","?")
			roll_button.disabled=false;roll_button.text="掷 D20  ·  难度 %s" % decision.get("difficulty","?")
			set_status("GM 已要求检定。点击 D20，同一行动只能掷一次")
		else:
			current_request=result.request;auto_export()
			phase_label.text="③ 结果裁定 · 无需掷骰"
			set_status("本次无需掷骰。已生成 resolution 请求，等待最终裁定")
		return true
	elif decision.get("phase","")=="resolution":
		var result:Dictionary=game.commit_decision(decision)
		if not result.get("ok",false): set_status("拒绝裁定："+str(result));return false
		if result.get("already_committed",false): set_status("该行动已提交，忽略重复裁定");return true
		append_journal("GM · "+String(decision.get("outcome","结果")),String(decision.get("narration","")))
		active_action="";current_request={};cancel_button.disabled=true;roll_button.disabled=true;roll_button.text="掷 D20 · 等待 GM 要求";submit_button.disabled=false
		phase_label.text="回合已提交 · 继续自由行动"
		set_status("精确状态已更新 · v%s · 可继续行动或保存" % game.state.state_version)
		refresh_world(true)
		board.present_resolved_metadata(decision.get("presentation",{}))
		goal.text=""
		var frozen_reference:Dictionary=game.focus_contract.reference_for(result.event.get("attention_focus",{}))
		var chosen_next:bool=result.event.has("attention_focus") and JSON.stringify(selected_focus,"",true,true)!=JSON.stringify(frozen_reference,"",true,true)
		if not chosen_next:clear_target()
		else:_refresh_transient_focus()
		return true
	set_status("裁定 phase 必须是 planning 或 resolution");return false

func roll_dice() -> void:
	if _block_preview_action(): return
	if playtest_mode: advance_playtest(); return
	var result:Dictionary=game.roll_action(active_action,9 if demo_step>0 else -1)
	if not result.get("ok",false): set_status("不能掷骰："+str(result));return
	current_request=result.request
	var roll:Variant=current_request.get("roll",{})
	var value=result.get("roll",{}).get("value","?")
	die_label.text=("回放 D20  /  %s" if demo_step>0 else "D20  /  %s") % value
	roll_button.disabled=true
	phase_label.text="③ 结果裁定 · 已掷 %s" % value
	set_status("骰子已记录且不可重掷。导出 resolution 请求，等待模型决定最终结果")
	auto_export()
	if demo_step>0: finish_demo()

func save_game() -> void:
	if is_map_preview():
		last_save_result={"ok":false,"code":"READ_ONLY_PREVIEW"}
		set_status("只读预览不覆盖任何冒险存档；返回海岸后可保存原冒险。")
		return
	last_save_result={"ok":false,"code":"NOT_ATTEMPTED"}
	if playtest_mode:
		var saved: Dictionary = playtest.save_file()
		if saved.ok and (actor_action_mode or generated_v3_npc_mode):
			var prose:Dictionary=_runtime_adapter().save_sidecar(playtest.default_save_path())
			saved["narration_log_saved"]=prose.ok
			if not prose.ok:saved["narration_warning"]="核心进度已保存，可选叙事这次未能保存。"
		last_save_result=saved.duplicate(true)
		append_journal("冒险已保存" if saved.ok else "保存未完成", "当前进度已保存，可以稍后从菜单继续。" if saved.ok else "这次保存没有完成，当前游戏仍保留。连接与高级中可以查看原因。")
		set_status(("多地貌冒险" if generated_mode else ("海岸冒险" if coast_mode else "测试冒险"))+"已独立保存，含待处理阶段和一次结果" if saved.ok else "保存失败：" + str(saved))
		if saved.ok and not saved.get("narration_log_saved",true):
			append_journal("部分文字未保存","数值进度已保存，可选叙事这次未能保存。")
			set_status(str(saved.get("narration_warning","可选叙事未能保存，核心进度已保存。")))
		return
	var result=game.save_to_file("user://savegame.json")
	last_save_result=result.duplicate(true)
	append_journal("冒险已保存" if result.get("ok",false) else "保存未完成", "当前进度已保存，可以稍后从菜单继续。" if result.get("ok",false) else "这次保存没有完成，当前游戏仍保留。连接与高级中可以查看原因。")
	set_status("已保存精确状态与待处理回合" if result.get("ok",false) else "保存失败："+str(result))

func load_game() -> void:
	if is_map_preview():
		load_legacy_preview()
		return
	last_load_result={"ok":false,"code":"NOT_ATTEMPTED"}
	_invalidate_mode_dialogs()
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	if playtest_mode:
		if coast_mode and not coast_bundle_available(playtest): return
		var previous_renderer_source:RefCounted=board.admitted_source if generated_v3_mode else null
		var loaded: Dictionary = playtest.load_file()
		last_load_result=loaded.duplicate(true)
		if not loaded.ok:
			var reason:="存档未能读取，当前冒险保持不变。"
			if loaded.get("code","") in ["BUNDLE_MISMATCH","WORLD_MISMATCH","LOAD_FAILED"] and not loaded.get("errors",[]).is_empty(): reason=String(loaded.errors[0])
			append_journal("读取未完成",reason)
			set_status("读取失败，当前状态保留："+str(loaded)); return
		if actor_action_mode or generated_v3_npc_mode:
			var prose:Dictionary=_runtime_adapter().load_sidecar(playtest.default_save_path())
			loaded["narration_log_status"]=prose.status;loaded["narration_warning"]=prose.get("warning","")
			last_load_result=loaded.duplicate(true)
		if generated_v3_mode:
			V3RenderResidency.reuse(previous_renderer_source,playtest.source)
			board.admitted_source=playtest.source
			if previous_renderer_source!=playtest.source:V3RenderResidency.suspend(previous_renderer_source)
		if is_instance_valid(runtime_ai): runtime_ai.bind_adapter(_runtime_adapter())
		if actor_action_mode:actor_action_panel.reset_consent()
		end_turn_requested = playtest.phase() != "idle"
		clear_target()
		if not actor_action_mode or playtest.action_copy().get("actor_id","actor_player")=="actor_player":set_player_intent(String(playtest.action_copy().get("goal", "")),coast_mode)
		sync_playtest_request(); refresh_world(); board.focus_player()
		journal.clear()
		if (coast_mode or generated_mode) and playtest.has_method("journal_entries"):
			for entry in playtest.journal_entries():
				append_journal(String(entry.get("title","冒险记录")),String(entry.get("text","")))
		if actor_action_mode or generated_v3_npc_mode:
			for entry in _runtime_adapter().narration_entries():append_journal("叙事记录 · 第%d回合"%int(entry.turn),str(entry.narration))
		if actor_action_mode and playtest.phase()!="idle":append_journal("敌方 · 待完成的行动" if playtest.action_copy().get("actor_id")!="actor_player" else "你 · 待完成的行动",str(playtest.action_copy().goal))
		elif playtest.phase()!="idle" and not goal.text.is_empty(): append_journal("敌方 · 待完成的行动" if playtest.action_copy().get("actor_id","actor_player")!="actor_player" else "你 · 待完成的行动",goal.text)
		append_journal("冒险继续", "已恢复保存的冒险。未完成的回合可以继续，已锁定的结果保持不变。")
		if not str(loaded.get("narration_warning","")).is_empty():append_journal("部分文字未恢复",str(loaded.narration_warning))
		if not actor_action_mode or actor_render_error.is_empty():set_status("存档已读取 · 已锁定的结果保持不变")
		if _waiting_enemy_phase(): _queue_required_enemy_turn()
		return

func load_legacy_preview(path: String = "user://savegame.json") -> void:
	if not is_map_preview() or world_build_busy: return
	var inspected=Game.new()
	var loaded:Dictionary=inspected.load_from_file(path)
	last_load_result=loaded.duplicate(true)
	if not loaded.get("ok",false):
		set_status("旧版存档读取失败，当前预览与原文件保留："+str(loaded))
		return
	# Inspect the exact loaded snapshot, including pending records. No resume,
	# request export, cancellation, roll or save-back is allowed in this mode.
	game=inspected
	_invalidate_mode_dialogs()
	reset_world_controls()
	refresh_world(); board.focus_player()
	for entry in game.state.get("recent_dialogue",[]):
		append_journal("旧版记录（只读）",String(entry.get("content","")))
	append_journal("旧版存档预览（只读）", "原文件未修改；%d个待处理行动仅保留查看，不会恢复或执行。返回海岸可继续当前冒险。"%game.state.get("pending_actions",{}).size())
	last_load_result["read_only"]=true
	last_load_result["pending_resumed"]=false
	set_status(MAP_PREVIEW_NOTICE+" · 旧版存档只读载入，原文件保留")

func reset_world_controls() -> void:
	_invalidate_mode_dialogs()
	invalidate_sample_draft()
	resolved_focus.clear(); movement_preview.clear(); _route_preview_key=""
	if is_instance_valid(focus_details_dialog): focus_details_dialog.hide()
	if is_instance_valid(effects_dialog): effects_dialog.hide()
	if is_instance_valid(route_preview_label): route_preview_label.hide()
	end_turn_requested=false;end_turn_busy=false
	set_map_dialogue_hidden(false)
	active_action="";current_request={};cancel_button.disabled=true;selected_focus.clear();focus_choices.clear();focus_choice_button.visible=false;focus_choice_popup.hide();selected=Vector2i(99,99);board.selected_hex=selected;board.hover_hex=selected;board.clear_actor_selection();demo_step=0;demo_button.text="体验已记录的 AI 回合";roll_button.disabled=true;submit_button.disabled=false;die_label.text="D20  /  —";phase_label.text="等待你的意图";goal.text="";journal.clear();target_label.text="未选中目标";clear_target_button.disabled=true

func restart_game() -> void:
	if _block_preview_action(): return
	var prepared:Dictionary=prepare_world_candidate()
	if not prepared.ok or not commit_world_candidate(prepared.candidate).ok:return
	append_journal("GM · 场景", "晨雾归来，河岸重置。你重新站在古墙外。")
	set_status("新世界已建立")

func start_demo() -> void:
	if _block_preview_action(): return
	if playtest_mode:
		set_status("已记录AI回合只适用于原v9；当前请使用明确署名的测试夹具按钮")
		return
	if world_build_busy:return
	if game.state.has("generated_world"):
		set_status("已记录回合只适用于原始雾河遗迹；请从世界选择中返回原始 61 格")
		return
	if demo_step==2:
		finish_demo();return
	if not active_action.is_empty():
		set_status("先完成或取消当前回合，再开始回放")
		return
	if int(game.state.state_version)>0:
		set_status("记录回放会重置世界。请确认，或取消并先保存当前进度")
		demo_confirm_dialog.popup_centered()
		return
	_begin_demo()

func _begin_demo() -> void:
	if _block_preview_action(): return
	if game.state.has("generated_world"):
		set_status("已记录回合只适用于原始雾河遗迹")
		return
	restart_game()
	goal.text="喝下雾行药剂，穿过浅水走到那里，再试着说服守卫放下武器。"
	selected=Vector2i(1,-1);board.selected_hex=selected;on_hex_selected(selected);board.draw_overlay()
	submit_action(true)
	var result:Dictionary=provider.recorded_example_for(current_request,"res://relay/compound_planning.json")
	if not result.get("ok",false): set_status("回放暂不可用："+str(result));return
	demo_step=1
	append_journal("系统 · 已记录的模型中继", "以下裁定来自实际 gpt-6-luna LOW 助手中继测试。此回放使用已记录的 D20=9，不是实时 API 或新的随机掷骰。")
	if apply_decision(result.decision):
		capture_board("relay_planning.png")
		roll_button.text="回放 D20 = 9 · 已记录测试"
		set_status("示例回放 · 规划只是预览，尚未执行。点击回放已记录的 D20=9")

func finish_demo() -> void:
	if _block_preview_action(): return
	var result:Dictionary=provider.recorded_example_for(current_request,"res://relay/compound_resolution_d20_9.json")
	if not result.get("ok",false): set_status("记录与当前请求不匹配："+str(result));return
	if apply_decision(result.decision):
		demo_step=0;demo_button.text="体验已记录的 AI 回合"
		set_status("实际模型中继回放已提交：涉水成功，说服失败。药剂数量与位置由模型裁定更新，可自由继续")
		capture_board("relay_outcome.png")

func capture_board(filename: String) -> void:
	if DisplayServer.get_name()=="headless" or not DirAccess.dir_exists_absolute("res://artifacts"): return
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("res://artifacts/"+filename)


func cancel_pending() -> void:
	if _block_preview_action(): return
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	if playtest_mode:
		var cancelled: Dictionary = playtest.cancel()
		if not cancelled.ok: set_status("取消被拒绝：" + str(cancelled)); return
		end_turn_requested = false
		sync_playtest_request(); set_status("掷前请求已取消；事实、骰子序列和历史尝试保留")
		return
	if active_action.is_empty(): return
	var result:Dictionary=game.cancel_action(active_action)
	if not result.get("ok",false): set_status("取消失败："+str(result));return
	active_action="";current_request={};demo_step=0;roll_button.disabled=true;submit_button.disabled=false;cancel_button.disabled=true
	die_label.text="D20  /  —";roll_button.text="掷 D20 · 等待 GM 要求";demo_button.text="体验已记录的 AI 回合"
	phase_label.text="等待已取消 · 数值状态未改变"
	set_status("请求已取消。迟到的旧 action_id 裁定会被拒绝，可重新描述意图")

func _process(_delta: float) -> void:
	if is_map_preview():
		_update_map_preview_controls()
		return
	# Large real-world snapshots are read on UI events, never cloned every frame.
	if coast_mode or generated_mode: return
	if playtest_mode:
		update_turn_controls()
		return
	if not perf_logged and Time.get_ticks_msec()>15000 and DisplayServer.get_name()!="headless":
		perf_logged=true
		print("ACTUAL RENDER FPS ",Performance.get_monitor(Performance.TIME_FPS)," objects=",Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	update_turn_controls()
	if not active_action.is_empty() and not timeout_shown and wait_started>0 and Time.get_ticks_msec()-wait_started>60000:
		timeout_shown=true
		set_status("已等待约一分钟。离线中继不会自动收到响应；可导出/导入裁定、保存稍后继续，或取消等待")


# The legacy protocol is retained for core regression only. Release UI treats
# every legacy snapshot (generated or loaded) as an isolated read-only preview.
func is_map_preview() -> bool:
	return not playtest_mode

func _block_preview_action() -> bool:
	if not is_map_preview(): return false
	set_status(MAP_PREVIEW_NOTICE+"；请返回海岸冒险再行动。")
	return true

func _update_map_preview_controls() -> void:
	if not is_instance_valid(goal): return
	goal.editable=false
	action_base.hide()
	submit_button.disabled=true; submit_button.hide()
	cancel_button.disabled=true; cancel_button.hide()
	roll_button.disabled=true; roll_button.hide()
	export_button.disabled=true; import_button.disabled=true; relay_row.hide()
	demo_button.disabled=true; demo_button.hide(); die_label.hide()
	turn_footer.show()
	phase_label.text="只读预览 · 尚未接入当前行动规则"
	next_step_label.text="移动镜头或查看地貌；菜单可返回海岸冒险"
	clear_target_button.disabled=selected_focus.is_empty()
	clear_target_button.visible=not selected_focus.is_empty()
	target_row.visible=not selected_focus.is_empty()
	mode_legend.text=MAP_PREVIEW_NOTICE
	relay_note.text=MAP_PREVIEW_NOTICE+"。\n旧版裁定和待处理行动仅供查看；原存档不会被覆盖。"
	runtime_connection_panel.hide()
	if is_instance_valid(advanced_menu): advanced_menu.set_item_disabled(advanced_menu.get_item_index(5),true)
	if is_instance_valid(adventure_menu):
		adventure_menu.set_item_disabled(adventure_menu.get_item_index(1),true)
		adventure_menu.set_item_disabled(adventure_menu.get_item_index(13),false)
		adventure_menu.set_item_text(adventure_menu.get_item_index(1),"只读预览不能覆盖存档")
		adventure_menu.set_item_text(adventure_menu.get_item_index(2),"查看旧版存档（只读）")
		adventure_menu.set_item_text(adventure_menu.get_item_index(3),"选择多地貌预览")

func _can_leave_current_adventure() -> bool:
	if (actor_action_mode and playtest!=null and playtest.decision_pending()) or end_turn_busy or not active_action.is_empty() or (playtest_mode and playtest != null and playtest.phase() != "idle"):
		set_status("当前行动尚未完成；请先完成回合，或在结果锁定前取消，再查看地图预览。")
		return false
	return true

func show_map_preview_selector() -> void:
	if world_build_busy or not _can_leave_current_adventure(): return
	world_dialog.popup_centered()

func return_from_map_preview() -> void:
	world_dialog.hide()
	if is_map_preview() or generated_mode: _switch_mode("coast")

func _invalidate_mode_dialogs() -> void:
	if is_instance_valid(runtime_connection_panel): runtime_connection_panel.close_settings()
	_mode_epoch += 1
	_import_epoch=-1; _import_file_epoch=-1; _export_epoch=-1
	for dialog in [import_dialog,import_file_dialog,file_dialog,demo_confirm_dialog,restart_confirm_dialog,world_dialog,playtest_reset_dialog,scene_test_confirm_dialog,v3_setup_dialog,npc_notes_dialog]:
		if is_instance_valid(dialog): dialog.hide()
	if is_instance_valid(import_text): import_text.text=""
	if is_instance_valid(import_error_label): import_error_label.text=""

func _on_import_file_selected(path: String) -> void:
	if is_map_preview() or _import_file_epoch != _mode_epoch or _import_epoch != _mode_epoch: return
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null: set_status("无法读取裁定文件"); return
	import_text.text=file.get_as_text()
	import_file_dialog.hide()
	import_dialog.popup_centered()
	set_status("裁定文件已载入预览，点击校验并应用后才会提交")

func _on_import_file_canceled() -> void:
	if is_map_preview() or _import_file_epoch != _mode_epoch or _import_epoch != _mode_epoch: return
	import_file_dialog.hide()
	import_dialog.popup_centered()

func _capture_mode_ui() -> Dictionary:
	var source_coast: bool=coast_mode and board.get_meta("renderer_id","")=="source_coast/v1"
	var camera_owner: Node=board.world_view if source_coast else board
	var camera_fields: Array=["target","distance","pitch","yaw","overview","scope_name"] if source_coast else ["view_focus","camera_distance","orbit_pitch","view_angle","overview_mode","overview_zoom_factor","overview_fit_size","overview_close_angle"]
	var view_state: Dictionary={}
	for field in camera_fields: view_state[field]=camera_owner.get(field)
	return {"goal":goal.text,"signed_goal":_signed_sample_goal,"signed_display":_signed_sample_display,"journal":journal.text,"speaker":dialogue_speaker.text,"latest":latest_dialogue.text,"status":status_label.text,"focus":selected_focus.duplicate(true),"dialogue_hidden":dialogue_hidden_for_map,"view":view_state,"camera_transform":board.camera.transform,"camera_size":board.camera.size,"camera_projection":board.camera.projection}

func _restore_mode_ui(saved: Dictionary) -> void:
	goal.text=saved.goal
	_signed_sample_goal=saved.signed_goal; _signed_sample_display=saved.signed_display
	journal.text=saved.journal; dialogue_speaker.text=saved.speaker; latest_dialogue.text=saved.latest; latest_dialogue.tooltip_text=saved.latest
	if not saved.focus.is_empty(): _apply_focus(saved.focus)
	var source_coast: bool=coast_mode and board.get_meta("renderer_id","")=="source_coast/v1"
	var camera_owner: Node=board.world_view if source_coast else board
	for field in saved.view: camera_owner.set(field,saved.view[field])
	if source_coast: camera_owner._update_camera()
	else: board.orbit_camera(0,0)
	board.camera.transform=saved.camera_transform; board.camera.size=saved.camera_size; board.camera.projection=saved.camera_projection
	set_map_dialogue_hidden(saved.dialogue_hidden)
	set_status(saved.status)

func switch_playtest(enabled: bool) -> void:
	_switch_mode("laboratory" if enabled else "legacy")

func new_coast_adventure() -> RefCounted:
	# Explicit new-world opt-in; no UI control mutates a status directly.
	return Coast.new(null,false,"--status-gameplay" in OS.get_cmdline_user_args())

func switch_coast() -> void:
	_switch_mode("coast")

func _switch_mode(mode: String) -> void:
	_switch_mode_to(mode)

func _switch_mode_to(mode: String, replacement_v3:RefCounted=null) -> void:
	if mode not in ["coast","laboratory","legacy","generated","generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]: return
	if replacement_v3!=null and mode not in ["generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]:return
	if world_build_busy:
		if is_map_preview() and mode != "legacy": cancel_world_build()
		else: return
	var previous_v3_source:RefCounted=playtest.source if generated_v3_mode and playtest!=null else null
	var current := "actor_status_v1" if actor_status_mode else "actor_actions_v2" if actor_action_mode else "generated_v3_equipment" if generated_v3_equipment_mode else ("generated_v3_enemy" if generated_v3_enemy_mode else ("generated_v3_npc" if generated_v3_npc_mode else ("generated_v3_village" if generated_v3_village_mode else ("generated_v3_inventory" if generated_v3_inventory_mode else ("generated_v3" if generated_v3_mode else ("generated" if generated_mode else ("coast" if coast_mode else ("laboratory" if playtest_mode else "legacy"))))))))
	if mode == current and replacement_v3==null: return
	if not _can_leave_current_adventure(): return
	if mode=="generated" and (generated_adventure==null or not generated_adventure.ready().ok): return
	var next_v3:RefCounted=replacement_v3 if replacement_v3!=null else actor_status_adventure if mode=="actor_status_v1" else actor_action_adventure if mode=="actor_actions_v2" else (generated_v3_equipment_adventure if mode=="generated_v3_equipment" else (generated_v3_enemy_adventure if mode=="generated_v3_enemy" else (generated_v3_npc_adventure if mode=="generated_v3_npc" else (generated_v3_village_adventure if mode=="generated_v3_village" else (generated_v3_inventory_adventure if mode=="generated_v3_inventory" else generated_v3_adventure)))))
	if mode in ["generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"] and (next_v3==null or not next_v3.ready().ok):return
	if mode in ["generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]:
		V3RenderResidency.reuse(previous_v3_source,next_v3.source)
		var resident:Dictionary=V3RenderResidency.ensure(next_v3.source)
		if not resident.ok:show_world_load_error(str(resident));return
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	if mode == "coast":
		if not coast_bundle_available(coast_adventure): return
		if coast_adventure == null:
			var candidate:RefCounted=new_coast_adventure()
			if not candidate.engine.ready().ok:
				show_world_load_error(str(candidate.engine.ready())); return
			coast_adventure=candidate
	# Prepare the new renderer before removing the current valid scene. A missing
	# or corrupt bundle must never publish an empty world or clear current history.
	var next_board=StatusEntryBoard.new(next_v3.source) if mode=="actor_status_v1" else ActorEntryBoard.new(next_v3.source) if mode=="actor_actions_v2" else V3EquipmentBoard.new(next_v3.source) if mode=="generated_v3_equipment" else (V3EnemyBoard.new(next_v3.source) if mode=="generated_v3_enemy" else (V3NPCBoard.new(next_v3.source) if mode=="generated_v3_npc" else (V3VillageBoard.new(next_v3.source) if mode=="generated_v3_village" else (V3InventoryBoard.new(next_v3.source) if mode=="generated_v3_inventory" else (V3Board.new(next_v3.source) if mode=="generated_v3" else (GeneratedBoard.new(generated_adventure.source) if mode=="generated" else (_create_scene_board(coast_adventure.state_copy()) if mode=="coast" else Board.new())))))))
	if next_board==null: return
	next_board.attention_ui_mode=true
	viewport.add_child(next_board)
	if mode in ["actor_actions_v2","actor_status_v1"]:next_board.set_world(next_v3.state_copy())
	if mode in ["coast","generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"] and not next_board.load_error.is_empty():
		var render_error:String=next_board.load_error
		viewport.remove_child(next_board);next_board.free()
		show_world_load_error(render_error);return
	if playtest_mode:
		_mode_ui_snapshots[current]=_capture_mode_ui()
	_invalidate_mode_dialogs()
	reset_world_controls()
	if playtest_mode:
		if actor_status_mode: actor_status_adventure=playtest
		elif actor_action_mode: actor_action_adventure=playtest
		elif generated_v3_equipment_mode: generated_v3_equipment_adventure=playtest
		elif generated_v3_enemy_mode: generated_v3_enemy_adventure=playtest
		elif generated_v3_npc_mode: generated_v3_npc_adventure=playtest
		elif generated_v3_village_mode: generated_v3_village_adventure=playtest
		elif generated_v3_inventory_mode and not actor_action_mode: generated_v3_inventory_adventure=playtest
		elif generated_v3_mode and not actor_action_mode: generated_v3_adventure=playtest
		elif generated_mode: generated_adventure=playtest
		elif coast_mode: coast_adventure = playtest
		else: laboratory = playtest
	if replacement_v3!=null:
		if mode=="actor_status_v1":actor_status_adventure=replacement_v3
		elif mode=="actor_actions_v2":actor_action_adventure=replacement_v3
		elif mode=="generated_v3_equipment":generated_v3_equipment_adventure=replacement_v3
		elif mode=="generated_v3_enemy":generated_v3_enemy_adventure=replacement_v3
		elif mode=="generated_v3_npc":generated_v3_npc_adventure=replacement_v3
		elif mode=="generated_v3_village":generated_v3_village_adventure=replacement_v3
		elif mode=="generated_v3_inventory":generated_v3_inventory_adventure=replacement_v3
		else:generated_v3_adventure=replacement_v3
		_mode_ui_snapshots.erase(mode)
	actor_render_error="";actor_render_suspended=false;actor_status_mode=mode=="actor_status_v1";actor_action_mode=mode in ["actor_actions_v2","actor_status_v1"]; coast_mode = mode == "coast"; generated_v3_equipment_mode=mode=="generated_v3_equipment"; generated_v3_enemy_mode=mode in ["generated_v3_enemy","generated_v3_equipment"]; generated_v3_npc_mode=mode in ["generated_v3_npc","generated_v3_enemy","generated_v3_equipment"]; generated_v3_village_mode=mode in ["generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]; generated_v3_inventory_mode=mode in ["generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]; generated_v3_mode=mode in ["generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]; generated_mode=mode in ["generated","generated_v3","generated_v3_inventory","generated_v3_village","generated_v3_npc","generated_v3_enemy","generated_v3_equipment","actor_actions_v2","actor_status_v1"]; playtest_mode = mode != "legacy"
	mode_legend.text = "文字决定意图 · 点击只关注 · 离线评估，固定程序结算" if playtest_mode else MAP_PREVIEW_NOTICE
	action_base.visible=playtest_mode
	demo_button.disabled=not playtest_mode
	if actor_status_mode: playtest=actor_status_adventure
	elif actor_action_mode: playtest=actor_action_adventure
	elif generated_v3_equipment_mode: playtest=generated_v3_equipment_adventure
	elif generated_v3_enemy_mode: playtest=generated_v3_enemy_adventure
	elif generated_v3_npc_mode: playtest=generated_v3_npc_adventure
	elif generated_v3_village_mode: playtest=generated_v3_village_adventure
	elif generated_v3_inventory_mode and not actor_action_mode: playtest=generated_v3_inventory_adventure
	elif generated_v3_mode and not actor_action_mode: playtest=generated_v3_adventure
	elif generated_mode: playtest=generated_adventure
	elif coast_mode: playtest = coast_adventure
	elif playtest_mode:
		if laboratory == null: laboratory = Playtest.new()
		playtest = laboratory
	laboratory_panel.visible = mode == "laboratory"; coast_panel.visible = coast_mode; generated_panel.visible=generated_mode and not generated_v3_mode; generated_v3_panel.visible=generated_v3_mode and not generated_v3_inventory_mode; generated_v3_inventory_panel.visible=generated_v3_inventory_mode and not generated_v3_npc_mode and not actor_action_mode; generated_v3_npc_panel.visible=generated_v3_npc_mode and not generated_v3_enemy_mode; generated_v3_enemy_panel.visible=generated_v3_enemy_mode and not generated_v3_equipment_mode; generated_v3_equipment_panel.visible=generated_v3_equipment_mode
	actor_action_panel.visible=actor_action_mode
	runtime_connection_panel.visible=_runtime_supported()
	# Binding emits synchronous UI refreshes; publish the matching panel first.
	playtest_panel = actor_action_panel if actor_action_mode else generated_v3_equipment_panel if generated_v3_equipment_mode else (generated_v3_enemy_panel if generated_v3_enemy_mode else (generated_v3_npc_panel if generated_v3_npc_mode else (generated_v3_inventory_panel if generated_v3_inventory_mode else (generated_v3_panel if generated_v3_mode else (generated_panel if generated_mode else (coast_panel if coast_mode else laboratory_panel))))))
	runtime_ai.bind_adapter(_runtime_adapter())
	actor_action_panel.reset_consent()
	# Separate rendering parents prevent duplicate worlds, lights and input handlers.
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	viewport.remove_child(board); board.free()
	if previous_v3_source!=null and (not generated_v3_mode or previous_v3_source!=playtest.source):V3RenderResidency.suspend(previous_v3_source)
	board = next_board
	board.focus_candidates.connect(on_focus_candidates); board.hex_hovered.connect(on_hex_hovered)
	var mode_menu: PopupMenu = adventure_menu
	advanced_menu.set_item_disabled(advanced_menu.get_item_index(5), true)
	advanced_menu.set_item_disabled(advanced_menu.get_item_index(4), coast_mode or generated_v3_mode)
	mode_menu.set_item_disabled(mode_menu.get_item_index(11), not coast_mode)
	mode_menu.set_item_disabled(mode_menu.get_item_index(1),not playtest_mode)
	mode_menu.set_item_disabled(mode_menu.get_item_index(13),playtest_mode and not generated_mode)
	mode_menu.set_item_text(mode_menu.get_item_index(1), "保存海岸冒险" if coast_mode else ("保存测试冒险" if playtest_mode else "只读预览不能覆盖存档"))
	mode_menu.set_item_text(mode_menu.get_item_index(2), "读取海岸冒险" if coast_mode else ("读取测试冒险" if playtest_mode else "查看旧版存档（只读）"))
	mode_menu.set_item_text(mode_menu.get_item_index(3), "重置海岸冒险" if coast_mode else ("重置AI-GM测试渡口" if playtest_mode else "选择多地貌预览"))
	import_text.text = ""; import_error_label.text = ""
	if playtest_mode:
		journal_drawer.title = "主持手记 · 真实海岸冒险" if coast_mode else "主持手记 · AI-GM框架测试"
		import_dialog.title = "人工离线评估 / 可选叙事JSON"
		import_text.placeholder_text = "ai_gm_assessment/v1；provenance须live=false、kind=model_reply。" + ("海岸动作字段见导出请求中的 action_schemas；支持路线、倒树、持续状态及旧灯剧情。" if coast_mode else "仅fixture_gate/listen。")
		goal.placeholder_text = "你想做什么？"
		relay_note.text = "当前为离线模式，尚未连接 AI。结束回合后须人工导入裁定。\n下方为临时规则与开发测试工具；署名样例不代表模型回复。"
		playtest_reset_dialog.title = "重置海岸冒险？" if coast_mode else "重置 AI-GM 测试渡口？"
		playtest_reset_dialog.ok_button_text = "重新开始" if coast_mode else "重置测试渡口"
		playtest_reset_dialog.dialog_text = "将替换此模式进度；独立存档不会自动覆盖。要保留请先保存。"
		sync_playtest_request()
		append_journal("芦灯" if coast_mode else "主持人", "旧灯已经熄了三夜。先观察岸线，再到我身旁，我们一起把灯点亮。" if coast_mode else "渡船即将出发。芦灯说：潮水转向前，请说明你的来意。")
		set_status("真实地理＋棋子＋回合已接通 · 样例明确署名，任意自由文字需离线评估" if coast_mode else "新框架测试模式 · 真实程序骰子，演示公式")
	else:
		journal_drawer.title = "地图预览记录（只读）"
		relay_note.text = MAP_PREVIEW_NOTICE+"。\n旧版模型裁定、掷骰、回放和请求导出已停用；原存档不会被覆盖。"
		goal.placeholder_text = "只读地图预览不执行行动"
		append_journal("地图预览（只读）", "可查看地貌、移动镜头和关注对象；尚未接入当前行动规则。返回海岸会保留原来的冒险、文字草稿与记录。")
		set_status(MAP_PREVIEW_NOTICE)
	if generated_mode and not generated_v3_mode:
		mode_menu.set_item_text(mode_menu.get_item_index(1),"保存多地貌冒险")
		mode_menu.set_item_text(mode_menu.get_item_index(2),"读取此多地貌冒险")
		mode_menu.set_item_text(mode_menu.get_item_index(3),"重置此多地貌冒险")
		journal.clear(); journal_drawer.title="主持手记 · 多地貌探索第一阶段"
		append_journal("多地貌玩法原型","此模式仍使用旧宏观地形显示，尚未迁移当前海岸美术。移动、邻格观察、休息和精确存档已接通。桥梁、聚落、树木操作、战斗与海岸故事尚未迁移。点击只关注，所有行动仍先评估。")
		relay_note.text="固定程序结算 · 无实时API。先选择署名样例填入文字并结束回合，再采用署名评估；自由文字可导入人工离线评估。"
		var with_inventory: bool=playtest.state_copy().get("generated_world",{}).get("inventory_profile") in ["generated_inventory/v1","generated_v3_inventory/v1"]
		if with_inventory: append_journal("行礼包",generated_inventory_intro(playtest.state_copy()))
		import_text.placeholder_text="ai_gm_assessment/v1；移动、观察、休息"+("、行礼包放下与拾回" if with_inventory else "")+"；具体字段见导出请求。"
		playtest_reset_dialog.title="重置此多地貌冒险？"
		if playtest.phase()!="idle":
			set_player_intent(str(playtest.action_copy().get("goal","")),true)
			end_turn_requested=true
		set_status("多地貌玩法原型 · 移动 / 观察 / 休息"+(" / 行囊放下与拾回" if with_inventory else ""))
	if generated_v3_mode and not actor_action_mode:
		for entry in [[1,"保存新地形探索"],[2,"读取此新地形探索"],[3,"重新开始这张地图"]]:mode_menu.set_item_text(mode_menu.get_item_index(entry[0]),entry[1])
		journal.clear();journal_drawer.title="主持手记 · 新地形探索"
		append_journal("新地形探索","你来到一片陌生的土地。先看看脚下，再选一处干燥的落脚点。点击只关注；行动需文字描述与裁定。可在“连接与高级”中选择移动、观察或休息示例。")
		relay_note.text="离线演示，尚未接入实时AI。可应用预设裁定，或导入人工离线评估；行动由固定规则结算。河流、城镇和物品互动尚未开放。"
		import_text.placeholder_text="ai_gm_assessment/v1；只支持移动、观察、休息。具体字段见导出请求。"
		playtest_reset_dialog.title="重新开始这张地图？";playtest_reset_dialog.ok_button_text="重新开始"
		if playtest.phase()!="idle":
			set_player_intent(str(playtest.action_copy().get("goal","")),true);end_turn_requested=true
		set_status("新地形探索 · 离线预设裁定 · 独立存档")
	if generated_v3_inventory_mode and not actor_action_mode:
		for entry in [[1,"保存新地形行囊探索"],[2,"读取此行囊探索"]]:mode_menu.set_item_text(mode_menu.get_item_index(entry[0]),entry[1])
		journal_drawer.title="主持手记 · 新地形行囊探索"
		append_journal("行礼包",generated_inventory_intro(playtest.state_copy()))
		relay_note.text="离线演示，尚未接入实时AI。行动示例可应用预设裁定，自由文字需导入评估。行礼包可整件放下、拾回；没有使用、拆分、装备或转交能力。河流、城镇与战斗尚未开放。"
		import_text.placeholder_text="移动、观察、休息、整件放下或拾回行礼包；字段见此行囊版本的独立请求。"
		set_status("新地形行囊探索 · 点击只查看 · 独立存档")
	if generated_v3_village_mode and not generated_v3_npc_mode and not actor_action_mode:
		for entry in [[1,"保存村落行囊探索"],[2,"读取此村落探索"]]:mode_menu.set_item_text(mode_menu.get_item_index(entry[0]),entry[1])
		journal_drawer.title="主持手记 · 村落行囊探索"
		append_journal("沿途村落","远处有一座小村落。房屋会挡住实际占据的路线，可以沿空出的路口绕行。可点击村落、建筑和道路查看；尚无人物、进屋、交易或城门行动。")
		relay_note.text="离线演示，尚未接入实时AI。移动、观察、休息与行囊规则照常结算。村落、建筑和道路可选择查看，房屋影响通路；暂无人物、进屋、交易、城门或实体河流。"
		set_status("村落行囊探索 · 沿路靠近村落 · 独立存档")
	if generated_v3_npc_mode:
		for entry in [[1,"保存村庄冒险"],[2,"读取村庄冒险"]]:mode_menu.set_item_text(mode_menu.get_item_index(entry[0]),entry[1])
		journal_drawer.title="主持手记 · 村庄冒险"
		append_journal("沿途村庄","入口路旁有位守路村民。靠近后可以询问入口道路；点击人物只查看，交谈仍需提交意图和评估。")
		relay_note.text="离线演示，尚未接入实时AI。可填入行动示例并应用预设裁定；自由文字需导入评估。当前交谈只支持登记话题，信息与首次获知记录会保存。"
		import_text.placeholder_text="移动、观察、休息、行囊和登记话题交谈；字段见本次请求。"
		set_status("村庄冒险 · 先靠近守路村民，再提出交谈")
		_on_runtime_changed()
	if generated_v3_enemy_mode:
		append_journal("持刃拦路者","村中有个持刃拦路者。你已有木杖；先靠近到干地连通的邻格，才可提交近战意图。敌方也会单独等待评估，倒下后仍占格。中毒按每次已提交行动结算。")
		import_text.placeholder_text="探索、行囊、交谈与木杖近战；敌方近战须单独评估。具体字段见当前请求。"
		set_status("村庄冒险 · 双方行动分别评估 · 默认离线")
	if generated_v3_equipment_mode:
		append_journal("武器归属与装备","击倒后可取走原来的苦叶短刃，再另行评估换装。原武器仍在行囊中，归属与装备会保存；两件武器不能丢弃或转交。当前没有新的攻击目标。")
		set_status("村庄冒险 · 取走和换装分别评估 · 旧进度保留")
	if actor_action_mode:
		journal.clear();journal_drawer.title="主持手记 · 行动状态测试" if actor_status_mode else "主持手记 · 统一行动测试"
		import_dialog.title="人工离线意图 / 评估 / 只读叙事 JSON"
		import_text.placeholder_text=_actor_entry_proposal_schema()+" 或 ai_gm_assessment/v1；人工导入始终标为离线。"
		append_journal("行动状态测试" if actor_status_mode else "统一行动测试","相同来源的新独立进度。双方按现有单敌顺序使用普通行动；外部意图候选仍需普通评估与固定规则。没有自动攻击或自动换装。")
		if actor_status_mode:
			for entry in [[1,"保存行动状态测试"],[2,"读取行动状态测试"],[3,"重置行动状态测试"]]:mode_menu.set_item_text(mode_menu.get_item_index(entry[0]),entry[1])
			playtest_reset_dialog.title="重置行动状态测试？";playtest_reset_dialog.ok_button_text="重新开始"
		if actor_entry_restore_requested:_restore_actor_entry_history()
		_on_runtime_changed()
	refresh_world(); board.focus_player()
	if playtest_mode and _mode_ui_snapshots.has(mode): _restore_mode_ui(_mode_ui_snapshots[mode])
	if coast_mode and not board.load_error.is_empty(): set_status("地理呈现异常："+board.load_error)

func _create_scene_board(state: Dictionary) -> Node3D:
	var scene_id: String=state.actors.actor_player.scene_id
	var descriptor: Dictionary=SceneAdapters.descriptor(state,scene_id)
	if not descriptor.get("ok",false):
		show_world_load_error(str(descriptor));return null
	# Preserve the public scene/resolver descriptor; opt-in preparation only
	# substitutes its exact Coast rendering factory in this private candidate.
	var path:String=str(descriptor.script_path)
	var script:Script=CoastBoard if path=="res://view/playable_build/board.gd" else load(path)
	if script==null:show_world_load_error("已注册场景显示文件未能载入。");return null
	var next: Node3D=script.new()
	next.set_meta("active_scene_id",scene_id);next.set_meta("renderer_id",descriptor.renderer_id)
	return next

func _ensure_scene_board(state: Dictionary) -> Dictionary:
	if not coast_mode:return {"ok":true,"changed":false}
	var scene_id: String=state.actors.actor_player.scene_id
	if board.get_meta("active_scene_id","scene_coast")==scene_id:return {"ok":true,"changed":false}
	var next: Node3D=_create_scene_board(state)
	if next==null:return {"ok":false,"changed":false}
	next.attention_ui_mode=true;viewport.add_child(next)
	if not next.load_error.is_empty():
		var error: String=next.load_error;viewport.remove_child(next);next.free();show_world_load_error(error);return {"ok":false,"changed":false}
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	viewport.remove_child(board);board.free();board=next
	board.focus_candidates.connect(on_focus_candidates);board.hex_hovered.connect(on_hex_hovered)
	selected_focus.clear();resolved_focus.clear();focus_choices.clear();selected=Vector2i(99,99)
	focus_choice_popup.hide();focus_choice_button.hide();focus_details_dialog.hide();target_row.hide()
	_route_preview_key="";movement_preview.clear();route_preview_label.hide()
	return {"ok":true,"changed":true}

func coast_bundle_available(existing:RefCounted=null) -> bool:
	if not WorldBundle.ready():
		show_world_load_error(WorldBundle.last_error);return false
	if existing!=null:
		var state:Dictionary=existing.state_copy()
		if not state.is_empty() and str(state.get("generated_world",{}).get("bundle_id",""))!=WorldBundle.bundle_id():
			show_world_load_error("The active map changed while this adventure was open. Restart required; current facts were not changed.");return false
	return true

func show_world_load_error(detail:String) -> void:
	append_journal("海岸无法载入","地图文件缺失或未通过校验。当前已打开的场景和进度保留。请恢复完整更新文件后重新启动；详细原因在连接与高级中。")
	set_status("地图载入失败："+detail)

func invalidate_sample_draft() -> void:
	_signed_sample_goal=""
	_signed_sample_display=""

func set_player_intent(raw: String, signed_sample := false) -> void:
	invalidate_sample_draft()
	# A chosen sample can display natural wording without rewriting its exact
	# signed protocol goal. User edits (including edit/undo) invalidate the token.
	goal.set_block_signals(true)
	goal.text=DisplayText.player_intent(raw)
	goal.set_block_signals(false)
	if signed_sample and DisplayText.is_signed_sample(raw):
		_signed_sample_goal=raw
		_signed_sample_display=goal.text

func submitted_player_intent() -> String:
	if (coast_mode or generated_mode) and not _signed_sample_goal.is_empty() and goal.text==_signed_sample_display:
		return _signed_sample_goal
	return goal.text

func fill_coast_sample(kind: String) -> void:
	if not coast_mode or playtest.phase() != "idle": return
	var sample: String=playtest.sample_goal(kind,selected_focus)
	if sample.is_empty(): set_status("此样例需要合适的目标或物品。倒树先选附近直立的树；攻击先装备可用武器并选择敌人。"); return
	set_player_intent(sample,true)
	set_status("署名样例只填入文字，尚未行动；提交后仍须采用明确署名评估或导入JSON")

func ask_scene_framework_test() -> void:
	if not coast_mode: set_status("请先进入海岸冒险。");return
	if playtest.phase()!="idle":set_status("先完成当前行动，或在结果锁定前取消等待。");return
	scene_test_confirm_dialog.popup_centered(Vector2i(560,240))

func start_scene_framework_test() -> void:
	if not coast_mode or playtest.phase()!="idle":return
	runtime_ai.invalidate_context()
	var result: Dictionary=playtest.start_scene_framework_test()
	if not result.get("ok",false):set_status("测试场景未创建，当前冒险保留："+str(result));return
	coast_adventure=playtest
	reset_world_controls();runtime_ai.bind_adapter(playtest);sync_playtest_request();refresh_world();board.focus_player()
	append_journal("场景框架测试","你仍在海岸，测试入口已准备好。连接与高级中可填入进入或返回样例；每次转换仍需结束回合并取得有效评估。正式室内内容尚未制作。")
	set_status("独立的新测试进度已建立；没有切换场景或覆盖已有存档。")

func ask_reset_playtest() -> void:
	if not playtest_mode: return
	if playtest.phase() != "idle": set_status("先提交当前数值结果；掷前也可取消"); return
	advanced_dialog.hide()
	playtest_reset_dialog.popup_centered()

func reset_playtest() -> void:
	if _block_preview_action(): return
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	if not playtest_mode or playtest.phase() != "idle": return
	if coast_mode and not coast_bundle_available(playtest): return
	var previous_renderer_source:RefCounted=playtest.source if generated_v3_mode else null
	var candidate:RefCounted=(playtest.restarted() if playtest.has_method("restarted") else GeneratedAdventure.new(playtest.source.data)) if generated_mode else (new_coast_adventure() if coast_mode else Playtest.new())
	var candidate_ready:Dictionary=candidate.ready() if generated_mode else candidate.engine.ready()
	if not candidate_ready.ok:
		show_world_load_error(str(candidate_ready));return
	if generated_v3_mode:V3RenderResidency.reuse(previous_renderer_source,candidate.source)
	playtest=candidate
	if previous_renderer_source!=null and previous_renderer_source!=playtest.source:V3RenderResidency.suspend(previous_renderer_source)
	runtime_ai.bind_adapter(_runtime_adapter())
	if actor_action_mode:actor_action_panel.reset_consent()
	if actor_status_mode: actor_status_adventure=playtest; board.admitted_source=playtest.source
	elif actor_action_mode: actor_action_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_equipment_mode: generated_v3_equipment_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_enemy_mode: generated_v3_enemy_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_npc_mode: generated_v3_npc_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_village_mode: generated_v3_village_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_inventory_mode: generated_v3_inventory_adventure=playtest; board.admitted_source=playtest.source
	elif generated_v3_mode: generated_v3_adventure=playtest; board.admitted_source=playtest.source
	elif generated_mode: generated_adventure=playtest; board.admitted_source=playtest.source
	elif coast_mode: coast_adventure = playtest
	else: laboratory = playtest
	reset_world_controls(); sync_playtest_request(); refresh_world(); board.focus_player()
	append_journal("冒险重置", "同一生成来源的起点与数值已恢复；独立存档未覆盖。" if generated_mode else ("真实海岸初始位置与数值已恢复。" if coast_mode else "初始19格渡口恢复。果酒3份，体力8；可使用指定署名夹具。"))
	if not actor_action_mode or actor_render_error.is_empty():set_status("多地貌冒险已重置 · 独立存档不会自动覆盖" if generated_mode else ("海岸冒险已重置 · 独立存档不会自动覆盖" if coast_mode else "测试渡口已重置 · 单独存档不会自动覆盖"))

func sync_playtest_request() -> void:
	if _block_preview_action(): return
	active_action = playtest.active_action
	current_request = playtest.request()
	auto_export()
	update_playtest_controls()
	if _runtime_supported() and is_instance_valid(runtime_connection_panel):
		runtime_connection_panel.set_action_state(runtime_ai.phase())
		if generated_v3_enemy_mode and playtest.phase()=="awaiting_assessment" and not runtime_ai.busy() and runtime_connection_panel.status_label.text.begins_with("回合已结算"):
			runtime_connection_panel.status_label.tooltip_text="上次接口消息："+runtime_connection_panel.status_label.text
			runtime_connection_panel.set_status("敌方行动等待独立评估；尚未攻击或扣除体力。" if playtest.action_copy().get("actor_id")==playtest.source.enemy_id else "这次行动等待有效评估；世界尚未改变。")
		if generated_v3_npc_mode and playtest.phase()=="idle" and not runtime_ai.busy() and runtime_ai.last_result.get("ok",false) and runtime_ai.last_result.get("phase")=="assessment" and runtime_ai.last_result.get("action_id")==playtest.last_action:
			if not runtime_connection_panel.status_label.text.begins_with("回合已结算"):
				runtime_connection_panel.status_label.tooltip_text="上次接口消息："+runtime_connection_panel.status_label.text
			runtime_connection_panel.set_status("回合已结算，可以继续行动；可选叙述不会改变数值。")

func submit_playtest() -> void:
	if _block_preview_action(): return
	if actor_action_mode and not actor_render_error.is_empty():set_status("当前显示未通过校验，请读取或重新开始。");return
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	var raw: String=submitted_player_intent()
	if is_instance_valid(runtime_ai) and runtime_ai.client.contains_current_credential(raw):
		set_status("行动文字包含当前连接凭据，请移除后重试；未记录或发送。");return
	var result: Dictionary = playtest.begin_intent(raw, selected_focus)
	if not result.ok: set_status("意图未创建：" + str(result)); return
	append_journal("你 · 明确意图", goal.text)
	sync_playtest_request()
	if actor_action_mode:set_status("普通行动等待评估；数值尚未改变。测试入口没有预设AI意图。")
	else:set_status("行动已记录，尚未执行；可请求或导入有效评估，行动示例可用预设裁定。" if generated_v3_npc_mode else ("行动已记录，尚未执行；示例可应用预设裁定，自由文字需导入离线评估。" if generated_v3_mode else "ai_gm_assessment/v1请求已生成 · 明确署名样例可用；任意自由文本须人工离线DecisionModel评估"))
	if _runtime_supported() and not DisplayText.is_signed_sample(raw) and not (generated_v3_npc_mode and playtest.fixture_available()) and runtime_ai.automatic_assessment_enabled(): runtime_ai.request_assessment()

func playtest_fixture() -> void:
	if _block_preview_action(): return
	if not playtest_mode: return
	if playtest.phase() == "idle":
		if coast_mode or generated_mode: set_status("先填写行动并结束回合，再应用预设裁定或导入离线评估。" if generated_v3_mode else "先选择明确署名样例填入文字并提交，或自行输入再导入离线评估"); return
		goal.text = Playtest.FIXTURE_GOAL
		set_status("指定示例已填入，尚未行动。请提交意图，再采用署名夹具评估")
		return
	if is_instance_valid(runtime_ai): runtime_ai.invalidate_context()
	var result: Dictionary = playtest.prepare_fixture()
	if not result.ok: set_status("评估未应用：" + _assessment_error_text(result)); return
	sync_playtest_request()
	var author: String=playtest.action_copy().get("assessment",{}).get("provenance",{}).get("provider",Coast.AUTHOR if coast_mode else Playtest.FIXTURE_AUTHOR)
	set_status("预设裁定已应用，未调用实时AI；接下来由游戏规则结算。" if generated_v3_mode else author + " · 手写演示评估，未调用模型；评估与后果分支已冻结，尚未执行")
	complete_requested_turn()

func _assessment_error_text(result: Dictionary) -> String:
	if generated_v3_inventory_mode:
		var item_messages:Dictionary={"GENERATED_ITEM_REACH":"离行礼包太远；先走到同格或直接连通的干地邻格。","ITEM_RANGE":"离物品太远；先靠近，再提交拾回行动。","ITEM_OWNERSHIP":"这件物品目前不由你携带，不能替其他角色放下或转移。","ITEM_DUPLICATE":"行礼包已经在你身上，无需再次拾回。","ITEM_CAPABILITY":"这件物品没有这项能力；此版本只支持整件放下和拾回。","ACTION_FACT":"评估缺少当前旅人或物品的明确资料；尚未执行行动。"}
		if item_messages.has(result.get("code","")):return item_messages[result.code]
	var errors: Array = result.get("errors",[])
	return String(errors[0]) if not errors.is_empty() else str(result.get("code","评估无法应用"))

func apply_playtest_reply(decision: Dictionary) -> bool:
	if _block_preview_action(): return false
	if actor_action_mode and decision.get("schema_version")==_actor_entry_proposal_schema():
		# Cancel only transport ownership; preserve the grant being answered.
		runtime_ai.cancel_transport_for_manual()
		if runtime_ai.client.contains_current_credential(JSON.stringify(decision)):set_status("导入内容包含连接凭据，未记录或应用。");return false
		var accepted:Dictionary=playtest.accept_decision(decision)
		if not accepted.get("ok",false):set_status("意图候选未接纳："+str(accepted));return false
		_on_actor_intention_ready(str(playtest.action_copy().get("actor_id","")),str(playtest.action_copy().get("goal","")))
		set_status("人工离线意图候选已接纳；仍需普通行动评估，尚未行动。")
		return true
	if is_instance_valid(runtime_ai) and runtime_ai.client.contains_current_credential(JSON.stringify(decision)):
		set_status("导入内容包含当前连接密钥，未显示、保存或应用。");return false
	if is_instance_valid(runtime_ai) and decision.get("schema_version")=="ai_gm_assessment/v1": runtime_ai.invalidate_context()
	var result: Dictionary = _runtime_adapter().import_narration(decision) if (actor_action_mode or generated_v3_npc_mode) and decision.get("schema_version")=="ai_gm_narration/v1" else playtest.import_reply(decision)
	if not result.ok: set_status("评估未应用，数值保留：" + _assessment_error_text(result)); return false
	if decision.get("schema_version") == "ai_gm_narration/v1":
		if not result.get("already_recorded",false):
			var action_id:String=str(decision.get("action_id",""))
			var caption:String="叙事记录 · 第%d回合"%int(playtest.committed(action_id).turn) if actor_action_mode else "叙事记录"
			var promote_latest:bool=not actor_action_mode or (action_id==playtest.last_action and playtest.phase()=="idle")
			append_journal(caption,result.narration,promote_latest)
		set_status("叙事仅显示文字，不能改数值、重掷或阻塞提交")
	else:
		set_status("人工离线评估通过结构校验，演示规则已准备；下一步结算一次")
	sync_playtest_request()
	complete_requested_turn()
	return true

func advance_playtest() -> void:
	if _block_preview_action(): return
	if actor_action_mode and not actor_render_error.is_empty():set_status("当前显示未通过校验，请读取或重新开始。");return
	var phase: String = playtest.phase()
	var result: Dictionary
	match phase:
		"ready_roll":
			result = playtest.roll_once()
			if result.ok: set_status("结果已锁定 · 禁止重掷 / 取消；下一步暂存预览")
		"rolled":
			result = playtest.stage()
			if result.ok: set_status("权威结果已暂存，事实尚未改变 · 可以直接提交，无需叙事")
		"staged":
			var before_state: Dictionary=playtest.state_copy()
			result = playtest.commit()
			if result.ok:
				if actor_action_mode or generated_v3_npc_mode:_runtime_adapter().committed()
				end_turn_requested = false
				append_journal("回合结束", readable_turn_feedback())
				if not actor_action_mode or result.get("receipt",{}).get("actor_id")=="actor_player":goal.text = ""
				refresh_world(true); _refresh_transient_focus()
				if (actor_action_mode or coast_mode or generated_v3_enemy_mode) and actor_render_error.is_empty() and not result.get("already_committed",false) and (board.has_method("present_status_receipt") if actor_status_mode else board.has_method("present_committed_receipt")):
					_update_feedback_safe_rect()
					if actor_status_mode:
						var receipt:Dictionary=result.get("receipt",{})
						board.present_status_receipt(receipt,before_state,playtest.public_receipt_record(str(receipt.get("action_id",""))))
					else:board.present_committed_receipt(result.get("receipt",{}),before_state)
				if not actor_action_mode or actor_render_error.is_empty():set_status("这一回合已完成，可以继续探索。" if generated_v3_mode else "数值已原子提交一次 · 可继续意图；可选叙事失败不影响数值")
		_:
			set_status("先导入有效评估，或使用指定署名夹具")
			return
	if not result.ok: set_status("阶段未推进，状态保留：" + str(result))
	sync_playtest_request()
	if phase=="staged" and result.ok and _runtime_supported() and actor_render_error.is_empty():
		if _waiting_enemy_phase(): _queue_required_enemy_turn()
		else: runtime_ai.committed()

func _waiting_enemy_phase() -> bool:
	return actor_render_error.is_empty() and (actor_action_mode or coast_mode or generated_v3_enemy_mode) and playtest!=null and playtest.phase()=="idle" and playtest.has_method("enemy_response_available") and playtest.enemy_response_available()

func _begin_required_enemy_turn() -> void:
	# Explicit input supersedes any earlier scheduled request as well.
	_enemy_dispatch_generation+=1
	if _api_settings_open() or process_mode==Node.PROCESS_MODE_DISABLED:return
	if not _waiting_enemy_phase(): return
	if actor_action_mode:
		_prepare_actor_decision();return
	runtime_ai.invalidate_context()
	var result: Dictionary=playtest.begin_enemy_response()
	if not result.get("ok",false): set_status("敌方行动尚未就绪："+str(result)); return
	set_player_intent(str(playtest.action_copy().get("goal","")),true)
	append_journal("敌方 · 行动意图",goal.text)
	end_turn_requested=true
	sync_playtest_request()
	set_status("敌方行动等待有效评估；尚未攻击、扣除体力或造成伤害。")
	if runtime_ai.automatic_assessment_enabled(): runtime_ai.request_assessment()

func _runtime_supported()->bool:
	return actor_action_mode or coast_mode or generated_v3_npc_mode
func _runtime_adapter()->RefCounted:
	if coast_mode:return playtest
	if actor_action_mode:return playtest
	if not generated_v3_npc_mode or playtest==null:return null
	# Each preserved profile owns its unsaved optional prose as well as its
	# adapter/draft. Replacing that profile's adapter starts a fresh facade.
	var profile_key:String=str(playtest.source.identity.profile)
	var cached:RefCounted=_village_runtime_sessions.get(profile_key)
	if cached==null or cached.adapter!=playtest:
		cached=VillageRuntimeSession.new(playtest);_village_runtime_sessions[profile_key]=cached
	village_runtime_session=cached
	return village_runtime_session

func _on_runtime_assessment(action_id: String) -> void:
	if not _runtime_supported() or playtest==null or playtest.active_action!=action_id: return
	sync_playtest_request(); complete_requested_turn()

func _on_runtime_narration(action_id: String, text: String) -> void:
	if not _runtime_supported() or playtest==null or (not actor_action_mode and (playtest.phase()!="idle" or playtest.last_action!=action_id)): return
	var recorded: Dictionary=_runtime_adapter().record_narration(action_id,text,"manual" if actor_action_mode and not runtime_ai.client.provider_info().live else "provider")
	if is_instance_valid(runtime_connection_panel): runtime_connection_panel.set_action_state(runtime_ai.phase())
	if not recorded.get("ok",false):
		if actor_action_mode: return
		append_journal("叙事记录 · 暂未保存",text)
		set_status("叙事未能加入历史，已提交事实保持不变："+str(recorded));return
	var recorded_text:String=str(recorded.get("narration",text))
	if not actor_action_mode or action_id==playtest.last_action:playtest.narration=recorded_text
	if not recorded.get("already_recorded",false):
		var caption:String="叙事记录 · 第%d回合"%int(playtest.committed(action_id).turn) if actor_action_mode else "叙事记录"
		# A delayed committed receipt belongs in history while a newer action owns the current display.
		var promote_latest:bool=not actor_action_mode or (action_id==playtest.last_action and playtest.phase()=="idle")
		append_journal(caption,recorded_text,promote_latest)

func _on_runtime_changed() -> void:
	if not is_instance_valid(demo_button) or not is_instance_valid(playtest_panel):return
	var working:bool=is_instance_valid(runtime_ai) and runtime_ai.busy()
	if generated_v3_enemy_mode and working and not _enemy_runtime_was_busy and is_instance_valid(advanced_dialog) and advanced_dialog.visible:
		_reveal_enemy_runtime_actions.call_deferred(_mode_epoch)
	_enemy_runtime_was_busy=working
	if _runtime_supported() and is_instance_valid(relay_note):
		if runtime_ai.client.configured() and runtime_ai.connection_enabled:
			var live:bool=runtime_ai.client.provider_info().live
			relay_note.text=("接口已配置；服务是否可用以实际响应为准。\n" if live else "离线测试通道，不会联网或计费。\n")+("结束回合将请求一次AI评估（可能计费）。" if live and runtime_ai.automatic_assessment_enabled() else ("结束回合会请求离线测试评估。" if runtime_ai.automatic_assessment_enabled() else "自动请求未启用，可手动请求或导入裁定。"))
			if generated_v3_npc_mode:relay_note.text+="\n村庄冒险资料上限仍为64 KiB；连接上限不能扩大原有行动范围。"
		else: relay_note.text=("当前未配置可用AI接口。自由文字会等待人工导入评估。\n行动示例可使用预设裁定，未调用实时AI。" if generated_v3_npc_mode else "当前未配置可用AI接口。自由意图会等待人工裁定。\n署名样例是明确的离线规则演示，不是模型回复。")
	if generated_v3_npc_mode:
		mode_legend.text="文字决定意图 · 点击只关注 · 游戏规则结算"
		if is_instance_valid(generated_v3_npc_panel) and generated_v3_npc_panel.get_child_count()>0:
			var caption:Label=generated_v3_npc_panel.get_child(0).get_child(0)
			var connection_text:String="离线等待评估"
			if runtime_ai.client.configured() and runtime_ai.connection_enabled:connection_text="API已配置" if runtime_ai.client.provider_info().live else "离线测试通道"
			caption.text="村庄冒险 · "+connection_text
			if generated_v3_enemy_mode:generated_v3_enemy_panel.get_child(0).get_child(0).text=caption.text
			if generated_v3_equipment_mode:generated_v3_equipment_panel.get_child(0).get_child(0).text=caption.text
	if actor_action_mode:
		if is_instance_valid(runtime_ai) and is_instance_valid(actor_action_panel) and not runtime_ai.intention_consent:actor_action_panel.reset_consent()
		mode_legend.text="行动状态测试 · 双方普通行动 / 公开状态 · 独立存档" if actor_status_mode else "统一行动测试 · 双方普通行动 · 旧存档独立"
		relay_note.text="敌方每步：一次意图候选请求，再一次普通行动评估；可选叙事另一次，均可能计费。默认不请求意图；人工 JSON 明确离线。"
	update_turn_controls()

func readable_turn_feedback() -> String:
	if not (coast_mode or generated_mode) or playtest.last_feedback.is_empty(): return "你的行动已经完成。"
	var text_: String = playtest.last_feedback
	var coords:=RegEx.new(); coords.compile("到达（[^）]+）")
	text_=coords.sub(text_,"走到了新的落脚处",true)
	text_=text_.replace("桐岸巡逻走到了新的落脚处","桐岸继续沿岸巡视")
	return text_

func update_playtest_controls() -> void:
	if is_map_preview():
		_update_map_preview_controls(); return
	if playtest == null: return
	var phase: String = playtest.phase()
	var pending := phase != "idle"
	var enemy_waiting: bool=_waiting_enemy_phase()
	var enemy_pending: bool=pending and playtest.action_copy().get("actor_id","actor_player")!="actor_player"
	turn_footer.visible = pending or enemy_waiting
	goal.editable = not pending and not enemy_waiting
	submit_button.visible = true
	var runtime_pending: bool=_runtime_supported() and is_instance_valid(runtime_ai) and runtime_ai.busy() and phase!="idle"
	submit_button.disabled = phase == "awaiting_assessment" or end_turn_busy or runtime_pending
	submit_button.text = "等待\n裁定" if phase == "awaiting_assessment" else ("完成\n回合" if pending else "结束\n回合")
	cancel_button.visible = pending
	cancel_button.disabled = not playtest.can_cancel()
	cancel_button.text = "取消等待" if playtest.can_cancel() else "结果已锁定，不能取消"
	roll_button.visible = phase in ["ready_roll","rolled","staged"]
	roll_button.disabled = not roll_button.visible
	roll_button.text = {"ready_roll":"调试：结算一次","rolled":"调试：暂存结果","staged":"调试：提交结果"}.get(phase,"等待裁定")
	phase_label.text = {"idle":"等待你的行动","awaiting_assessment":"离线 · 等待裁定","ready_roll":"裁定已就绪","rolled":"结果已锁定","staged":"结果待提交"}.get(phase,phase)
	next_step_label.text = {"idle":"写下行动后结束回合","awaiting_assessment":"菜单 → 连接与高级 → 导入裁定","ready_roll":"可完成本回合","rolled":"可继续完成本回合","staged":"可继续完成本回合"}.get(phase,"")
	if generated_v3_mode:
		if phase=="idle":next_step_label.text="连接与高级 → 选择行动示例"
		elif phase=="awaiting_assessment":next_step_label.text="连接与高级 → 应用预设裁定或导入评估" if playtest.fixture_available() else "连接与高级 → 导入评估或取消"
	if _runtime_supported() and is_instance_valid(runtime_ai) and runtime_ai.client.configured() and phase=="awaiting_assessment":
		phase_label.text="等待有效评估 · 尚未行动"
		if generated_v3_npc_mode and runtime_ai.connection_enabled and not runtime_ai.busy() and not playtest.fixture_available():next_step_label.text="连接与高级 → 请求评估、导入或取消"
	if runtime_pending and phase=="awaiting_assessment":
		phase_label.text=("等待AI评估 · 尚未行动" if runtime_ai.client.provider_info().live else "等待离线测试评估 · 尚未行动"); next_step_label.text="可从连接与高级取消等待"
	elif _runtime_supported() and phase=="awaiting_assessment" and runtime_ai.last_result.get("action_id","")==playtest.active_action and not runtime_ai.last_result.get("ok",true):
		phase_label.text="评估未完成 · 世界未改变"; next_step_label.text="连接与高级 → 重试、导入或取消"
	if enemy_pending:
		phase_label.text="敌方 · "+phase_label.text
		if phase=="awaiting_assessment": submit_button.text="等待\n敌方"; next_step_label.text="连接与高级 → 提供敌方评估"
	elif enemy_waiting:
		phase_label.text="敌方回合 · 等待裁定"; next_step_label.text="继续敌方回合后才能开始你的下一次行动"; submit_button.text="继续\n敌方"
	if (actor_action_mode or coast_mode or generated_v3_enemy_mode) and not pending and int(playtest.state_copy().actors.actor_player.health.current)<=0:
		turn_footer.show();goal.editable=false;submit_button.disabled=true;submit_button.text="已经\n倒下";phase_label.text="旅人已经倒下";next_step_label.text="可从冒险菜单读取存档或重新开始"
	relay_row.visible = true
	export_button.disabled = current_request.is_empty()
	import_button.disabled = phase in ["ready_roll","rolled"]
	demo_button.visible = false
	die_label.visible = false
	clear_target_button.disabled = selected_focus.is_empty()
	clear_target_button.visible = not selected_focus.is_empty()
	target_row.visible = not selected_focus.is_empty()
	if not resolved_focus.is_empty():
		target_label.text=_focus_caption(resolved_focus,"下一次目标" if pending else "目标")
		target_label.tooltip_text=_focus_details_description()+( "\n当前行动的目标已经确定；新点击只改变下一次目标。" if pending else "")
	if actor_action_mode:
		if playtest.decision_pending():
			phase_label.text="敌方 · 等待外部意图候选";next_step_label.text="连接与高级 → 导出候选请求 / 人工导入 / 明确启用接口"
			cancel_button.visible=true;cancel_button.disabled=false
		if runtime_ai.busy():submit_button.disabled=true
	if actor_action_mode and not actor_render_error.is_empty():
		turn_footer.show();goal.editable=false;submit_button.disabled=true;roll_button.disabled=true
		phase_label.text="棋盘显示未通过校验 · 行动已暂停";next_step_label.text="数值进度保留；可保存、读取或重新开始"
	playtest_panel.update_adapter(playtest)
	update_movement_preview()

func end_turn() -> void:
	if _api_settings_open(): return
	if has_node("OfflineMoveDemo") and get_node("OfflineMoveDemo").handle_end_turn(): return
	if _block_preview_action(): return
	# The player's single primary action submits the intent, then waits honestly
	# for an accepted assessment. Existing advanced stage controls remain intact.
	if end_turn_busy: return
	if not playtest_mode:
		if not active_action.is_empty(): return
		submit_action(); return
	if playtest.phase() == "awaiting_assessment": return
	if _runtime_supported() and runtime_ai.busy() and playtest.phase()!="idle": return
	if playtest.phase() == "idle":
		if _waiting_enemy_phase(): _begin_required_enemy_turn(); return
		if goal.text.strip_edges().is_empty():
			turn_footer.show(); phase_label.text="请先写下你想做什么"; next_step_label.text=""; goal.grab_focus(); return
		end_turn_requested = true
		submit_action()
		if playtest.phase() == "idle": end_turn_requested = false
	else:
		end_turn_requested = true
		complete_requested_turn()

func complete_requested_turn() -> void:
	if _block_preview_action(): return
	if not end_turn_requested or end_turn_busy or not playtest_mode: return
	if playtest.phase() not in ["ready_roll","rolled","staged"]: return
	end_turn_busy = true
	var action_id: String = playtest.active_action
	# Every stage is still validated by the original engine. A failure leaves
	# the last safe phase available for save/recovery; no UI writes world facts.
	for expected in ["ready_roll","rolled","staged"]:
		if playtest.phase() != expected: continue
		if playtest.active_action != action_id: break
		advance_playtest()
		if playtest.phase() == expected: break
	end_turn_busy = false
	if playtest.phase() == "idle":
		end_turn_requested = false
		advanced_dialog.hide()
	update_playtest_controls()

func refresh_playtest_world(animate_changes: bool = false) -> void:
	if is_instance_valid(private_main_visual):private_main_visual.before_world_change()
	if is_instance_valid(private_main_visual):private_main_visual.after_world_change.call_deferred()
	if has_node("SelectionMotion"): get_node("SelectionMotion").cancel()
	var state: Dictionary = playtest.state_copy()
	if not state.get("actors") is Dictionary or not state.actors.has("actor_player"):
		show_world_load_error(WorldBundle.last_error if not WorldBundle.last_error.is_empty() else "Invalid adventure state");return
	var renderer: Dictionary=_ensure_scene_board(state)
	if not renderer.ok:return
	var source_coast: bool=coast_mode and state.actors.actor_player.scene_id=="scene_coast"
	var render_state: Dictionary=SceneAdapters.projection(state,"scene_coast") if source_coast else state
	if generated_mode and animate_changes: board.set_world(render_state,true,playtest.authoritative_result().get("public_effects",[]))
	elif source_coast and animate_changes and not renderer.changed: board.set_world(render_state,true,playtest.authoritative_result().get("public_effects",[]))
	else: board.set_world(render_state,animate_changes and not renderer.changed)
	if actor_action_mode:
		actor_render_error=str(board.load_error)
		if not actor_render_error.is_empty():
			board.hide();board.set_process_input(false);end_turn_requested=false
			actor_render_suspended=true;runtime_ai.bind_adapter(null);actor_action_panel.reset_consent()
			set_status("数值进度已保留，但当前棋盘显示未通过支撑校验。后续行动已暂停；可保存、读取或重新开始。"+actor_render_error)
			return
		board.show();board.set_process_input(not _api_settings_open())
		if actor_render_suspended:
			actor_render_suspended=false;runtime_ai.bind_adapter(playtest);actor_action_panel.reset_consent()
	if renderer.changed:board.focus_player()
	if coast_mode:adventure_menu.set_item_disabled(adventure_menu.get_item_index(11),state.actors.actor_player.scene_id!="scene_coast")
	_route_preview_key=""
	TerrainMaterials.set_software_preview(software_preview)
	var actor: Dictionary = state.actors.actor_player
	map_title.text = str(state.scenes[actor.scene_id].get("name","南潮海岸")) if coast_mode else "暮潮渡口"
	map_stats_label.text = ("1801格真实海岸 / 固定规则" if actor.scene_id=="scene_coast" else "七格场景框架测试 / 正式室内内容尚未制作") if coast_mode else "19 格 / 演示rule A"
	if generated_mode:
		map_title.text=state.scenes[actor.scene_id].name
		map_stats_label.text="%d格 / 固定规则探索第一阶段"%state.hexes.size()
		if generated_v3_npc_mode:map_title.text="村庄冒险 · "+str(state.generated_world.seed_token)
		elif generated_v3_village_mode:map_title.text="村落行囊探索 · "+str(state.generated_world.seed_token)
		if actor_status_mode:map_title.text="行动状态测试 · "+str(state.generated_world.seed_token)
	hero_subtitle.text = "框架测试 · 回合%d" % state.turn
	update_character_status(actor,state.turn,state)
	hero_label.tooltip_text = hero_label.text
	for child in inventory_box.get_children(): child.queue_free()
	var statuses: Array[String]=playtest.status_details("actor_player") if actor_action_mode else PlayerDetails.status_lines(PlayerDetails.adapt_actor(state,actor))
	inventory_box.add_child(label("当前状态",18))
	if statuses.is_empty(): inventory_box.add_child(label("没有持续状态",15,MUTED))
	for line in statuses:
		var status_text=label(line,15,MUTED); status_text.custom_minimum_size.x=420; status_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; inventory_box.add_child(status_text)
	inventory_box.add_child(label("随身物品",18))
	for id in actor.inventory:
		if not state.items.has(id): continue
		var item: Dictionary = state.items[id]
		inventory_box.add_child(label("%s ×%d%s" % [item.name, item.quantity," · 已装备" if id in actor.get("equipment",{}).values() else ""], 18))
		if generated_mode and playtest.has_method("item_reference") and (not generated_v3_enemy_mode or id=="item_travel_bundle") and (not actor_action_mode or not playtest.item_reference(str(id)).is_empty()):
			var select_button=button("查看"+str(item.name),select_generated_item.bind(str(id)));select_button.tooltip_text="只选择和查看，不会放下或使用";inventory_box.add_child(select_button)
		var description := label(String(item.description), 15, MUTED)
		description.custom_minimum_size.x = 420; description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inventory_box.add_child(description)
	var ground_items: Array=[]
	for item in state.items.values():
		var known_generated_pack:bool=generated_mode and playtest.has_method("item_reference") and item.get("id")=="item_travel_bundle"
		if (item.get("hex",[])==actor.hex or known_generated_pack) and item.get("scene_id","")==actor.scene_id and not item.has("owner_actor_id") and int(item.get("quantity",0))>0: ground_items.append(item)
	if not ground_items.is_empty(): inventory_box.add_child(label("地上的物品" if generated_mode and ground_items.any(func(item):return item.hex!=actor.hex) else "脚边物品",18))
	for item in ground_items:
		inventory_box.add_child(label("%s ×%d" % [item.name,item.quantity],18))
		if generated_mode and item.get("hex",[])!=actor.hex:inventory_box.add_child(label("留在（%d，%d），尚未拾回"%item.hex,15,MUTED))
		if generated_mode and playtest.has_method("item_reference") and (not actor_action_mode or not playtest.item_reference(str(item.id)).is_empty()):
			var select_button=button("查看"+str(item.name),select_generated_item.bind(str(item.id)));select_button.tooltip_text="只选择和查看，不会自动拾取";inventory_box.add_child(select_button)
		var description=label(str(item.get("description","")),15,MUTED);description.custom_minimum_size.x=420;description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;inventory_box.add_child(description)
	update_playtest_controls()

static func generated_inventory_intro(state: Dictionary) -> String:
	var item:Dictionary=state.get("items",{}).get("item_travel_bundle",{})
	var custody:String="行礼包的位置与归属可在行囊中查看"
	if item.get("owner_actor_id")=="actor_player":custody="行礼包目前随身携带"
	elif not item.has("owner_actor_id") and item.get("hex") is Array and item.hex.size()==2:custody="行礼包留在（%d，%d）"%item.hex
	return custody+"。点击模型，或在行囊里点“查看行礼包”，可以查看详情。放下或拾回都要先提交行动，再取得有效裁定。它不能拆分、装备，也没有额外效果。"

func select_generated_item(id: String) -> void:
	if not generated_mode or not playtest.has_method("item_reference"):return
	var reference: Dictionary=playtest.item_reference(id)
	if reference.is_empty():set_status("这件物品的位置已变化，请重新查看行囊。");return
	_apply_focus(reference)
	inventory_dialog.hide()
	show_focus_details()

func _input(event: InputEvent) -> void:
	if _api_settings_open(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F11:
		toggle_fullscreen(); get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if tools_menu.get_popup().visible or adventure_menu.visible or advanced_menu.visible or display_menu.visible:
			close_tool_menus(); get_viewport().set_input_as_handled(); return
		if world_dialog.visible:
			world_dialog.hide(); get_viewport().set_input_as_handled(); return
		if is_instance_valid(board) and board.has_method("_cancel_committed_camera"):board._cancel_committed_camera()
		if advanced_dialog.visible: advanced_dialog.request_motion_close()
		elif journal_open: toggle_journal()
		elif intent_expanded: toggle_intent()
		elif get_window().mode == Window.MODE_FULLSCREEN: toggle_fullscreen()
		else: goal.release_focus()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F12:
		screenshot_serial += 1
		capture_board("playable_build_20261002/native_%03d.png" % screenshot_serial)

func view_trial_river() -> void:
	if not coast_mode: return
	if not board.has_method("view_river"):set_status("当前是场景框架测试室；返回海岸后可查看河岸。");return
	if board.view_river():
		set_status("已看向同一地图上的局部试河；旅人没有移动。可关注两岸；接触河水的移动需单独跨水评估")
	else: set_status("局部试河未加载："+board.river_status)


func start_generated_from_preview() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if not is_map_preview() or not game.state.get("generated_world") is Dictionary:
		set_status("先打开多地貌地图预览并生成地图，再选择以此地图开始探索。");return
	if last_world_generation_metadata.is_empty():
		set_status("这份旧预览没有种子/预设记录；请重新生成预览后开始探索。原世界与草稿保留。");return
	var envelope: Dictionary={"source":game.state.generated_world.duplicate(true),"metadata":last_world_generation_metadata.duplicate(true)}
	var carry_inventory: bool=is_instance_valid(generated_inventory_choice) and generated_inventory_choice.button_pressed
	var epoch: int=_mode_epoch
	var build_epoch: int=_world_build_epoch
	generated_start_busy=true
	set_status("正在验证种子、预设与实际干地起点连通性；原海岸与预览保持不变。")
	await get_tree().process_frame
	if epoch!=_mode_epoch or build_epoch!=_world_build_epoch or world_build_busy or not is_map_preview():generated_start_busy=false;return
	var candidate:RefCounted=prepare_inventory_adventure(envelope) if carry_inventory else prepare_seeded_adventure(envelope)
	generated_start_busy=false
	if not candidate.ready().ok:set_status("此地图未通过玩法准入，原世界与草稿保留："+str(candidate.ready()));return
	if epoch!=_mode_epoch or build_epoch!=_world_build_epoch or not is_map_preview():return
	generated_adventure=candidate;_mode_ui_snapshots.erase("generated")
	_switch_mode("generated")

func prepare_seeded_adventure(envelope: Dictionary) -> RefCounted:
	var candidate:=SeededAdventure.new()
	candidate.start_seeded(envelope)
	return candidate

func prepare_inventory_adventure(envelope: Dictionary) -> RefCounted:
	var candidate:=InventoryAdventure.new()
	candidate.start_seeded(envelope)
	return candidate

func continue_generated_adventure() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_adventure==null:
		var candidate:RefCounted=InventoryAdventure.new() if FileAccess.file_exists(InventoryAdventure.INVENTORY_SAVE) else SeededAdventure.new()
		var loaded: Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到匹配的多地貌冒险："+str(loaded));return
		generated_adventure=candidate
	_switch_mode("generated")

func fill_generated_sample(kind: String) -> void:
	if not generated_mode or playtest.phase()!="idle":return
	var sample: String=playtest.sample_goal(kind,selected_focus)
	if sample.is_empty():set_status("先选择当前或相邻地格；移动需要可达的干地目标。");return
	set_player_intent(sample,true)
	set_status("已填入示例意图；结束回合后可应用预设裁定。" if generated_v3_mode else "署名样例只填文字；结束回合后仍须取得有效评估。")


func v3_biome_name(value:String) -> String:
	return {"desert":"沙漠","grassland":"草原","dry_steppe":"干草原","jungle":"丛林","ocean":"海洋","temperate_forest":"林地","alpine":"高山","wetland":"湿地"}.get(value,value)

func build_v3_setup_dialog() -> void:
	v3_setup_dialog=ConfirmationDialog.new();v3_setup_dialog.title="开始新旅程";v3_setup_dialog.ok_button_text="生成并开始";v3_setup_dialog.cancel_button_text="取消";add_child(v3_setup_dialog)
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(440,0);box.add_theme_constant_override("separation",10);v3_setup_dialog.add_child(box)
	var note:=Label.new();note.text="选择探索，或带着木杖和行囊走进村庄、交谈与近战。\n默认离线；村庄冒险可在连接与高级中配置可选接口。\n开始会替换对应旅程，请先保存。旧进度可在工具 → 高级中继续。";box.add_child(note)
	v3_adventure_style=OptionButton.new();v3_adventure_style.add_item("探索");v3_adventure_style.add_item("村庄冒险");box.add_child(v3_adventure_style)
	v3_vegetation_choice=CheckButton.new();v3_vegetation_choice.text="显示沿途植被（村庄冒险）";v3_vegetation_choice.button_pressed=true
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:v3_vegetation_choice.add_theme_color_override(state,INK)
	box.add_child(v3_vegetation_choice)
	var legacy_button:=Button.new();legacy_button.text="更多设置 / 旧探索格式";box.add_child(legacy_button)
	v3_legacy_settings=VBoxContainer.new();box.add_child(v3_legacy_settings);v3_legacy_settings.hide();legacy_button.pressed.connect(func():v3_legacy_settings.visible=not v3_legacy_settings.visible)
	v3_seed_input=LineEdit.new();v3_seed_input.text="726381";v3_seed_input.placeholder_text="地图种子";v3_seed_input.max_length=80;box.add_child(v3_seed_input)
	v3_radius_choice=OptionButton.new();v3_radius_choice.add_item("小地图 · 半径4",4);v3_radius_choice.add_item("大地图 · 半径12",12);box.add_child(v3_radius_choice)
	v3_recipe_choice=OptionButton.new();v3_recipe_choice.add_item("海岸地带");v3_recipe_choice.add_item("高原腹地");box.add_child(v3_recipe_choice)
	v3_inventory_choice=CheckButton.new();v3_inventory_choice.text="带行礼包探索（单独进度，不改旧存档）"
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:v3_inventory_choice.add_theme_color_override(state,INK)
	v3_inventory_choice.add_theme_color_override("font_disabled_color",MUTED);v3_legacy_settings.add_child(v3_inventory_choice)
	v3_village_choice=CheckButton.new();v3_village_choice.text="加入沿途村落（含行囊，独立进度）"
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:v3_village_choice.add_theme_color_override(state,INK)
	v3_village_choice.add_theme_color_override("font_disabled_color",MUTED);v3_legacy_settings.add_child(v3_village_choice)
	v3_village_choice.toggled.connect(func(enabled:bool):
		if enabled:v3_inventory_choice.button_pressed=true)
	v3_setup_dialog.confirmed.connect(start_v3_from_dialog)

func show_v3_setup() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	v3_setup_dialog.popup_centered()

func start_v3_from_dialog() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	var seed_value:String=v3_seed_input.text
	var radius:int=v3_radius_choice.get_selected_id()
	var recipe:String="coastal_range" if v3_recipe_choice.selected==0 else "plateau_hinterland"
	var epoch:int=_mode_epoch
	var with_inventory:bool=v3_inventory_choice.button_pressed
	var with_village:bool=v3_village_choice.button_pressed
	var with_npc:bool=v3_adventure_style.selected==1
	generated_start_busy=true;set_status("正在生成并校验新地形，原进度仍保留……")
	await get_tree().process_frame
	if epoch!=_mode_epoch:generated_start_busy=false;return
	var built:Dictionary=V3Generator.generate(seed_value,radius,recipe)
	if not built.get("ok",false):generated_start_busy=false;set_status("生成失败，原进度保留："+str(built));return
	var candidate:RefCounted
	if with_npc:
		candidate=V3EquipmentAdventure.new();candidate.feature_options={"vegetation":v3_vegetation_choice.button_pressed};candidate.start_source(built.source)
	else:candidate=V3VillageAdventure.new(built.source) if with_village else (V3InventoryAdventure.new(built.source) if with_inventory else V3Adventure.new(built.source))
	generated_start_busy=false
	if epoch!=_mode_epoch:return
	if not candidate.ready().ok:set_status("地图未通过探索校验，原进度保留："+str(candidate.ready()));return
	_switch_mode_to("generated_v3_equipment" if with_npc else ("generated_v3_village" if with_village else ("generated_v3_inventory" if with_inventory else "generated_v3")),candidate)

func continue_v3_adventure() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_adventure==null:
		var candidate:RefCounted=V3Adventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到新地形探索存档，原进度保留："+str(loaded));return
		_switch_mode_to("generated_v3",candidate)
	else:_switch_mode("generated_v3")

func continue_v3_inventory_adventure() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_inventory_adventure==null:
		var candidate:RefCounted=V3InventoryAdventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到此行囊版本的进度，其他冒险保留："+str(loaded));return
		_switch_mode_to("generated_v3_inventory",candidate)
	else:_switch_mode("generated_v3_inventory")

func continue_v3_village_adventure() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_village_adventure==null:
		var candidate:RefCounted=V3VillageAdventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到此村落版本的进度，其他冒险保留："+str(loaded));return
		_switch_mode_to("generated_v3_village",candidate)
	else:_switch_mode("generated_v3_village")

func continue_v3_npc_adventure() -> void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_npc_adventure==null:
		var candidate:RefCounted=V3NPCAdventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到村庄冒险进度，其他旅程保留："+str(loaded));return
		_switch_mode_to("generated_v3_npc",candidate)
		if generated_v3_npc_mode and playtest==candidate:
			var prose:Dictionary=_runtime_adapter().load_sidecar(candidate.default_save_path())
			for entry in _runtime_adapter().narration_entries():append_journal("叙事记录 · 第%d回合"%int(entry.turn),str(entry.narration))
			if not str(prose.get("warning","")).is_empty():append_journal("部分文字未恢复",str(prose.warning))
	else:_switch_mode("generated_v3_npc")

func show_npc_notes() -> void:
	if not generated_v3_npc_mode or playtest==null:set_status("请先开启或继续村庄冒险，再查看旅途笔记。");return
	advanced_dialog.hide();close_tool_menus()
	npc_notes_dialog.dialog_text=playtest.learned_notes()
	npc_notes_dialog.popup_centered(Vector2i(500,340))

func continue_v3_enemy_adventure()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_enemy_adventure==null:
		var candidate:RefCounted=V3EnemyAdventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到当前村庄冒险；原村庄进度可从高级菜单继续："+str(loaded));return
		_switch_mode_to("generated_v3_enemy",candidate)
		if generated_v3_enemy_mode and playtest==candidate:
			var prose:Dictionary=_runtime_adapter().load_sidecar(candidate.default_save_path())
			for entry in _runtime_adapter().narration_entries():append_journal("叙事记录 · 第%d回合"%int(entry.turn),str(entry.narration))
			if not str(prose.get("warning","")).is_empty():append_journal("部分文字未恢复",str(prose.warning))
	else:_switch_mode("generated_v3_enemy")

func _reveal_enemy_runtime_actions(epoch:int)->void:
	# Budget/status labels can reflow after the busy signal. Preserve access to
	# cancellation after the final layout, without reopening a dismissed panel.
	await get_tree().process_frame
	await get_tree().process_frame
	if epoch!=_mode_epoch or not generated_v3_enemy_mode or not is_instance_valid(runtime_ai) or not runtime_ai.busy() or not advanced_dialog.visible:return
	if is_instance_valid(advanced_scroll) and is_instance_valid(runtime_connection_panel.cancel_button):advanced_scroll.ensure_control_visible(runtime_connection_panel.cancel_button)

func continue_v3_equipment_adventure()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if generated_v3_equipment_adventure==null:
		var candidate:RefCounted=V3EquipmentAdventure.new()
		var loaded:Dictionary=candidate.load_file()
		if not loaded.ok:set_status("尚未读取到当前村庄冒险；原近战进度可从高级菜单继续："+str(loaded));return
		_switch_mode_to("generated_v3_equipment",candidate)
		if generated_v3_equipment_mode and playtest==candidate:
			var prose:Dictionary=_runtime_adapter().load_sidecar(candidate.default_save_path())
			for entry in _runtime_adapter().narration_entries():append_journal("叙事记录 · 第%d回合"%int(entry.turn),str(entry.narration))
			if not str(prose.get("warning","")).is_empty():append_journal("部分文字未恢复",str(prose.warning))
	else:_switch_mode("generated_v3_equipment")


func _river_entry_ui_snapshot() -> Dictionary:
	return {"selected_focus":selected_focus.duplicate(true),"selected_hex":[selected.x,selected.y],"goal":goal.text,"signed_goal":_signed_sample_goal,"signed_display":_signed_sample_display,"mode_epoch":_mode_epoch,"board_instance":str(board.get_instance_id()),"playtest_instance":str(playtest.get_instance_id()) if playtest!=null else "none"}

func _river_entry_modal_visible(node: Node) -> bool:
	for child in node.get_children():
		if child is Window and child.visible:return true
		if _river_entry_modal_visible(child):return true
	return false

func open_river_experiment() -> void:
	if not playtest_mode or playtest==null:
		set_status("请先进入正式旅程，再显式打开限定河流实验。");return
	if not _can_leave_current_adventure():return
	var status_:Dictionary={"world_build_busy":world_build_busy,"generated_start_busy":generated_start_busy,"end_turn_busy":end_turn_busy or end_turn_requested,"runtime_busy":(is_instance_valid(runtime_ai) and runtime_ai.busy()) or _river_entry_modal_visible(self),"active_action":active_action}
	# No eager river preload/mesh at startup; keep the accepted default untouched.
	if not is_instance_valid(river_entry_controller):
		var script:Script=load("res://view/generated_v3_river_entry/controller.gd")
		if script==null:set_status("实验入口未能载入；原旅程保持不变。");return
		river_entry_controller=script.new();add_child(river_entry_controller)
		river_entry_controller.returned.connect(func(result:Dictionary):set_status("已返回原旅程；实验使用独立进度。" if result.get("ok",false) else str(result.get("errors",[]))))
	var opened:Dictionary=river_entry_controller.open(self,playtest,status_,viewport,_river_entry_ui_snapshot)
	if not opened.get("ok",false):set_status("实验未打开："+str(opened.get("errors",[])))


func start_actor_action_test()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if not generated_v3_mode or playtest==null:
		set_status("先打开已有新地形村庄地图，再以同一来源新开统一行动测试；不会读取或迁移旧进度。");return
	var candidate:RefCounted=ActorEntryView.new(playtest.source.data)
	if not candidate.ready().ok:set_status("统一行动测试未建立："+str(candidate.ready()));return
	_switch_mode_to("actor_actions_v2",candidate)

func continue_actor_action_test()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if actor_action_adventure!=null:_switch_mode("actor_actions_v2");return
	var candidate:RefCounted=ActorEntryView.new()
	var checked:Dictionary=candidate.load_file()
	if not checked.get("ok",false):set_status("独立测试存档未读取，当前旅程保留："+str(checked));return
	actor_entry_restore_requested=true
	_switch_mode_to("actor_actions_v2",candidate)
	actor_entry_restore_requested=false

func start_actor_status_test()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if not generated_v3_mode or playtest==null:
		set_status("先打开已有新地形村庄地图，再以同一来源新开行动状态测试；不会读取或迁移旧进度。");return
	var candidate:RefCounted=StatusEntryView.new(playtest.source.data)
	if not candidate.ready().ok:set_status("行动状态测试未建立："+str(candidate.ready()));return
	_switch_mode_to("actor_status_v1",candidate)

func continue_actor_status_test()->void:
	if world_build_busy or generated_start_busy or not _can_leave_current_adventure():return
	if actor_status_adventure!=null:_switch_mode("actor_status_v1");return
	var candidate:RefCounted=StatusEntryView.new()
	var checked:Dictionary=candidate.load_file()
	if not checked.get("ok",false):set_status("独立状态存档未读取，当前旅程保留："+str(checked));return
	actor_entry_restore_requested=true
	_switch_mode_to("actor_status_v1",candidate)
	actor_entry_restore_requested=false

func _actor_entry_proposal_schema()->String:
	return playtest.proposal_schema() if actor_status_mode else "actor_intent_proposal/v1"

func _prepare_actor_decision()->void:
	if not actor_action_mode or not _waiting_enemy_phase():return
	if not playtest.decision_pending():
		var grant:Dictionary=playtest.decision_request()
		if not grant.get("ok",false):set_status("意图候选请求未建立："+str(grant));return
	sync_playtest_request()
	set_status("敌方等待外部意图候选；没有预设攻击。可导出请求并人工导入，或明确启用接口。")

func _request_actor_decision()->void:
	if not actor_render_error.is_empty() or not actor_action_mode or not _waiting_enemy_phase():return
	_prepare_actor_decision()
	var result:Dictionary=runtime_ai.request_intention()
	if not result.get("ok",false):set_status("意图请求尚未发送："+str(result))

func _on_actor_intention_ready(actor_id:String,accepted_goal:String)->void:
	if not actor_action_mode or playtest==null or playtest.action_copy().get("actor_id")!=actor_id:return
	# Never replace the player's editor with a hostile goal.
	append_journal("敌方 · 外部意图候选",accepted_goal)
	end_turn_requested=true;sync_playtest_request()
	if not _api_settings_open() and runtime_ai.automatic_assessment_enabled():runtime_ai.request_assessment()


func _restore_actor_entry_history()->void:
	journal.clear()
	for entry in playtest.journal_entries():append_journal(str(entry.get("title","冒险记录")),str(entry.get("text","")))
	var prose:Dictionary=playtest.load_sidecar(playtest.default_save_path())
	for entry in playtest.narration_entries():append_journal("叙事记录 · 第%d回合"%int(entry.turn),str(entry.narration))
	end_turn_requested=playtest.phase()!="idle"
	var pending:Dictionary=playtest.action_copy()
	if not pending.is_empty():
		if pending.get("actor_id")=="actor_player":set_player_intent(str(pending.goal))
		append_journal("敌方 · 待完成的行动" if pending.get("actor_id")!="actor_player" else "你 · 待完成的行动",str(pending.goal))
	append_journal("行动状态测试 · 继续" if actor_status_mode else "统一行动测试 · 继续","原 pending 阶段、结果和回执已恢复；没有重新选意图或重掷。")
	if not str(prose.get("warning","")).is_empty():append_journal("部分文字未恢复",str(prose.warning))


func open_natural_coast_experiment(recipe: String) -> void:
	if not playtest_mode or playtest==null:
		set_status("请先进入正式旅程，再显式打开自然海岸基础探索。");return
	if not _can_leave_current_adventure():return
	var status_:Dictionary={"world_build_busy":world_build_busy,"generated_start_busy":generated_start_busy,"end_turn_busy":end_turn_busy or end_turn_requested,"runtime_busy":(is_instance_valid(runtime_ai) and runtime_ai.busy()) or _river_entry_modal_visible(self),"active_action":active_action}
	# No eager river preload/mesh at startup; keep the accepted default untouched.
	if not is_instance_valid(natural_coast_entry_controller):
		var script:Script=load("res://view/generated_natural_coast_entry/controller.gd")
		if script==null:set_status("实验入口未能载入；原旅程保持不变。");return
		natural_coast_entry_controller=script.new();add_child(natural_coast_entry_controller)
		natural_coast_entry_controller.returned.connect(func(result:Dictionary):set_status("已返回原旅程；实验使用独立进度。" if result.get("ok",false) else str(result.get("errors",[]))))
	var opened:Dictionary=natural_coast_entry_controller.open(self,playtest,status_,viewport,_river_entry_ui_snapshot,recipe)
	if not opened.get("ok",false):set_status("实验未打开："+str(opened.get("errors",[])))

func _api_settings_open() -> bool:
	return not _api_input_snapshot.is_empty() or (is_instance_valid(runtime_connection_panel) and is_instance_valid(runtime_connection_panel.settings_dialog) and runtime_connection_panel.settings_dialog.visible)

func _on_api_modal_visibility(open: bool) -> void:
	if open:
		if not _api_input_snapshot.is_empty(): return
		_enemy_dispatch_generation+=1
		_api_input_snapshot = {"board": board}
		if is_instance_valid(board):
			_api_input_snapshot.merge({"input": board.is_processing_input(), "unhandled": board.is_processing_unhandled_input(), "keys": board.is_processing_unhandled_key_input()})
			board.set_process_input(false); board.set_process_unhandled_input(false); board.set_process_unhandled_key_input(false)
			for field in ["orbit_dragging", "dragging", "panning"]:
				if field in board: board.set(field, false)
	else: _restore_api_input()

func _restore_api_input() -> void:
	# Consume the closing Enter/Escape/click before allowing background input.
	await get_tree().process_frame
	if is_instance_valid(runtime_connection_panel) and is_instance_valid(runtime_connection_panel.settings_dialog) and runtime_connection_panel.settings_dialog.visible: return
	var previous: Variant = _api_input_snapshot.get("board")
	if is_instance_valid(previous) and previous == board:
		previous.set_process_input(bool(_api_input_snapshot.get("input", false)))
		previous.set_process_unhandled_input(bool(_api_input_snapshot.get("unhandled", false)))
		previous.set_process_unhandled_key_input(bool(_api_input_snapshot.get("keys", false)))
	_api_input_snapshot.clear()



func _queue_required_enemy_turn()->void:
	if _api_settings_open() or process_mode==Node.PROCESS_MODE_DISABLED or not _waiting_enemy_phase() or not is_instance_valid(runtime_ai):return
	if actor_action_mode and playtest.decision_pending():return
	var runtime_epoch:Variant=runtime_ai.get("_epoch")
	if not ActorEntryView.C.integer(runtime_epoch):return
	var state:Dictionary=playtest.state_copy()
	_enemy_dispatch_generation+=1
	var ticket:Dictionary={"generation":_enemy_dispatch_generation,"mode_epoch":_mode_epoch,"runtime_epoch":runtime_epoch,"view_instance":str(playtest.get_instance_id()),"engine_instance":str(playtest.engine.get_instance_id()),"world_id":str(state.get("world_id","")),"state_version":state.get("state_version"),"turn_hash":ActorEntryView.C.digest(state.get("combat_turn",{}))}
	if not ActorEntryView.C.safe(ticket):return
	_dispatch_required_enemy_turn.call_deferred(weakref(playtest),ticket)

func _dispatch_required_enemy_turn(receiver_ref:WeakRef,ticket:Dictionary)->void:
	if not ActorEntryView.C.exact_fields(ticket,["generation","mode_epoch","runtime_epoch","view_instance","engine_instance","world_id","state_version","turn_hash"]) or not ActorEntryView.C.safe(ticket):return
	for field in ["generation","mode_epoch","runtime_epoch","state_version"]:
		if not ActorEntryView.C.integer(ticket[field]):return
	for field in ["view_instance","engine_instance","world_id","turn_hash"]:
		if not ticket[field] is String:return
	if ticket.generation!=_enemy_dispatch_generation:return
	# Consume even a dropped callback. Returning from a guest cannot replay it.
	_enemy_dispatch_generation+=1
	if _api_settings_open() or process_mode==Node.PROCESS_MODE_DISABLED or not is_instance_valid(runtime_ai) or receiver_ref==null:return
	var receiver:RefCounted=receiver_ref.get_ref()
	if receiver==null or receiver!=playtest or _mode_epoch!=ticket.mode_epoch or runtime_ai.get("_epoch")!=ticket.runtime_epoch:return
	if str(playtest.get_instance_id())!=ticket.view_instance or str(playtest.engine.get_instance_id())!=ticket.engine_instance or not _waiting_enemy_phase():return
	var state:Dictionary=playtest.state_copy()
	if state.get("world_id")!=ticket.world_id or state.get("state_version")!=ticket.state_version or ActorEntryView.C.digest(state.get("combat_turn",{}))!=ticket.turn_hash:return
	_begin_required_enemy_turn()
