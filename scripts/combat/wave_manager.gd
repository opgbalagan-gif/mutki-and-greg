class_name WaveManager
extends Node

signal spawn_requested(enemy_id: String)
signal wave_changed(wave_number: int, wave_size: int)

const GROUP_SIZE := 3

var wave_index := 0
var spawned_count := 0
var defeated_count := 0
var running := false
var _current_wave: Array[String] = []

func start_run() -> void:
	wave_index = 0
	spawned_count = 0
	defeated_count = 0
	running = true
	_load_wave()
	await get_tree().create_timer(0.35).timeout
	_fill_group()

func enemy_defeated() -> void:
	if not running:
		return
	defeated_count += 1
	if defeated_count >= _current_wave.size():
		wave_index += 1
		spawned_count = 0
		defeated_count = 0
		_load_wave()
		await get_tree().create_timer(0.45).timeout
		_fill_group()
		return
	await get_tree().create_timer(0.20).timeout
	_request_next_enemy()

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
		var count := 7 + mini(6, wave_index)
		for _index in count:
			_current_wave.append(GameBalance.STANDARD_ENEMY_ID)
	wave_changed.emit(wave_index + 1, _current_wave.size())

func _fill_group() -> void:
	for _slot in mini(GROUP_SIZE, _current_wave.size() - spawned_count):
		_request_next_enemy()


func _request_next_enemy() -> void:
	if not running or spawned_count >= _current_wave.size():
		return
	spawn_requested.emit(_current_wave[spawned_count])
	spawned_count += 1
