class_name GameBalance
extends RefCounted

const GROUND_Y := 930.0
const PLAYER_X := 360.0
const ENEMY_LEFT_SPAWN_X := -100.0
const ENEMY_RIGHT_SPAWN_X := 820.0
const ENEMY_LEFT_STOP_X := 170.0
const ENEMY_RIGHT_STOP_X := 550.0
const STANDARD_ENEMY_ID := "enemy_01_thug"

const FIGHTERS := {
	"mutki": {
		"display_name": "МУТКИ",
		"max_hp": 110,
		"attack_range": 240.0,
		"hit_stop": 0.060,
		"animation_speed": 1.5,
		"standard_sprite_position": Vector2(0.0, -202.0),
		"standard_sprite_scale": 1.1,
		# Attacks and reactions use one canvas, floor pivot and body scale.
		"idle_directory": "idle_reactions_v2",
		"idle_sprite_position": Vector2(0.0, -217.53999),
		"idle_sprite_scale": 1.0663725,
		"idle_faces_left": false,
		"hit_directory": "hit_video_v2",
		"death_directory": "death_video_v2",
		"video_sprite_position": Vector2(0.0, -217.53999),
		"video_sprite_scale": 1.0663725,
		"attacks": [
			{"animation": "attack_v2_01", "damage": 34, "knockback": 182.0, "active_frame": 3, "active_end_frame": 4},
			{"animation": "attack_v2_02", "damage": 40, "knockback": 205.0, "active_frame": 3, "active_end_frame": 4},
			{"animation": "attack_v2_03", "damage": 48, "knockback": 235.0, "active_frame": 5, "active_end_frame": 6},
			{"animation": "attack_v2_04", "damage": 52, "knockback": 250.0, "active_frame": 6, "active_end_frame": 7},
			{"animation": "attack_v2_05", "damage": 48, "knockback": 235.0, "active_frame": 5, "active_end_frame": 6},
			{"animation": "attack_v2_06", "damage": 52, "knockback": 255.0, "active_frame": 8, "active_end_frame": 9},
			{"animation": "attack_v2_07", "damage": 60, "knockback": 275.0, "active_frame": 16, "active_end_frame": 17},
		],
	},
	"greg": {
		"display_name": "ГРИША",
		"max_hp": 100,
		"attack_range": 240.0,
		"cleave_range": 340.0,
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
	"charge_per_combo_hit": 12.5,
	"damage": 140,
	"knockback": 310.0,
}

const ENEMIES := {
	"enemy_01_thug": {
		"display_name": "THUG",
		"sprite_position": Vector2(0.0, -232.0),
		"sprite_scale": 0.5942625,
		"max_hp": 42,
		"speed": 150.0,
		"damage": 11,
		"attack_range": 88.0,
		"attack_delay": 0.30,
		"recovery": 0.52,
		"knockback_resistance": 1.0,
		"score": 120,
	},
	"enemy_02_hoodie": {
		"display_name": "HOODIE",
		"max_hp": 34,
		"speed": 180.0,
		"damage": 9,
		"attack_range": 82.0,
		"attack_delay": 0.24,
		"recovery": 0.44,
		"knockback_resistance": 1.08,
		"score": 135,
	},
	"enemy_03_big_guy": {
		"display_name": "BIG GUY",
		"max_hp": 52,
		"speed": 118.0,
		"damage": 19,
		"attack_range": 98.0,
		"attack_delay": 0.42,
		"recovery": 0.72,
		"knockback_resistance": 0.48,
		"score": 260,
	},
	"enemy_04_knife": {
		"display_name": "KNIFE",
		"max_hp": 38,
		"speed": 200.0,
		"damage": 18,
		"attack_range": 105.0,
		"attack_delay": 0.20,
		"recovery": 0.38,
		"knockback_resistance": 1.02,
		"score": 185,
	},
	"enemy_05_bandana": {
		"display_name": "BANDANA",
		"max_hp": 46,
		"speed": 170.0,
		"damage": 13,
		"attack_range": 96.0,
		"attack_delay": 0.26,
		"recovery": 0.43,
		"knockback_resistance": 0.88,
		"score": 165,
	},
}

const WAVES := [
	[STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID],
	[STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID],
	[STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID, STANDARD_ENEMY_ID],
]
