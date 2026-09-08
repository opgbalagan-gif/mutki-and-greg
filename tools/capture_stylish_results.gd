extends "res://tools/capture_menu_style.gd"

var actions: Array[String] = []


func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event)
		await process_frame


func reveal(panel: StylishResultPanel) -> void:
	await create_timer(1.7).timeout
	if panel.is_processing() or panel._shown(panel.score) != panel.score:
		failures.append("Score animation did not settle to the actual score")


func _run() -> void:
	output = "res://artifacts/stylish_results_20260909/"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var lobby := CoopLobby.new()
	root.add_child(lobby)
	lobby.action_requested.connect(func(action: String, _value: String): actions.append(action))
	lobby.show_results("РАУНД 1 / 3 ЗАВЕРШЁН", {"greg": 6500, "mutki": 4800}, {"greg": 6500, "mutki": 4800})
	await reveal(lobby.stylish_result)
	await capture("01_round", lobby)
	await tap(lobby.continue_button)
	if actions != ["ready"]:
		failures.append("Ready tap did not reach the lobby")
	lobby.set_ready_state(true, false)
	await tap(lobby.continue_button)
	if actions.size() != 1:
		failures.append("Disabled ready button accepted another tap")
	lobby.show_results("МИССИЯ ПРОЙДЕНА ВМЕСТЕ!", {"greg": 9800, "mutki": 15300}, {"greg": 28500, "mutki": 34200}, true)
	await reveal(lobby.stylish_result)
	lobby.set_ready_state(true, false)
	await capture("02_coop_final", lobby)
	lobby.show_results("РАУНД 2 / 3 ЗАВЕРШЁН", {"greg": 0, "mutki": 0}, {"greg": 6500, "mutki": 4800})
	await reveal(lobby.stylish_result)
	await capture("03_tie_zero", lobby)
	lobby.show_results("МИССИЯ НЕ ПРОЙДЕНА", {"greg": 900, "mutki": 300}, {"greg": 6500, "mutki": 4800})
	lobby.set_status("Оба героя повержены. Подтвердите готовность, чтобы попробовать ещё раз.")
	await reveal(lobby.stylish_result)
	await capture("04_coop_defeat", lobby)
	await tap(lobby.column.get_child(lobby.column.get_child_count() - 1))
	if actions.back() != "menu":
		failures.append("Menu tap did not reach the lobby")
	lobby.queue_free()
	await process_frame
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.coop_menu.action_requested.emit("solo", "")
	game.hud.character_selected.emit("mutki")
	game.intro_video._finish()
	game.wave_manager.stop()
	game.spawner.stop_combat()
	game.mission_phase = "complete"
	for example in [[40000, 72], [18000, 49], [10000, 50], [3500, 100], [0, 100], [999999999, 100]]:
		game.hud.show_mission_complete(example[0], example[1], 121.0)
		await reveal(game.hud.stylish_result)
		await capture("05_solo_%09d" % example[0], game.hud.message_panel)
	game.hud.show_game_over(3250, 67.0)
	await reveal(game.hud.stylish_result)
	await capture("06_solo_defeat", game.hud.message_panel)
	await tap(game.hud.get_node("Root/MessagePanel/RetryButton"))
	await create_timer(4.0).timeout
	if current_scene == null or current_scene.scene_file_path != "res://scenes/Main.tscn":
		failures.append("Retry did not return to the main scene")
	elif not current_scene.hud.coop_menu.visible:
		failures.append("Retry did not reopen mode selection")
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("STYLISH_RESULTS_PASS" if failures.is_empty() else "STYLISH_RESULTS_FAIL")
	quit(0 if failures.is_empty() else 1)
