class_name StoryPanel
extends Control

signal finished

const INK := Color("26343c")
const PAPER := Color("edf3f5")
const TEAL := Color("83b6be")
const ACCENT := Color("296b7c")
const MUTED := Color("d9e4e9")

var slides: Array = []
var slide_index := 0
var next_button: Button
var back_button: Button
var skip_button: Button
var chapter_label: Label
var title_label: Label
var speaker_label: Label
var body_label: Label
var artwork: TextureRect
var page_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	MenuVisuals.background(self)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	chapter_label = _label(18, MenuVisuals.CYAN)
	column.add_child(chapter_label)
	title_label = _label(38, MenuVisuals.SILVER)
	column.add_child(title_label)
	var art_frame := PanelContainer.new()
	art_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := MenuVisuals.panel_style(MenuVisuals.VIOLET)
	frame_style.content_margin_left = 8
	frame_style.content_margin_right = 8
	frame_style.content_margin_top = 8
	frame_style.content_margin_bottom = 8
	art_frame.add_theme_stylebox_override("panel", frame_style)
	column.add_child(art_frame)
	artwork = TextureRect.new()
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.custom_minimum_size.y = 240
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_child(artwork)
	speaker_label = _label(19, MenuVisuals.VIOLET)
	column.add_child(speaker_label)
	body_label = _label(25, MenuVisuals.SILVER)
	body_label.custom_minimum_size.y = 120
	column.add_child(body_label)
	page_label = _label(18, MenuVisuals.MUTED)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(page_label)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 16)
	column.add_child(navigation)
	back_button = _button("НАЗАД")
	navigation.add_child(back_button)
	back_button.pressed.connect(previous_slide)
	next_button = _button("ДАЛЬШЕ")
	navigation.add_child(next_button)
	next_button.pressed.connect(next_slide)
	skip_button = _button("ПРОПУСТИТЬ ВСТУПЛЕНИЕ")
	skip_button.custom_minimum_size.y = 52
	skip_button.add_theme_font_size_override("font_size", 20)
	MenuVisuals.button(skip_button, MenuVisuals.VIOLET, 19)
	column.add_child(skip_button)
	skip_button.pressed.connect(_finish)
	visible = false


func show_slides(cards: Array, skippable: bool = true) -> void:
	slides = cards
	slide_index = 0
	skip_button.visible = skippable
	if slides.is_empty():
		visible = false
		finished.emit()
		return
	visible = true
	_render_slide()
	next_button.grab_focus()


func next_slide() -> void:
	if not visible:
		return
	if slide_index + 1 >= slides.size():
		_finish()
		return
	slide_index += 1
	_render_slide()


func previous_slide() -> void:
	if not visible or slide_index <= 0:
		return
	slide_index -= 1
	_render_slide()


func _finish() -> void:
	if not visible:
		return
	visible = false
	next_button.release_focus()
	finished.emit()


func _render_slide() -> void:
	var card: Dictionary = slides[slide_index]
	chapter_label.text = String(card.get("chapter", ""))
	title_label.text = String(card.get("title", ""))
	speaker_label.text = String(card.get("speaker", ""))
	body_label.text = String(card.get("text", ""))
	var art_path := String(card.get("art", MissionData.CANONICAL_ART))
	if not ResourceLoader.exists(art_path):
		art_path = MissionData.CANONICAL_ART
	artwork.texture = load(art_path) as Texture2D
	page_label.text = "%02d / %02d" % [slide_index + 1, slides.size()]
	back_button.disabled = slide_index == 0
	next_button.text = "ДАЛЬШЕ" if slide_index + 1 < slides.size() else ("НАЧАТЬ МИССИЮ" if skip_button.visible else "ЗАВЕРШИТЬ")


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	MenuVisuals.label(label, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 78
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuVisuals.button(button, MenuVisuals.CYAN, 24)
	return button
