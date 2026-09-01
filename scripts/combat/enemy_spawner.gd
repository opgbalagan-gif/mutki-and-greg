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

const FORMATION_SPACING := 94.0
const SPAWN_SPACING := 104.0

func spawn_enemy(enemy_id: String) -> void:
	var packed := SCENES.get(enemy_id) as PackedScene
	if packed == null:
		push_error("Unknown enemy type: " + enemy_id)
		return
	var enemy := packed.instantiate() as EnemyBase
	if enemy_id == "enemy_01_thug":
		enemy.death_variant = _next_thug_death_variant
		_next_thug_death_variant = 2 if _next_thug_death_variant == 1 else 1
	add_child(enemy)
	enemy.position = Vector2(
		GameBalance.ENEMY_SPAWN_X + SPAWN_SPACING * active_enemies.size(),
		GameBalance.GROUND_Y
	)
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
	for index in active_enemies.size():
		active_enemies[index].set_formation_slot(index, GameBalance.ENEMY_STOP_X + FORMATION_SPACING * index)
