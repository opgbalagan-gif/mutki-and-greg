class_name EnemyBase
extends Node2D

signal died(enemy: Node, enemy_id: String)
signal damaged(enemy: Node, current_hp: int, max_hp: int)
signal attack_landed(damage: int)

@export var enemy_id := "enemy_01_thug"
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_box: Area2D = $HitBox
@onready var hurt_box: Area2D = $HurtBox

var config: Dictionary
var hp := 1
var state := "walk"
var target_x := GameBalance.ENEMY_STOP_X
var knockback_velocity := 0.0
var debug_draw_enabled := false
var death_variant := 1
var _attack_active := false
var _attack_committed := false
var _attack_variant := 1
var _current_attack_animation := "attack"
var _death_reported := false
var _can_attack := true
var formation_slot := 0

func _ready() -> void:
	config = GameBalance.ENEMIES.get(enemy_id, GameBalance.ENEMIES.enemy_01_thug)
	hp = int(config.max_hp)
	sprite.sprite_frames = AnimationLibraryBuilder.build_enemy(enemy_id)
	sprite.position = config.get("sprite_position", Vector2(0.0, -202.0))
	sprite.scale = Vector2.ONE * float(config.get("sprite_scale", 1.0))
	# The new ordinary-enemy videos already face toward the player.
	sprite.flip_h = not sprite.sprite_frames.has_animation("attack_01")
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	hit_box.monitoring = false
	hurt_box.set_meta("fighter", self)
	sprite.play("walk")

func _physics_process(delta: float) -> void:
	if state == "walk":
		if position.x > target_x:
			position.x = maxf(target_x, position.x - float(config.speed) * delta)
			if sprite.animation != "walk":
				sprite.play("walk")
		else:
			if _can_attack:
				_begin_attack()
			else:
				state = "queue"
				sprite.play("idle")
	elif state == "hit" or state == "dead":
		if knockback_velocity > 0.1:
			position.x += knockback_velocity * delta
			knockback_velocity = move_toward(knockback_velocity, 0.0, 520.0 * delta)


func set_formation_slot(slot_index: int, stop_x: float) -> void:
	formation_slot = slot_index
	target_x = stop_x
	_can_attack = slot_index == 0
	if state == "dead" or state == "hit":
		return
	if not _can_attack and state in ["startup", "attack", "recovery"]:
		_deactivate_hit_box()
	if position.x > target_x:
		state = "walk"
		if sprite.animation != "walk":
			sprite.play("walk")
	elif _can_attack:
		state = "walk"
	else:
		state = "queue"
		sprite.play("idle")

func _begin_attack() -> void:
	if state != "walk":
		return
	state = "startup"
	_attack_active = false
	sprite.play("idle")
	await get_tree().create_timer(float(config.attack_delay)).timeout
	if state != "startup":
		return
	state = "attack"
	_attack_committed = false
	_current_attack_animation = "attack"
	if sprite.sprite_frames.has_animation("attack_01"):
		_current_attack_animation = "attack_%02d" % _attack_variant
		_attack_variant = 2 if _attack_variant == 1 else 1
	sprite.play(_current_attack_animation)

func receive_hit(amount: int, force: float) -> void:
	if state == "dead":
		return
	_deactivate_hit_box()
	hp = maxi(0, hp - amount)
	knockback_velocity = force * float(config.knockback_resistance)
	damaged.emit(self, hp, int(config.max_hp))
	if hp <= 0:
		state = "dead"
		hurt_box.set_deferred("monitorable", false)
		var death_animation := "death"
		var requested_death := "death_%02d" % clampi(death_variant, 1, 2)
		if sprite.sprite_frames.has_animation(requested_death):
			death_animation = requested_death
		sprite.play(death_animation)
	else:
		state = "hit"
		sprite.play("hit")

func _on_frame_changed() -> void:
	var active_frame := 5 if sprite.animation.begins_with("attack_") else 2
	if (
		state == "attack"
		and sprite.animation == _current_attack_animation
		and sprite.frame == active_frame
		and not _attack_committed
	):
		_attack_committed = true
		_attack_active = true
		hit_box.monitoring = true
		call_deferred("_scan_current_overlaps")
	elif _attack_active:
		_deactivate_hit_box()

func _scan_current_overlaps() -> void:
	if not _attack_active:
		return
	for area in hit_box.get_overlapping_areas():
		_on_hit_box_area_entered(area)

func _on_hit_box_area_entered(area: Area2D) -> void:
	if not _attack_active:
		return
	var fighter: Variant = area.get_meta("fighter", null)
	if fighter == null:
		fighter = area.get_parent()
	if fighter != null and fighter.has_method("take_damage"):
		var damage_applied: Variant = fighter.take_damage(int(config.damage))
		if damage_applied == false:
			_deactivate_hit_box()
			return
		attack_landed.emit(int(config.damage))
		_deactivate_hit_box()

func _deactivate_hit_box() -> void:
	_attack_active = false
	hit_box.set_deferred("monitoring", false)
	queue_redraw()

func _on_animation_finished() -> void:
	if sprite.animation == _current_attack_animation and state == "attack":
		_deactivate_hit_box()
		state = "recovery"
		await get_tree().create_timer(float(config.recovery)).timeout
		if state == "recovery":
			state = "walk"
			sprite.play("walk")
	elif sprite.animation == "hit" and state == "hit":
		state = "walk"
		sprite.play("walk")
	elif sprite.animation.begins_with("death") and state == "dead" and not _death_reported:
		_death_reported = true
		await get_tree().create_timer(0.24).timeout
		died.emit(self, enemy_id)
		queue_free()

func set_debug_draw(value: bool) -> void:
	debug_draw_enabled = value
	queue_redraw()

func _draw() -> void:
	if not debug_draw_enabled:
		return
	draw_rect(Rect2(-55, -245, 110, 245), Color(0.2, 1.0, 0.35, 0.17), true)
	draw_rect(Rect2(-190, -210, 145, 170), Color(1.0, 0.2, 0.2, 0.15), true)
	draw_line(Vector2.ZERO, Vector2(-float(config.attack_range), 0), Color.RED, 3.0)

func debug_status(mutki_x: float) -> String:
	return "%s: %s | %s #%d | HP %d/%d | dist %.1f | active %s" % [
		String(config.display_name),
		state,
		sprite.animation,
		sprite.frame,
		hp,
		int(config.max_hp),
		position.x - mutki_x,
		"ON" if _attack_active else "off",
	]
