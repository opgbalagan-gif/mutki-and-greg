class_name EnemySpawner
extends Node

signal enemy_spawned(enemy: Node)
signal enemy_defeated(enemy: Node, enemy_id: String)

const SCENES := {
	"enemy_01_thug": preload("res://scenes/enemies/EnemyThug.tscn"),
	"enemy_02_hoodie": preload("res://scenes/enemies/EnemyHoodie.tscn"),
	"enemy_03_big_guy": preload("res://scenes/enemies/EnemyBigGuy.tscn"),
	"enemy_04_knife": preload("res://scenes/enemies/EnemyKnife.tscn"),
	"enemy_05_bandana": preload("res://scenes/enemies/EnemyBandana.tscn"),
}

var current_enemy: EnemyBase = null
var active_enemies: Array[EnemyBase] = []
var _next_thug_death_variant := 1
var _next_spawn_side := 1

const FORMATION_SPACING := 94.0
const SPAWN_SPACING := 104.0

func spawn_enemy(enemy_id: String) -> void:
	var packed := SCENES.get(enemy_id) as PackedScene
	if packed == null:
		push_error("Unknown enemy type: " + enemy_id)
		return
	var enemy := packed.instantiate() as EnemyBase
	var approach_side := _next_spawn_side
	_next_spawn_side *= -1
	enemy.approach_side = approach_side
	if enemy_id == "enemy_01_thug":
		enemy.death_variant = _next_thug_death_variant
		_next_thug_death_variant = 2 if _next_thug_death_variant == 1 else 1
	var same_side_count := 0
	for active_enemy: EnemyBase in active_enemies:
		if active_enemy.approach_side == approach_side:
			same_side_count += 1
	add_child(enemy)
	var spawn_x := GameBalance.ENEMY_RIGHT_SPAWN_X + SPAWN_SPACING * same_side_count
	if approach_side < 0:
		spawn_x = GameBalance.ENEMY_LEFT_SPAWN_X - SPAWN_SPACING * same_side_count
	enemy.position = Vector2(spawn_x, GameBalance.GROUND_Y)
	active_enemies.append(enemy)
	enemy.died.connect(_on_enemy_died)
	_refresh_formation()
	enemy_spawned.emit(enemy)

func _on_enemy_died(enemy: Node, enemy_id: String) -> void:
	active_enemies.erase(enemy)
	_refresh_formation()
	enemy_defeated.emit(enemy, enemy_id)


func set_all_physics_enabled(value: bool) -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(value)


func set_all_debug_draw(value: bool) -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.set_debug_draw(value)


func _refresh_formation() -> void:
	active_enemies = active_enemies.filter(func(enemy: EnemyBase): return is_instance_valid(enemy))
	current_enemy = active_enemies[0] if not active_enemies.is_empty() else null
	var left_slot := 0
	var right_slot := 0
	for enemy: EnemyBase in active_enemies:
		if enemy.approach_side < 0:
			enemy.set_formation_slot(
				left_slot,
				GameBalance.ENEMY_LEFT_STOP_X - FORMATION_SPACING * left_slot,
				enemy == current_enemy
			)
			left_slot += 1
		else:
			enemy.set_formation_slot(
				right_slot,
				GameBalance.ENEMY_RIGHT_STOP_X + FORMATION_SPACING * right_slot,
				enemy == current_enemy
			)
			right_slot += 1
