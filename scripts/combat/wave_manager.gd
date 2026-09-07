class_name WaveManager
extends Node

signal spawn_requested(enemy_id: String)
signal wave_changed(wave_number: int, wave_size: int)
signal progress_changed(defeated: int, total: int)
signal run_completed
signal round_completed(wave_number: int)

const GROUP_SIZE := 3

var wave_index := 0
var spawned_count := 0
var defeated_count := 0
var running := false
var wait_between_rounds := false
var waiting_for_continue := false
var _current_wave: Array[String] = []
var _wave_limit := 0
var _run_generation := 0
var _total_defeated := 0
var _total_enemies := 0

func start_run(wave_limit: int = 0) -> void:
	_run_generation += 1
	var generation := _run_generation
	_wave_limit = maxi(0, wave_limit)
	_total_defeated = 0
	_total_enemies = 0
	for index in _wave_limit:
		_total_enemies += GameBalance.WAVES[index].size() if index < GameBalance.WAVES.size() else 7 + mini(6, index)
	wave_index = 0
	spawned_count = 0
	defeated_count = 0
	running = true
	waiting_for_continue = false
	_load_wave()
	progress_changed.emit(_total_defeated, _total_enemies)
	await get_tree().create_timer(0.35, false).timeout
	if running and generation == _run_generation:
		_fill_group()

func enemy_defeated() -> void:
	if not running or waiting_for_continue:
		return
	var generation := _run_generation
	defeated_count += 1
	_total_defeated += 1
	progress_changed.emit(_total_defeated, _total_enemies)
	if defeated_count >= _current_wave.size():
		# Replacement timers from the finished wave cannot spawn into the next one.
		_run_generation += 1
		generation = _run_generation
		if wait_between_rounds:
			waiting_for_continue = true
			round_completed.emit(current_wave_number())
			return
		if _wave_limit > 0 and wave_index + 1 >= _wave_limit:
			stop()
			run_completed.emit()
			return
		wave_index += 1
		spawned_count = 0
		defeated_count = 0
		_load_wave()
		await get_tree().create_timer(0.45, false).timeout
		if running and generation == _run_generation:
			_fill_group()
		return
	await get_tree().create_timer(0.20, false).timeout
	if running and generation == _run_generation:
		_request_next_enemy()

func stop() -> void:
	running = false
	waiting_for_continue = false
	_run_generation += 1

func continue_after_round() -> void:
	if not running or not waiting_for_continue:
		return
	waiting_for_continue = false
	if _wave_limit > 0 and current_wave_number() >= _wave_limit:
		stop()
		run_completed.emit()
		return
	wave_index += 1
	spawned_count = 0
	defeated_count = 0
	_load_wave()
	var generation := _run_generation
	await get_tree().create_timer(0.45, false).timeout
	if running and generation == _run_generation:
		_fill_group()

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
	if not running or waiting_for_continue or spawned_count >= _current_wave.size():
		return
	spawn_requested.emit(_current_wave[spawned_count])
	spawned_count += 1
