class_name AssistButton
extends Button

var charge := 0.0:
	set(value):
		charge = clampf(value, 0.0, 100.0)
		disabled = charge < 100.0
		queue_redraw()
var portrait: AtlasTexture:
	set(value):
		portrait = value
		queue_redraw()
var accent := Color("68edff")
var ready_caption := "ПОЗВАТЬ"


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 10.0
	draw_circle(center, radius + 10.0, Color("111b24"))
	if portrait != null:
		var vertices := PackedVector2Array()
		var uvs := PackedVector2Array()
		for index in 64:
			var unit := Vector2.from_angle(float(index) * TAU / 64.0)
			vertices.append(center + unit * radius)
			uvs.append((portrait.region.position + (unit + Vector2.ONE) * 0.5 * portrait.region.size) / portrait.atlas.get_size())
		draw_colored_polygon(vertices, Color.WHITE, uvs, portrait.atlas)
	draw_arc(center, radius + 5.0, -PI * 0.5, PI * 1.5, 72, Color("45545e"), 6.0, true)
	if charge > 0.0:
		draw_arc(center, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * charge / 100.0, 72, accent, 6.0, true)
	if not disabled and (is_hovered() or has_focus()):
		draw_arc(center, radius + 10.0, 0.0, TAU, 72, Color.WHITE, 2.0, true)
	var label := ready_caption if charge >= 100.0 else "%d%%" % roundi(charge)
	var font := get_theme_default_font()
	var label_size := 16
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	draw_style_box(_label_style(), Rect2(center.x - 42, center.y + 21, 84, 24))
	draw_string(font, Vector2(center.x - text_width * 0.5, center.y + 39), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color.WHITE)


func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b24")
	style.set_corner_radius_all(10)
	return style
