class_name GraffitiNumber
extends Control

const GLYPHS := {
	"0": preload("res://assets/ui/graffiti_digits/0.svg"),
	"1": preload("res://assets/ui/graffiti_digits/1.svg"),
	"2": preload("res://assets/ui/graffiti_digits/2.svg"),
	"3": preload("res://assets/ui/graffiti_digits/3.svg"),
	"4": preload("res://assets/ui/graffiti_digits/4.svg"),
	"5": preload("res://assets/ui/graffiti_digits/5.svg"),
	"6": preload("res://assets/ui/graffiti_digits/6.svg"),
	"7": preload("res://assets/ui/graffiti_digits/7.svg"),
	"8": preload("res://assets/ui/graffiti_digits/8.svg"),
	"9": preload("res://assets/ui/graffiti_digits/9.svg"),
	"+": preload("res://assets/ui/graffiti_digits/plus.svg"),
	"×": preload("res://assets/ui/graffiti_digits/multiply.svg"),
	",": preload("res://assets/ui/graffiti_digits/comma.svg"),
	"-": preload("res://assets/ui/graffiti_digits/minus.svg"),
}

@export var text := "0":
	set(value):
		if text != value:
			text = value
			queue_redraw()
@export var digit_height := 56.0:
	set(value):
		digit_height = value
		queue_redraw()
@export_enum("Left", "Center", "Right") var alignment := 2:
	set(value):
		alignment = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)

func _advance(character: String) -> float:
	return 0.25 if character == " " else (0.22 if character == "," else 0.70)

func text_width(height: float) -> float:
	var width := 0.0
	for character in text:
		width += _advance(character) * height
	# Include the last glyph's slant, white outline and extrusion.
	if not text.is_empty():
		width += (156.0 / 174.0 - _advance(text[-1])) * height
	return width

func content_rect() -> Rect2:
	if text.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var height := minf(digit_height, size.y)
	var width := text_width(height)
	if width > size.x:
		height *= size.x / width
		width = text_width(height)
	var x := 0.0 if alignment == 0 else ((size.x - width) * (0.5 if alignment == 1 else 1.0))
	return Rect2(Vector2(x, (size.y - height) * 0.5), Vector2(width, height))

func _draw() -> void:
	var rect := content_rect()
	if rect.size.y <= 0.0:
		return
	var x := rect.position.x
	for character in text:
		if GLYPHS.has(character):
			var offset := -0.18 * rect.size.y if character == "," else 0.0
			draw_texture_rect(GLYPHS[character], Rect2(x + offset, rect.position.y, rect.size.y * 156.0 / 174.0, rect.size.y), false)
		x += _advance(character) * rect.size.y
