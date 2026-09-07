extends SceneTree

var spawn_count := 0
var completions := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var waves := WaveManager.new()
	root.add_child(waves)
	waves.spawn_requested.connect(func(_id: String): spawn_count += 1)
	waves.run_completed.connect(func(): completions += 1)
	waves.start_run(1)
	waves.stop()
	waves.start_run(1)
	await create_timer(0.4).timeout
	if spawn_count != 3:
		push_error("WAVE_TEST_FAIL: old startup timer spawned into a new run")
		quit(1)
		return
	waves.enemy_defeated()
	waves.stop()
	waves.start_run(1)
	spawn_count = 0
	await create_timer(0.25).timeout
	if spawn_count != 0:
		push_error("WAVE_TEST_FAIL: old replacement timer spawned into a new run")
		quit(2)
		return
	await create_timer(0.15).timeout
	for index in 5:
		waves.enemy_defeated()
		await create_timer(0.21).timeout
	await create_timer(0.5).timeout
	if waves.running or completions != 1 or spawn_count != 5:
		push_error("WAVE_TEST_FAIL: finite run completion or spawn count")
		quit(3)
		return
	waves.wait_between_rounds = true
	waves.start_run(2)
	await create_timer(0.4).timeout
	# Leave replacement timers pending, finish the wave and immediately continue.
	for index in 5:
		waves.enemy_defeated()
	if not waves.waiting_for_continue:
		push_error("WAVE_TEST_FAIL: cooperative round did not wait")
		quit(4)
		return
	waves.continue_after_round()
	spawn_count = 0
	await create_timer(0.25).timeout
	if spawn_count != 0:
		push_error("WAVE_TEST_FAIL: previous round replacement spawned into next round")
		quit(5)
		return
	await create_timer(0.25).timeout
	if spawn_count != 3:
		push_error("WAVE_TEST_FAIL: next cooperative round opening group")
		quit(6)
		return
	waves.stop()
	print("WAVE_TEST_PASS: stale-start/stale-respawn/finite-completion/round-barrier/no-cross-round-spawn")
	waves.queue_free()
	await process_frame
	quit(0)
