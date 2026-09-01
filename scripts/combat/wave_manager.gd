class_name WaveManager
extends Node

signal spawn_requested(enemy_id: String)
signal wave_changed(wave_number: int, wave_size: int)

var wave_index := 0
var enemy_index := 0
var running := false
var _current_wave: Array[String] = []

func start_run() -> void:
	wave_index = 0
	enemy_index = 0
	running = true
	_load_wave()
	await get_tree().create_timer(0.55).timeout
	_request_current_enemy()

func enemy_defeated() -> void:
	if not running:
		return
	enemy_index += 1
	if enemy_index >= _current_wave.size():
		wave_index += 1
		enemy_index = 0
		_load_wave()
	await get_tree().create_timer(0.72).timeout
	_request_current_enemy()

func stop() -> void:
	running = false

func current_wave_number() -> int:
	return wave_index + 1

func _load_wave() -> void:
	_current_wave.clear()
	if wave_index < GameBalance.WAVES.size():
		for enemy_id in GameBalance.WAVES[wave_index]:
			_current_wave.append(String(enemy_id))
	else:
		var roster := GameBalance.ENEMIES.keys()
		var count := 7 + mini(6, wave_index)
		for index in count:
			_current_wave.append(String(roster[(index + wave_index) % roster.size()]))
	wave_changed.emit(wave_index + 1, _current_wave.size())

func _request_current_enemy() -> void:
	if running and enemy_index < _current_wave.size():
		spawn_requested.emit(_current_wave[enemy_index])
