class_name GregHealthBar
extends Control

const MAX_FILL_WIDTH := 930.0
const FILL_HEIGHT := 112.0
const FILL_TWEEN_SECONDS := 0.20
const GREG_CYAN := Color(0.08, 0.79, 0.94, 1.0)

@onready var health_fill: ColorRect = $FillClip/HealthFill
@onready var frame_texture: TextureRect = $FrameTexture

var _health_ratio := 1.0
var _fill_tween: Tween = null
var _feedback_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	health_fill.color = GREG_CYAN
	_set_fill_width(MAX_FILL_WIDTH)


func set_health(current: float, maximum: float) -> void:
	var ratio := clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	var previous_ratio := _health_ratio
	_health_ratio = ratio

	if is_instance_valid(_fill_tween):
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fill_tween.tween_method(
		_set_fill_width,
		health_fill.size.x,
		MAX_FILL_WIDTH * ratio,
		FILL_TWEEN_SECONDS
	)

	if ratio < previous_ratio:
		_play_damage_feedback()
	_update_low_health_pulse(ratio)


func current_ratio() -> float:
	return _health_ratio


func current_fill_width() -> float:
	return health_fill.size.x


func _set_fill_width(value: float) -> void:
	health_fill.position.x = 0.0
	health_fill.size = Vector2(clampf(value, 0.0, MAX_FILL_WIDTH), FILL_HEIGHT)


func _play_damage_feedback() -> void:
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	frame_texture.modulate = Color(1.0, 0.58, 0.58, 1.0)
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(frame_texture, "modulate", Color.WHITE, 0.12)


func _update_low_health_pulse(ratio: float) -> void:
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
		_pulse_tween = null
	health_fill.modulate = Color.WHITE
	if ratio <= 0.0 or ratio > 0.25:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(health_fill, "modulate:a", 0.78, 0.50)
	_pulse_tween.tween_property(health_fill, "modulate:a", 1.0, 0.50)
