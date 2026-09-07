extends Node2D

const COURT_BACKGROUND := preload("res://assets/backgrounds/mission_01_courtyard.png")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(COURT_BACKGROUND, Rect2(0.0, 0.0, 720.0, 1280.0), false)
