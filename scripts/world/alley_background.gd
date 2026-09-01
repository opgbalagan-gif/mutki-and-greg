extends Node2D

const COURT_BACKGROUND := preload("res://assets/backgrounds/court_robot_01.png")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(COURT_BACKGROUND, Rect2(0.0, 0.0, 720.0, 1280.0), false)
	# A light ground shade keeps fighters readable without hiding the new artwork.
	draw_rect(Rect2(0.0, 720.0, 720.0, 330.0), Color(0.04, 0.025, 0.015, 0.08))
