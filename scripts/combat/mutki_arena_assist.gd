class_name MutkiArenaAssist
extends Node2D

signal impact
signal finished

const FRAME_DIRECTORY := "res://assets/characters/mutki/assist_super"
const IMPACT_FRAME := 22
const SPRITE_SCALE := 0.8549528301886793
const SPRITE_POSITION := Vector2(0, -166.88679245283018)

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
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	hide()


func _ensure_frames() -> void:
	if _loaded:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	AnimationLibraryBuilder.add_animation(frames, "assist_super", AnimationLibraryBuilder.png_paths(FRAME_DIRECTORY), 12.0, false)
	sprite.sprite_frames = frames
	_loaded = true


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
