class_name GameBalance
extends RefCounted

const GROUND_Y := 930.0
const PLAYER_X := 178.0
const ENEMY_SPAWN_X := 820.0
const ENEMY_STOP_X := 408.0

const FIGHTERS := {
	"mutki": {
		"display_name": "МУТКИ",
		"max_hp": 110,
		"attack_range": 240.0,
		"hit_stop": 0.060,
		"standard_sprite_position": Vector2(0.0, -202.0),
		"standard_sprite_scale": 1.1,
		"video_sprite_position": Vector2(63.83, -191.49),
		"video_sprite_scale": 1.11445,
		"attacks": [
			{"animation": "attack_01", "damage": 34, "knockback": 182.0, "active_frame": 3},
			{"animation": "attack_02", "damage": 40, "knockback": 205.0, "active_frame": 4},
			{"animation": "attack_03", "damage": 48, "knockback": 235.0, "active_frame": 5},
		],
	},
	"greg": {
		"display_name": "ГРЕГ",
		"max_hp": 100,
		"attack_range": 240.0,
		"hit_stop": 0.052,
		"standard_sprite_position": Vector2(0.0, -202.0),
		"standard_sprite_scale": 1.1,
		"video_sprite_position": Vector2(36.84, -153.845),
		"video_sprite_scale": 0.922595,
		"idle_after_attack_frame": 5,
		"idle_after_hit_frame": 30,
		"attacks": [
			{"animation": "attack_01", "damage": 28, "knockback": 150.0, "active_frame": 4},
			{"animation": "attack_02", "damage": 35, "knockback": 180.0, "active_frame": 5},
			{"animation": "attack_03", "damage": 42, "knockback": 215.0, "active_frame": 7},
			{"animation": "attack_04", "damage": 52, "knockback": 265.0, "active_frame": 5},
		],
	},
}

const SUPER := {
	"charge_per_hit": 8.0,
	"charge_per_kill": 15.0,
	"damage": 140,
	"knockback": 310.0,
}

const ENEMIES := {
	"enemy_01_thug": {
		"display_name": "THUG",
		"sprite_position": Vector2(0.0, -232.0),
		"sprite_scale": 1.188525,
		"max_hp": 68,
		"speed": 92.0,
		"damage": 11,
		"attack_range": 88.0,
		"attack_delay": 0.30,
		"recovery": 0.52,
		"knockback_resistance": 1.0,
		"score": 120,
	},
	"enemy_02_hoodie": {
		"display_name": "HOODIE",
		"max_hp": 54,
		"speed": 116.0,
		"damage": 9,
		"attack_range": 82.0,
		"attack_delay": 0.24,
		"recovery": 0.44,
		"knockback_resistance": 1.08,
		"score": 135,
	},
	"enemy_03_big_guy": {
		"display_name": "BIG GUY",
		"max_hp": 145,
		"speed": 58.0,
		"damage": 19,
		"attack_range": 98.0,
		"attack_delay": 0.42,
		"recovery": 0.72,
		"knockback_resistance": 0.48,
		"score": 260,
	},
	"enemy_04_knife": {
		"display_name": "KNIFE",
		"max_hp": 48,
		"speed": 126.0,
		"damage": 18,
		"attack_range": 105.0,
		"attack_delay": 0.20,
		"recovery": 0.38,
		"knockback_resistance": 1.02,
		"score": 185,
	},
	"enemy_05_bandana": {
		"display_name": "BANDANA",
		"max_hp": 72,
		"speed": 108.0,
		"damage": 13,
		"attack_range": 96.0,
		"attack_delay": 0.26,
		"recovery": 0.43,
		"knockback_resistance": 0.88,
		"score": 165,
	},
}

const WAVES := [
	["enemy_01_thug", "enemy_01_thug", "enemy_02_hoodie", "enemy_01_thug", "enemy_02_hoodie"],
	["enemy_02_hoodie", "enemy_01_thug", "enemy_03_big_guy", "enemy_01_thug", "enemy_04_knife", "enemy_02_hoodie"],
	["enemy_01_thug", "enemy_05_bandana", "enemy_04_knife", "enemy_03_big_guy", "enemy_02_hoodie", "enemy_05_bandana", "enemy_03_big_guy"],
]
