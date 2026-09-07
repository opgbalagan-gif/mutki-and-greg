class_name CoopLobby
extends Control

signal action_requested(action: String, value: String)

var column: VBoxContainer
var status_label: Label
var room_input: LineEdit
var hero_buttons: Dictionary = {}
var continue_button: Button
var screen := ""
const BLUE := Color("68edff")
const PURPLE := Color("ce70ff")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("101b25")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 38)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
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
	status_label = null
	room_input = null


func _label(caption: String, font_size: int = 26, tint: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	column.add_child(label)
	return label


func _space() -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)


func _art() -> void:
	var art := TextureRect.new()
	art.texture = load(MissionData.CANONICAL_ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 300
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(art)


func _button(caption: String, action: String, value: String = "", tint: Color = BLUE) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 86
	button.add_theme_font_size_override("font_size", 26)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("243644") if state_name != "pressed" else Color("395669")
		style.border_color = tint if state_name != "disabled" else Color("52616b")
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("92a5b0"))
	button.pressed.connect(func(): action_requested.emit(action, room_input.text if action == "join" else value))
	column.add_child(button)
	return button


func show_modes() -> void:
	_clear("modes")
	_label("ГРИША И МУТКИ", 44, BLUE)
	_art()
	_label("КАК ИГРАЕМ?", 36)
	_label("Одна история. Два героя.", 25, Color("afc6d5"))
	_space()
	_button("1 ИГРОК", "solo")
	_button("2 ИГРОКА · ДВА ТЕЛЕФОНА", "online", "", PURPLE)
	_label("Вместе пройдите сюжет.\nНаберите больше очков, чем напарник.", 24)
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
	_label(title, 38, BLUE)
	_art()
	_label("ГЕРОЙ                 РАУНД         ВСЕГО", 21, Color("afc6d5"))
	_label("ГРИША        +%d        %d" % [round_scores.greg, totals.greg], 34, BLUE)
	_label("МУТКИ        +%d        %d" % [round_scores.mutki, totals.mutki], 34, PURPLE)
	var compared := totals if final_result else round_scores
	var winner := "НИЧЬЯ" if int(compared.greg) == int(compared.mutki) else ("ГРИША" if int(compared.greg) > int(compared.mutki) else "МУТКИ")
	_label(("ПОБЕДИТЕЛЬ: " if final_result and winner != "НИЧЬЯ" else ("ЛУЧШИЙ В РАУНДЕ: " if winner != "НИЧЬЯ" else "")) + winner, 29)
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
