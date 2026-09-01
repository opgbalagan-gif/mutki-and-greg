class_name Greg
extends PlayerFighter

signal super_impact(enemy: Node)
signal super_finished

var busy := false
var _impact_sent := false
var _target: Node = null
var _assist_mode := false


func perform_super(enemy: Node) -> bool:
	if busy or player_enabled or enemy == null or not is_instance_valid(enemy):
		return false
	busy = true
	_assist_mode = true
	_impact_sent = false
	_target = enemy
	state = "special"
	visible = true
	position = Vector2(-130.0, GameBalance.GROUND_Y)
	_play_idle()
	var entrance := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	entrance.tween_property(self, "position:x", 255.0, 0.20)
	await entrance.finished
	if not busy:
		return false
	_play_standard("super")
	return true


func perform_power(enemy: Node) -> bool:
	if busy or not player_enabled or state != "idle" or enemy == null or not is_instance_valid(enemy):
		return false
	busy = true
	_assist_mode = false
	_impact_sent = false
	_target = enemy
	state = "special"
	_deactivate_hit_box()
	_play_standard("super")
	return true


func _on_frame_changed() -> void:
	super._on_frame_changed()
	if state == "special" and sprite.animation == "super" and sprite.frame == 3 and not _impact_sent:
		_impact_sent = true
		if is_instance_valid(_target):
			super_impact.emit(_target)


func _on_animation_finished() -> void:
	if state != "special" or sprite.animation != "super" or not busy:
		super._on_animation_finished()
		return
	if _assist_mode:
		var exit_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(self, "position:x", 820.0, 0.24)
		await exit_tween.finished
		visible = false
		state = "inactive"
	else:
		state = "idle"
		_play_idle()
	busy = false
	_target = null
	super_finished.emit()


func deactivate_player() -> void:
	busy = false
	_target = null
	super.deactivate_player()


func take_damage(amount: int) -> bool:
	var interrupted_special := busy and player_enabled
	var damage_applied := super.take_damage(amount)
	if not damage_applied:
		return false
	if interrupted_special:
		busy = false
		_target = null
		super_finished.emit()
	return true
