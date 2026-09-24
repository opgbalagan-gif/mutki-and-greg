class_name ArenaSuperAttack
extends Node2D

signal impact(side: int)
signal finished

# Shared fixed canvas and floor pivot; transparent padding is packed losslessly.
const CANVAS_SIZE := Vector2(1024, 576)
const FLOOR_PIVOT := Vector2(512, 862.0 * 576.0 / 941.0)
const DISPLAY_SCALE := 1672.0 / (2560.0 * 2.3525 * 0.4)
const PROFILES := {
	"mutki": {"fps": 18.0, "hits": [8, 17]},
	"greg": {"fps": 18.0, "hits": [7, 10]},
}

var sprite := AnimatedSprite2D.new()
var playing := false
var fighter_id := ""
var facing := 1
var _next_hit := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 8
	add_child(sprite)
	sprite.position = (CANVAS_SIZE * 0.5 - FLOOR_PIVOT) * DISPLAY_SCALE
	sprite.scale = Vector2.ONE * DISPLAY_SCALE
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	hide()


func get_visual_rect() -> Rect2:
	return Rect2(-FLOOR_PIVOT * DISPLAY_SCALE, CANVAS_SIZE * DISPLAY_SCALE)


func start(hero: String, floor_position: Vector2, direction: int = 1) -> void:
	if fighter_id != hero:
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var directory := "res://assets/characters/%s/super_gameplay" % hero
		AnimationLibraryBuilder.add_animation(frames, "super", AnimationLibraryBuilder.png_paths(directory), float(PROFILES[hero].fps), false)
		sprite.sprite_frames = frames
		fighter_id = hero
	if sprite.sprite_frames.get_frame_count("super") == 0:
		push_error("Missing gameplay super frames: " + hero)
		finished.emit.call_deferred()
		return
	position = floor_position
	facing = -1 if direction < 0 else 1
	sprite.flip_h = facing < 0
	_next_hit = 0
	playing = true
	show()
	sprite.stop()
	sprite.play("super")


func _on_frame_changed() -> void:
	if not playing:
		return
	var hits: Array = PROFILES[fighter_id].hits
	while _next_hit < hits.size() and sprite.frame >= int(hits[_next_hit]):
		var side := facing if _next_hit == 0 else -facing
		_next_hit += 1
		impact.emit(side)


func _on_animation_finished() -> void:
	if not playing:
		return
	cancel()
	finished.emit()


func cancel() -> void:
	playing = false
	sprite.stop()
	hide()


func set_suspended(value: bool) -> void:
	if not playing:
		return
	if value:
		sprite.pause()
	else:
		sprite.play()
