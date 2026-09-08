class_name MutkiArenaAssist
extends Node2D

signal impact
signal finished

const FRAME_DIRECTORY := "res://assets/characters/mutki/assist_super"
const IMPACT_FRAME := 22
# Match Greg's 290px body height. Only the outer quarters of the wave are
# narrowed to fit the arena; the hero and his hands retain this uniform scale.
const SPRITE_SCALE := 290.0 / (636.0 * 1024.0 / 1920.0)
const SPRITE_POSITION := Vector2(0, -(483.2 - 576.0 / 2.0) * SPRITE_SCALE)
const CANVAS_SIZE := Vector2(1024, 576)
const BODY_REGION := Rect2(256, 0, 512, 576)
const WAVE_WIDTH := 672.0 # 24px margins also cover the 18px impact shake.

var sprite := AnimatedSprite2D.new()
var playing := false
var network_replica := false
var _impact_sent := false
var _loaded := false


func _ready() -> void:
	# Only this animation advances while the arena is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 8
	add_child(sprite)
	sprite.position = SPRITE_POSITION
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	# Keep AnimatedSprite2D as the clock, and draw its packed textures in strips.
	# This avoids allocating full transparent canvases on mobile devices.
	sprite.hide()
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	hide()


func get_visual_rect() -> Rect2:
	return Rect2(Vector2(-WAVE_WIDTH / 2.0, -483.2 * SPRITE_SCALE), Vector2(WAVE_WIDTH, CANVAS_SIZE.y * SPRITE_SCALE))


func _draw() -> void:
	if not _loaded:
		return
	var texture := sprite.sprite_frames.get_frame_texture("assist_super", sprite.frame)
	var bounds := get_visual_rect()
	var body_width := BODY_REGION.size.x * SPRITE_SCALE
	var edge_width := (WAVE_WIDTH - body_width) / 2.0
	draw_texture_rect_region(texture, Rect2(bounds.position, Vector2(edge_width, bounds.size.y)), Rect2(0, 0, 256, 576))
	draw_texture_rect_region(texture, Rect2(Vector2(-body_width / 2.0, bounds.position.y), Vector2(body_width, bounds.size.y)), BODY_REGION)
	draw_texture_rect_region(texture, Rect2(Vector2(body_width / 2.0, bounds.position.y), Vector2(edge_width, bounds.size.y)), Rect2(768, 0, 256, 576))


func _ensure_frames() -> void:
	if _loaded:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	AnimationLibraryBuilder.add_animation(frames, "assist_super", AnimationLibraryBuilder.png_paths(FRAME_DIRECTORY), 12.0, false)
	sprite.sprite_frames = frames
	_loaded = true
	queue_redraw()


func start(floor_position: Vector2) -> void:
	_ensure_frames()
	network_replica = false
	position = floor_position
	_impact_sent = false
	playing = true
	show()
	sprite.stop()
	sprite.play("assist_super")


func _on_frame_changed() -> void:
	queue_redraw()
	if playing and not network_replica and sprite.frame >= IMPACT_FRAME and not _impact_sent:
		_impact_sent = true
		impact.emit()


func _on_animation_finished() -> void:
	if not playing or network_replica:
		return
	cancel()
	finished.emit()


func cancel() -> void:
	playing = false
	sprite.stop()
	hide()


func set_suspended(value: bool) -> void:
	if not playing or network_replica:
		return
	if value:
		sprite.pause()
	else:
		sprite.play()


func snapshot() -> Dictionary:
	return {"active": playing, "x": position.x, "y": position.y, "frame": sprite.frame, "progress": sprite.frame_progress}


func apply_snapshot(data: Dictionary) -> void:
	network_replica = true
	if not bool(data.get("active", false)):
		cancel()
		return
	_ensure_frames()
	playing = true
	position = Vector2(float(data.x), float(data.y))
	show()
	sprite.animation = "assist_super"
	sprite.set_frame_and_progress(int(data.frame), float(data.progress))
	# The host alone advances the move and emits its damage event.
	sprite.pause()
