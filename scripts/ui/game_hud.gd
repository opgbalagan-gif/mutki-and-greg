class_name GameHUD
extends CanvasLayer

signal super_pressed
signal retry_pressed
signal character_selected(fighter_id: String)
signal story_finished
signal exit_pressed

const CHARACTER_SELECT_ART := "res://assets/style/character_select.png"

@onready var hp_bar: ProgressBar = $Root/TopPanel/HPBar
@onready var hp_label: Label = $Root/TopPanel/HPLabel
@onready var top_panel: Panel = $Root/TopPanel
@onready var greg_health_bar: GregHealthBar = $Root/GregHealthBar
@onready var wave_label: Label = $Root/TopPanel/WaveLabel
@onready var score_label: Label = $Root/TopPanel/ScoreLabel
@onready var combo_label: Label = $Root/ComboLabel
@onready var super_bar: ProgressBar = $Root/BottomPanel/SuperBar
@onready var super_button: Button = $Root/BottomPanel/SuperButton
@onready var super_title_label: Label = $Root/BottomPanel/SuperTitle
@onready var fighter_portrait: TextureRect = $Root/BottomPanel/GregPortrait
@onready var debug_label: Label = $Root/DebugPanel/DebugLabel
@onready var debug_panel: Panel = $Root/DebugPanel
@onready var message_panel: Panel = $Root/MessagePanel
@onready var message_label: Label = $Root/MessagePanel/MessageLabel
@onready var character_select: Control = $Root/CharacterSelect
var fighter_name := "МУТКИ"
var special_name := "ПОМОЩЬ ГРИШИ"
var current_fighter_id := ""
var story_panel: StoryPanel
var mission_panel: Panel
var objective_label: Label
var progress_label: Label
var exit_button: Button
var direction_hint: Label
var result_backdrop: ColorRect
var _chain_view: Control
var _score_digits: GraffitiNumber
var _chain_digits: GraffitiNumber
var _chain_caption: Label
var _chain_timer: ProgressBar
var _chain_tween: Tween
var _objective_tween: Tween
var _health_name: Label
var coop_menu: Control
var _player_tags: Dictionary = {}


func _ready() -> void:
	super_button.pressed.connect(func(): super_pressed.emit())
	$Root/MessagePanel/RetryButton.pressed.connect(func(): retry_pressed.emit())
	$Root/CharacterSelect/MenuPanel/MutkiButton.pressed.connect(
		func(): character_selected.emit("mutki")
	)
	$Root/CharacterSelect/MenuPanel/GregButton.pressed.connect(
		func(): character_selected.emit("greg")
	)
	set_super(0.0)
	_apply_reference_style($Root)
	_build_reference_menu()
	_build_mission_ui()
	_build_compact_combat_hud()
	story_panel = StoryPanel.new()
	$Root.add_child(story_panel)
	story_panel.finished.connect(func(): story_finished.emit())


func show_character_select() -> void:
	character_select.visible = true
	$Root/TopPanel.visible = false
	greg_health_bar.visible = false
	$Root/BottomPanel.visible = false
	mission_panel.visible = false
	direction_hint.visible = false
	_chain_view.visible = false


func _input(event: InputEvent) -> void:
	if coop_menu != null and coop_menu.visible:
		return
	if not character_select.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var greg_button: Button = $Root/CharacterSelect/MenuPanel/GregButton
	var mutki_button: Button = $Root/CharacterSelect/MenuPanel/MutkiButton
	match event.keycode:
		KEY_LEFT, KEY_A:
			greg_button.grab_focus()
		KEY_RIGHT, KEY_D:
			mutki_button.grab_focus()
		KEY_TAB:
			if greg_button.has_focus():
				mutki_button.grab_focus()
			else:
				greg_button.grab_focus()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			character_selected.emit("mutki" if mutki_button.has_focus() else "greg")
		_:
			return
	get_viewport().set_input_as_handled()


func configure_fighter(fighter_id: String, display_name: String, _attack_count: int) -> void:
	current_fighter_id = fighter_id
	fighter_name = display_name
	special_name = "ПОМОЩЬ МУТКИ" if fighter_id == "greg" else "ПОМОЩЬ ГРИШИ"
	character_select.visible = false
	$Root/TopPanel.visible = true
	$Root/BottomPanel.visible = true
	hp_bar.visible = true
	hp_label.visible = true
	greg_health_bar.visible = false
	_health_name.text = fighter_name
	super_title_label.text = special_name
	var portrait := AtlasTexture.new()
	portrait.atlas = load(MissionData.CANONICAL_ART) as Texture2D
	portrait.region = Rect2(410, 85, 300, 340) if fighter_id == "greg" else Rect2(95, 70, 320, 325)
	fighter_portrait.texture = portrait
	(super_button as AssistButton).portrait = portrait
	(super_button as AssistButton).accent = Color("ce70ff") if fighter_id == "greg" else Color("68edff")
	super_button.tooltip_text = special_name
	set_super(0.0)


func set_hp(current: int, maximum: int) -> void:
	if current_fighter_id == "greg":
		greg_health_bar.set_health(float(current), float(maximum))
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "%d / %d" % [current, maximum]


func set_wave(value: int, _wave_size: int) -> void:
	wave_label.text = "ВОЛНА %d / %d" % [value, MissionData.WAVE_COUNT]


func set_score(value: int) -> void:
	score_label.text = "СЧЁТ"
	_score_digits.text = _number(value)


func set_combo(value: int) -> void:
	combo_label.visible = value > 1
	if value == 0 and _chain_view != null:
		_chain_view.visible = false


func set_super(value: float) -> void:
	super_bar.value = value
	super_button.disabled = value < 100.0
	if super_button is AssistButton:
		(super_button as AssistButton).charge = value
	super_title_label.text = special_name


func set_debug_visible(value: bool) -> void:
	debug_panel.visible = value


func set_debug_text(value: String) -> void:
	debug_label.text = value


func show_game_over(score: int) -> void:
	result_backdrop.visible = true
	message_panel.visible = true
	message_label.text = "МИССИЯ НЕ ПРОЙДЕНА\n\nКапела всё ещё уносит ваши роялти.\nПопробуй снова.\n\nОЧКИ  %07d" % score
	exit_button.visible = false
	direction_hint.visible = false
	$Root/BottomPanel.visible = false


func hide_message() -> void:
	message_panel.visible = false
	result_backdrop.visible = false


func show_story(cards: Array, skippable: bool = true) -> void:
	mission_panel.visible = false
	direction_hint.visible = false
	_chain_view.visible = false
	story_panel.show_slides(cards, skippable)


func set_mission_objective(text: String) -> void:
	if _objective_tween != null:
		_objective_tween.kill()
	mission_panel.visible = true
	mission_panel.modulate.a = 1.0
	objective_label.text = text
	direction_hint.visible = false
	_objective_tween = create_tween()
	_objective_tween.tween_interval(2.2)
	_objective_tween.tween_property(mission_panel, "modulate:a", 0.0, 0.4)
	_objective_tween.tween_callback(mission_panel.hide)


func set_mission_progress(defeated: int, total: int) -> void:
	progress_label.text = "ПОБЕЖДЕНО %d / %d" % [defeated, total]


func show_exit() -> void:
	set_mission_objective("Проход открыт. Осмотри его и найди след.")
	exit_button.visible = true
	exit_button.grab_focus()
	direction_hint.visible = false
	$Root/BottomPanel.visible = false


func hide_exit() -> void:
	exit_button.visible = false
	exit_button.release_focus()


func show_mission_complete(score: int, health_percent: int, elapsed: float) -> void:
	result_backdrop.visible = true
	message_panel.visible = true
	mission_panel.visible = false
	direction_hint.visible = false
	$Root/BottomPanel.visible = false
	var challenge := "ИСПЫТАНИЕ ВЫПОЛНЕНО" if health_percent >= 50 else "ИСПЫТАНИЕ: НУЖНО 50% HP"
	message_label.text = "МИССИЯ 01 ПРОЙДЕНА\n\nЗасада пройдена.\nПогоня за Капелой продолжается…\n\n%s\nЗдоровье: %d%% · Время: %d:%02d\nОЧКИ  %07d" % [challenge, health_percent, int(elapsed) / 60, int(elapsed) % 60, score]
	$Root/MessagePanel/RetryButton.text = "ПРОЙТИ ЕЩЁ РАЗ"
	$Root/MessagePanel/RetryButton.grab_focus()


func _apply_reference_style(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", StoryPanel.INK)
		node.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	if node is Panel or node is Button or node is ProgressBar:
		var names: Array = ["panel"] if node is Panel else (["normal", "hover", "pressed", "disabled", "focus"] if node is Button else ["background", "fill"])
		for style_name: String in names:
			var style := StyleBoxFlat.new()
			style.bg_color = StoryPanel.PAPER
			if style_name in ["hover", "pressed", "fill"]:
				style.bg_color = StoryPanel.TEAL
			elif style_name in ["disabled", "background"]:
				style.bg_color = StoryPanel.MUTED
			style.border_color = StoryPanel.INK
			style.set_border_width_all(2)
			style.set_corner_radius_all(9)
			node.add_theme_stylebox_override(style_name, style)
		if node is Button:
			for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
				node.add_theme_color_override(state_name, StoryPanel.INK)
	for child in node.get_children():
		_apply_reference_style(child)


static func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += " "
		result += digits[index]
	return result


func set_skill_chain(points: int, multiplier: float, hits: int, time_ratio: float) -> void:
	if _chain_tween != null:
		_chain_tween.kill()
		_chain_tween = null
	_chain_view.visible = points > 0
	_chain_view.modulate.a = 1.0
	combo_label.visible = false
	_chain_digits.visible = true
	_chain_digits.text = "%s × %s" % [_number(points), String.num(multiplier, 1).replace(".", ",")]
	_chain_caption.text = "СЕРИЯ УДАРОВ · %d" % hits if hits > 0 else "ПОМОЩЬ НАПАРНИКА"
	_chain_timer.visible = true
	_chain_timer.value = time_ratio * 100.0


func show_chain_result(value: int, lost: bool = false) -> void:
	if _chain_tween != null:
		_chain_tween.kill()
	_chain_view.visible = true
	_chain_view.modulate.a = 1.0
	combo_label.visible = lost
	combo_label.text = "ЦЕПОЧКА ПРЕРВАНА" if lost else ""
	combo_label.add_theme_color_override("font_color", Color("ffab91"))
	_chain_digits.visible = not lost
	_chain_digits.text = "+ " + _number(value)
	_chain_caption.text = "ПОЛУЧЕН УРОН" if lost else "ОЧКИ ЗАСЧИТАНЫ"
	_chain_timer.visible = false
	_chain_tween = create_tween()
	_chain_tween.tween_interval(1.1)
	_chain_tween.tween_property(_chain_view, "modulate:a", 0.0, 0.3)
	_chain_tween.tween_callback(_chain_view.hide)


func _floating_label(label: Label, font_size: int, tint: Color = Color.WHITE) -> void:
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0.03, 0.05, 0.07, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", font_size)


func _build_compact_combat_hud() -> void:
	top_panel.position = Vector2.ZERO
	top_panel.size = Vector2(720, 78)
	top_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	wave_label.position = Vector2(24, 20)
	wave_label.size = Vector2(300, 28)
	_floating_label(wave_label, 20)
	score_label.position = Vector2(340, 6)
	score_label.size = Vector2(348, 20)
	score_label.text = "СЧЁТ"
	_floating_label(score_label, 14)
	_score_digits = GraffitiNumber.new()
	_score_digits.name = "ScoreDigits"
	_score_digits.position = Vector2(340, 24)
	_score_digits.size = Vector2(356, 56)
	top_panel.add_child(_score_digits)
	progress_label.reparent(top_panel)
	progress_label.position = Vector2(24, 50)
	progress_label.size = Vector2(300, 24)
	_floating_label(progress_label, 15)
	mission_panel.position = Vector2(20, 190)
	mission_panel.size = Vector2(680, 40)
	mission_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	objective_label.position = Vector2.ZERO
	objective_label.size = Vector2(680, 40)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_label(objective_label, 20)
	_chain_view = Control.new()
	_chain_view.name = "SkillChain"
	_chain_view.position = Vector2(40, 84)
	_chain_view.size = Vector2(640, 94)
	_chain_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_chain_view)
	combo_label.reparent(_chain_view)
	combo_label.position = Vector2.ZERO
	combo_label.size = Vector2(640, 52)
	_floating_label(combo_label, 42, Color("ffe38b"))
	_chain_digits = GraffitiNumber.new()
	_chain_digits.name = "ChainDigits"
	_chain_digits.digit_height = 60.0
	_chain_digits.alignment = 1
	_chain_digits.size = Vector2(640, 60)
	_chain_view.add_child(_chain_digits)
	combo_label.hide()
	_chain_caption = Label.new()
	_chain_caption.position = Vector2(0, 58)
	_chain_caption.size = Vector2(640, 22)
	_chain_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_label(_chain_caption, 16)
	_chain_view.add_child(_chain_caption)
	_chain_timer = ProgressBar.new()
	_chain_timer.position = Vector2(200, 87)
	_chain_timer.size = Vector2(240, 3)
	_chain_timer.show_percentage = false
	_chain_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var timer_fill := StyleBoxFlat.new()
	timer_fill.bg_color = Color("ffe38b")
	var timer_back := StyleBoxFlat.new()
	timer_back.bg_color = Color(0.05, 0.08, 0.1, 0.45)
	_chain_timer.add_theme_stylebox_override("fill", timer_fill)
	_chain_timer.add_theme_stylebox_override("background", timer_back)
	_chain_view.add_child(_chain_timer)
	_chain_timer.size = Vector2(240, 3)
	_chain_view.visible = false
	var bottom: Panel = $Root/BottomPanel
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	super_bar.hide()
	fighter_portrait.hide()
	$Root/BottomPanel/Hint.hide()
	super_button.queue_free()
	var assist := AssistButton.new()
	assist.name = "AssistButton"
	assist.position = Vector2(148, 1128)
	assist.size = Vector2(112, 112)
	bottom.add_child(assist)
	assist.pressed.connect(func(): super_pressed.emit())
	super_button = assist
	var health := Panel.new()
	health.name = "AttachedHealth"
	health.position = Vector2(245, 1145)
	health.size = Vector2(332, 78)
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = Color(0.045, 0.075, 0.10, 0.9)
	health_style.set_corner_radius_all(18)
	health.add_theme_stylebox_override("panel", health_style)
	bottom.add_child(health)
	bottom.move_child(assist, bottom.get_child_count() - 1)
	_health_name = Label.new()
	_health_name.position = Vector2(22, 10)
	_health_name.size = Vector2(190, 26)
	_floating_label(_health_name, 18)
	health.add_child(_health_name)
	hp_label.reparent(health)
	hp_label.text = "100 / 100"
	_floating_label(hp_label, 17)
	hp_label.position = Vector2(218, 10)
	hp_label.size = Vector2(96, 26)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_bar.reparent(health)
	hp_bar.position = Vector2(22, 45)
	hp_bar.size = Vector2(292, 13)
	var hp_back := StyleBoxFlat.new()
	hp_back.bg_color = Color("354751")
	hp_back.set_corner_radius_all(6)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("78d9b2")
	hp_fill.set_corner_radius_all(6)
	hp_bar.add_theme_stylebox_override("background", hp_back)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	super_title_label.position = Vector2(148, 1098)
	super_title_label.size = Vector2(430, 26)
	super_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_label(super_title_label, 17)
	direction_hint.hide()


func _build_reference_menu() -> void:
	$Root/CharacterSelect/Dim.color = Color("080e15")
	var menu: Panel = $Root/CharacterSelect/MenuPanel
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	for child: Control in menu.get_children():
		child.visible = false
	var reference := TextureRect.new()
	reference.name = "SelectionArtwork"
	reference.texture = load(CHARACTER_SELECT_ART) as Texture2D
	reference.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reference.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reference.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(reference)
	menu.move_child(reference, 0)
	reference.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for fighter_id in ["Greg", "Mutki"]:
		var button: Button = menu.get_node(fighter_id + "Button")
		button.visible = true
		button.text = "ГРИША" if fighter_id == "Greg" else "МУТКИ"
		button.tooltip_text = "Играть за Гришу" if fighter_id == "Greg" else "Играть за Мутки"
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
			button.add_theme_color_override(state, Color.TRANSPARENT)
		var glow := Panel.new()
		glow.name = fighter_id + "Highlight"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var accent := Color("68edff") if fighter_id == "Greg" else Color("ce70ff")
		var highlight := StyleBoxFlat.new()
		highlight.bg_color = Color(accent, 0.12)
		highlight.border_color = Color(accent, 0.95)
		highlight.set_border_width_all(2)
		highlight.set_corner_radius_all(24)
		highlight.shadow_color = Color(accent, 0.5)
		highlight.shadow_size = 14
		glow.add_theme_stylebox_override("panel", highlight)
		glow.visible = false
		menu.add_child(glow)
		for event in [button.mouse_entered, button.mouse_exited, button.focus_entered, button.focus_exited]:
			event.connect(_update_selection_highlight.bind(button, glow))
		var other := NodePath("../MutkiButton" if fighter_id == "Greg" else "../GregButton")
		var player_tag := Label.new()
		player_tag.name = fighter_id + "PlayerTag"
		player_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		player_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		player_tag.add_theme_font_size_override("font_size", 38)
		player_tag.add_theme_color_override("font_color", accent)
		player_tag.add_theme_color_override("font_outline_color", Color("080e15"))
		player_tag.add_theme_constant_override("outline_size", 10)
		player_tag.visible = false
		menu.add_child(player_tag)
		_player_tags[fighter_id.to_lower()] = player_tag
		button.focus_neighbor_left = other
		button.focus_neighbor_right = other
		button.focus_next = other
		button.focus_previous = other
	menu.resized.connect(_layout_character_select.bind(menu, reference))
	_layout_character_select(menu, reference)


func _update_selection_highlight(button: Button, glow: Panel) -> void:
	glow.visible = button.is_hovered() or button.has_focus()


func _layout_character_select(menu: Control, reference: TextureRect) -> void:
	# Keep hit areas aligned with the actual image, including any letterboxing.
	var art_size := reference.texture.get_size()
	var fit := minf(menu.size.x / art_size.x, menu.size.y / art_size.y)
	var displayed := art_size * fit
	var origin := (menu.size - displayed) * 0.5
	for index in 2:
		var fighter_id := "Greg" if index == 0 else "Mutki"
		var button: Button = menu.get_node(fighter_id + "Button")
		button.position = origin + displayed * Vector2(index * 0.5, 0.17)
		button.size = displayed * Vector2(0.5, 0.755)
		var glow: Panel = menu.get_node(fighter_id + "Highlight")
		glow.position = origin + displayed * Vector2(0.048 if index == 0 else 0.526, 0.829)
		glow.size = displayed * Vector2(0.425, 0.084)
		var tag: Label = _player_tags[fighter_id.to_lower()]
		tag.position = origin + displayed * Vector2(0.048 if index == 0 else 0.526, 0.776)
		tag.size = displayed * Vector2(0.425, 0.052)


func set_coop_selection(host_hero: String = "", guest_hero: String = "", local_is_host: bool = true) -> void:
	for id: String in _player_tags:
		var tag: Label = _player_tags[id]
		tag.text = "P1" if id == host_hero else ("P2" if id == guest_hero else "")
		tag.visible = not tag.text.is_empty()
		var button: Button = character_select.get_node("MenuPanel/" + id.capitalize() + "Button")
		button.disabled = id == (guest_hero if local_is_host else host_hero)


func _build_mission_ui() -> void:
	mission_panel = Panel.new()
	mission_panel.position = Vector2(22, 218)
	mission_panel.size = Vector2(676, 138)
	mission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(mission_panel)
	objective_label = Label.new()
	objective_label.position = Vector2(18, 12)
	objective_label.size = Vector2(640, 60)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_font_size_override("font_size", 28)
	mission_panel.add_child(objective_label)
	progress_label = Label.new()
	progress_label.position = Vector2(18, 91)
	progress_label.add_theme_font_size_override("font_size", 18)
	mission_panel.add_child(progress_label)
	exit_button = Button.new()
	exit_button.text = "ОСМОТРЕТЬ ПРОХОД"
	exit_button.position = Vector2(95, 890)
	exit_button.size = Vector2(530, 94)
	exit_button.add_theme_font_size_override("font_size", 28)
	$Root.add_child(exit_button)
	exit_button.visible = false
	exit_button.pressed.connect(func(): exit_pressed.emit())
	direction_hint = Label.new()
	direction_hint.text = "УДАР СЛЕВА        УДАР СПРАВА"
	direction_hint.position = Vector2(45, 1010)
	direction_hint.size = Vector2(630, 40)
	direction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	direction_hint.add_theme_font_size_override("font_size", 23)
	$Root.add_child(direction_hint)
	_apply_reference_style(mission_panel)
	_apply_reference_style(exit_button)
	direction_hint.add_theme_color_override("font_color", StoryPanel.PAPER)
	direction_hint.add_theme_color_override("font_shadow_color", StoryPanel.INK)
	direction_hint.add_theme_constant_override("shadow_offset_x", 2)
	direction_hint.add_theme_constant_override("shadow_offset_y", 2)
	message_panel.position = Vector2(40, 565)
	result_backdrop = ColorRect.new()
	result_backdrop.color = StoryPanel.PAPER
	result_backdrop.z_index = 24
	result_backdrop.visible = false
	$Root.add_child(result_backdrop)
	result_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var result_chapter := Label.new()
	result_chapter.text = "ЭКСПЕДИЦИЯ · " + MissionData.TITLE
	result_chapter.position = Vector2(40, 25)
	result_chapter.size = Vector2(640, 40)
	result_chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_chapter.add_theme_font_size_override("font_size", 21)
	result_chapter.add_theme_color_override("font_color", StoryPanel.ACCENT)
	result_backdrop.add_child(result_chapter)
	var result_art := TextureRect.new()
	result_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result_art.texture = load(MissionData.TITLE_ART) as Texture2D
	result_art.position = Vector2(120, 70)
	result_art.size = Vector2(480, 473)
	result_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_backdrop.add_child(result_art)
	message_panel.z_index = 25
	message_panel.size = Vector2(640, 650)
	message_label.position = Vector2(24, 25)
	message_label.size = Vector2(592, 445)
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Root/MessagePanel/RetryButton.position = Vector2(45, 525)
	$Root/MessagePanel/RetryButton.size = Vector2(550, 85)
