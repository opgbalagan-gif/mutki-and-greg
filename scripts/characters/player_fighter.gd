class_name PlayerFighter
extends Node2D

const GREG_HIT_STUN_SECONDS := 0.18

signal attack_landed(enemy: Node, damage: int)
signal hp_changed(current_hp: int, max_hp: int)
signal damaged(amount: int)
signal died

@export_enum("mutki", "greg") var fighter_id := "mutki"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox

var hp := 1
var state := "inactive"
var debug_draw_enabled := false
var player_enabled := false
var _active_window := false
var _hit_ids: Dictionary = {}
var _attack_cursor := -1
var _attack_profile: Dictionary = {}


func _ready() -> void:
	sprite.sprite_frames = AnimationLibraryBuilder.build_fighter(fighter_id)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	hit_box.monitoring = false
	hurt_box.set_meta("fighter", self)
	hurt_box.set_deferred("monitorable", false)
	hp = int(_fighter_config().max_hp)
	visible = false
	_play_idle()


func activate_player() -> void:
	player_enabled = true
	visible = true
	state = "idle"
	hp = int(_fighter_config().max_hp)
	sprite.modulate = Color.WHITE
	hurt_box.set_deferred("monitorable", true)
	_play_idle()
	hp_changed.emit(hp, int(_fighter_config().max_hp))


func deactivate_player() -> void:
	player_enabled = false
	state = "inactive"
	_deactivate_hit_box()
	hurt_box.set_deferred("monitorable", false)
	visible = false


func try_attack(requested_index: int = -1) -> bool:
	if not player_enabled or state != "idle":
		return false
	var attacks: Array = _fighter_config().attacks
	if attacks.is_empty():
		return false
	if requested_index >= 0:
		_attack_cursor = clampi(requested_index, 0, attacks.size() - 1)
	else:
		_attack_cursor = (_attack_cursor + 1) % attacks.size()
	_attack_profile = attacks[_attack_cursor]
	state = String(_attack_profile.animation)
	_active_window = false
	_hit_ids.clear()
	hit_box.monitoring = false
	_play_video_attack(state)
	return true


func take_damage(amount: int) -> bool:
	if not player_enabled or state == "dead":
		return false
	if fighter_id == "greg" and (state.begins_with("attack_") or state == "special"):
		return false
	_deactivate_hit_box()
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, int(_fighter_config().max_hp))
	damaged.emit(amount)
	if hp <= 0:
		state = "dead"
		hurt_box.set_deferred("monitorable", false)
		if fighter_id == "greg":
			_play_video_attack("death_video")
		else:
			sprite.stop()
			sprite.modulate = Color(0.55, 0.55, 0.55, 1.0)
		died.emit()
	else:
		state = "hit"
		if fighter_id == "greg":
			_finish_greg_hit_stun.call_deferred()
		else:
			_play_standard("hit")
	return true


func _finish_greg_hit_stun() -> void:
	await get_tree().create_timer(GREG_HIT_STUN_SECONDS).timeout
	if player_enabled and state == "hit":
		state = "idle"


func heal(amount: int) -> bool:
	if not player_enabled or state == "dead" or amount <= 0:
		return false
	var maximum := int(_fighter_config().max_hp)
	var healed_hp := mini(maximum, hp + amount)
	if healed_hp == hp:
		return false
	hp = healed_hp
	hp_changed.emit(hp, maximum)
	return true


func _fighter_config() -> Dictionary:
	return GameBalance.FIGHTERS[fighter_id]


func _on_frame_changed() -> void:
	if not state.begins_with("attack_"):
		return
	if sprite.frame == int(_attack_profile.active_frame):
		_activate_hit_box()
	elif _active_window:
		_deactivate_hit_box()


func _activate_hit_box() -> void:
	_active_window = true
	hit_box.monitoring = true
	call_deferred("_scan_current_overlaps")
	queue_redraw()


func _deactivate_hit_box() -> void:
	_active_window = false
	hit_box.set_deferred("monitoring", false)
	queue_redraw()


func _scan_current_overlaps() -> void:
	if not _active_window:
		return
	for area in hit_box.get_overlapping_areas():
		_on_hit_box_area_entered(area)


func _on_hit_box_area_entered(area: Area2D) -> void:
	if not _active_window:
		return
	var enemy := area.get_parent()
	if enemy == null or not enemy.has_method("receive_hit"):
		return
	var config := _fighter_config()
	var hit_distance := float(config.attack_range)
	if fighter_id == "greg" and int(enemy.get("formation_slot")) == 1:
		hit_distance = float(config.get("cleave_range", hit_distance))
	if absf(enemy.global_position.x - global_position.x) > hit_distance:
		return
	var instance_id := enemy.get_instance_id()
	if _hit_ids.has(instance_id):
		return
	_hit_ids[instance_id] = true
	var damage := int(_attack_profile.damage)
	enemy.receive_hit(damage, float(_attack_profile.knockback))
	attack_landed.emit(enemy, damage)


func _on_animation_finished() -> void:
	if state.begins_with("attack_") or state == "hit":
		var completed_state := state
		_deactivate_hit_box()
		if state != "dead" and player_enabled:
			state = "idle"
			var idle_start_frame := 0
			if completed_state.begins_with("attack_"):
				idle_start_frame = int(_fighter_config().get("idle_after_attack_frame", 0))
			elif completed_state == "hit":
				idle_start_frame = int(_fighter_config().get("idle_after_hit_frame", 0))
			_play_idle(idle_start_frame)


func _play_idle(start_frame: int = 0) -> void:
	if fighter_id == "greg":
		_play_video_attack("idle_video")
		var frame_count := sprite.sprite_frames.get_frame_count("idle_video")
		if frame_count > 0:
			sprite.set_frame_and_progress(clampi(start_frame, 0, frame_count - 1), 0.0)
	else:
		_play_standard("idle")


func _play_standard(animation_name: String) -> void:
	var config := _fighter_config()
	sprite.position = config.standard_sprite_position
	sprite.scale = Vector2.ONE * float(config.standard_sprite_scale)
	sprite.play(animation_name)


func _play_video_attack(animation_name: String) -> void:
	var config := _fighter_config()
	sprite.position = config.video_sprite_position
	sprite.scale = Vector2.ONE * float(config.video_sprite_scale)
	sprite.play(animation_name)


func set_debug_draw(value: bool) -> void:
	debug_draw_enabled = value
	queue_redraw()


func _draw() -> void:
	if not debug_draw_enabled or not player_enabled:
		return
	draw_rect(Rect2(-58, -270, 116, 270), Color(0.1, 0.75, 1.0, 0.18), true)
	draw_rect(Rect2(48, -230, float(_fighter_config().attack_range), 190), Color(1.0, 0.25, 0.12, 0.14), true)
	draw_line(Vector2.ZERO, Vector2(float(_fighter_config().attack_range), 0), Color.ORANGE, 3.0)


func debug_status() -> String:
	return "%s: %s | %s #%d | HP %d/%d | hitbox %s" % [
		String(_fighter_config().display_name),
		state,
		sprite.animation,
		sprite.frame,
		hp,
		int(_fighter_config().max_hp),
		"ON" if _active_window else "off",
	]
