class_name CoopLobby
extends Control

signal action_requested(action: String, value: String)

var column: VBoxContainer
var status_label: Label
var room_input: LineEdit
var hero_buttons: Dictionary = {}
var continue_button: Button
var stylish_result: StylishResultPanel
var screen := ""
const BLUE := Color("68edff")
const PURPLE := Color("ce70ff")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuVisuals.background(self)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 38)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	show_modes()


func _clear(next_screen: String) -> void:
	screen = next_screen
	show()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	hero_buttons.clear()
	continue_button = null
	stylish_result = null
	status_label = null
	room_input = null


func _label(caption: String, font_size: int = 26, tint: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuVisuals.label(label, font_size, tint)
	column.add_child(label)
	return label


func _space() -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)


func _art(height: float = 300) -> void:
	var frame := PanelContainer.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", MenuVisuals.panel_style(PURPLE))
	frame.add_child(MenuVisuals.portraits(height))
	column.add_child(frame)


func _button(caption: String, action: String, value: String = "", tint: Color = BLUE) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 86
	MenuVisuals.button(button, tint, 26)
	button.pressed.connect(func(): action_requested.emit(action, room_input.text if action == "join" else value))
	column.add_child(button)
	return button


func show_modes() -> void:
	_clear("modes")
	column.add_child(MenuVisuals.logo())
	_label("ПОГОНЯ ЗА РОЯЛТИ", 20, MenuVisuals.MUTED)
	_art(470)
	_label("КАК ИГРАЕМ?", 34)
	_label("Одна история. Два героя.", 23, MenuVisuals.MUTED)
	_space()
	_button("1 ИГРОК", "solo")
	_button("2 ИГРОКА · ДВА ТЕЛЕФОНА", "online", "", PURPLE)
	_label("Вместе пройдите сюжет.\nНаберите больше очков, чем напарник.", 22, MenuVisuals.MUTED)
	_space()


func show_connect(invite_code: String = "") -> void:
	_clear("connect")
	_label("ИГРА НА ДВОИХ", 42, BLUE)
	_art()
	_label("На первом телефоне создай комнату.\nНа втором введи её код или открой приглашение.", 26)
	_space()
	_button("СОЗДАТЬ КОМНАТУ", "host")
	room_input = LineEdit.new()
	room_input.placeholder_text = "КОД КОМНАТЫ"
	room_input.text = invite_code
	room_input.max_length = 6
	room_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_input.custom_minimum_size.y = 80
	room_input.add_theme_font_size_override("font_size", 34)
	room_input.virtual_keyboard_enabled = true
	MenuVisuals.input(room_input)
	column.add_child(room_input)
	room_input.text_submitted.connect(func(value: String): action_requested.emit("join", value))
	_button("ПОДКЛЮЧИТЬСЯ", "join", "", PURPLE)
	status_label = _label("Оставляйте игру открытой на обоих телефонах.", 22, Color("afc6d5"))
	_space()
	_button("НАЗАД", "menu")


func show_room(code: String) -> void:
	_clear("room")
	_label("КОМНАТА", 26, Color("afc6d5"))
	_label(code, 62, BLUE)
	_button("СКОПИРОВАТЬ ПРИГЛАШЕНИЕ", "copy")
	_art()
	_label("P1 — СОЗДАТЕЛЬ КОМНАТЫ\nP2 — ВТОРОЙ ИГРОК", 28)
	_button("ВЫБРАТЬ ГЕРОЯ", "select")
	status_label = _label("Ждём второй телефон…", 26, Color("afc6d5"))
	_label("Разные герои · Общие враги\nОтдельные очки после каждого раунда", 22)
	_space()
	_button("ВЫЙТИ ИЗ КОМНАТЫ", "menu")


func update_room(local_hero: String, other_hero: String, connected: bool) -> void:
	if screen != "room":
		return
	for id: String in hero_buttons:
		var caption := "ГРИША" if id == "greg" else "МУТКИ"
		hero_buttons[id].text = caption + (" · ТЫ" if id == local_hero else (" · НАПАРНИК" if id == other_hero else ""))
		hero_buttons[id].disabled = id == other_hero
	status_label.text = "Передай приглашение напарнику и выбери героя." if not connected else "Напарник подключён. Выберите разных героев."


func show_results(title: String, round_scores: Dictionary, totals: Dictionary, final_result: bool = false) -> void:
	_clear("final" if final_result else "round")
	var logo := MenuVisuals.logo()
	logo.custom_minimum_size.y = 110
	column.add_child(logo)
	stylish_result = StylishResultPanel.new()
	column.add_child(stylish_result)
	stylish_result.present_duel(round_scores, totals, final_result, title)
	_space()
	continue_button = _button("СЫГРАТЬ ЕЩЁ ВМЕСТЕ" if final_result else "ГОТОВ ПРОДОЛЖАТЬ", "ready")
	status_label = _label("Продолжим, когда оба будут готовы.", 24, Color("afc6d5"))
	_button("В МЕНЮ", "menu")


func show_wait(caption: String) -> void:
	_clear("wait")
	_space()
	_label(caption, 36, BLUE)
	status_label = _label("История продолжится, когда оба будут готовы.", 26)
	_space()
	_button("В МЕНЮ", "menu")


func show_connection_problem(caption: String, terminal: bool = false) -> void:
	_clear("error" if terminal else "paused")
	_space()
	_label("СВЯЗЬ ПРЕРВАНА" if terminal else "ИГРА НА ПАУЗЕ", 40, BLUE)
	status_label = _label(caption, 27)
	_space()
	_button("В МЕНЮ", "menu")


func set_ready_state(local_ready: bool, other_ready: bool) -> void:
	if continue_button != null:
		continue_button.disabled = local_ready
		continue_button.text = "ЖДЁМ НАПАРНИКА…" if local_ready else ("НАПАРНИК ГОТОВ · ПРОДОЛЖИТЬ" if other_ready else "ГОТОВ ПРОДОЛЖАТЬ")


func set_status(caption: String) -> void:
	if status_label != null:
		status_label.text = caption
