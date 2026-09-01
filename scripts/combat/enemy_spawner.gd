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
var _next_thug_death_variant := 1

func spawn_enemy(enemy_id: String) -> void:
	if is_instance_valid(current_enemy):
		return
	var packed := SCENES.get(enemy_id) as PackedScene
	if packed == null:
		push_error("Unknown enemy type: " + enemy_id)
		return
	current_enemy = packed.instantiate() as EnemyBase
	if enemy_id == "enemy_01_thug":
		current_enemy.death_variant = _next_thug_death_variant
		_next_thug_death_variant = 2 if _next_thug_death_variant == 1 else 1
	add_child(current_enemy)
	current_enemy.position = Vector2(GameBalance.ENEMY_SPAWN_X, GameBalance.GROUND_Y)
	current_enemy.died.connect(_on_enemy_died)
	enemy_spawned.emit(current_enemy)

func _on_enemy_died(enemy: Node, enemy_id: String) -> void:
	if enemy == current_enemy:
		current_enemy = null
	enemy_defeated.emit(enemy, enemy_id)
