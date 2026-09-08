extends SceneTree

var failures: Array[String] = []
var output := "res://artifacts/menu_style_20260909/"


func _initialize() -> void:
	_run.call_deferred()


func _check_bounds(node: Node) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Button or node is LineEdit or node is Label):
		var bounds: Rect2 = node.get_global_rect()
		if bounds.position.x < -1 or bounds.end.x > 721 or bounds.end.y > 1281:
			failures.append("Outside viewport: " + node.name + " " + str(bounds))
		if node is Label and node.get_minimum_size().y > node.size.y + 1:
			failures.append("Text clipped: " + node.text)
	for child in node.get_children():
		_check_bounds(child)


func capture(label: String, control: Node) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check_bounds(control)
	var error := root.get_texture().get_image().save_png(output + label + ".png")
	if error != OK:
		failures.append("Could not save " + label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var lobby := CoopLobby.new()
	root.add_child(lobby)
	await capture("01_modes", lobby)
	lobby.show_connect("AB12CD")
	await capture("02_connect", lobby)
	lobby.show_room("AB12CD")
	await capture("03_room", lobby)
	lobby.show_results("ВОЛНА 1 ПРОЙДЕНА", {"greg": 12500, "mutki": 10800}, {"greg": 12500, "mutki": 10800})
	await capture("04_round", lobby)
	lobby.show_results("МИССИЯ ПРОЙДЕНА", {"greg": 9800, "mutki": 15300}, {"greg": 28500, "mutki": 34200}, true)
	lobby.set_ready_state(true, false)
	await capture("05_coop_final", lobby)
	lobby.show_connection_problem("Связь с напарником потеряна. Вернитесь в игру на обоих телефонах.")
	await capture("06_pause", lobby)
	lobby.queue_free()
	await process_frame
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.coop_menu.action_requested.emit("solo", "")
	await capture("07_character_select", game.hud.character_select)
	game.hud.character_selected.emit("mutki")
	await create_timer(1.0).timeout
	await capture("08_intro_video", game.intro_video._backdrop)
	game.intro_video._finish()
	game.wave_manager.stop()
	game.spawner.stop_combat()
	game.hud.show_mission_complete(123450, 72, 121.0)
	await capture("09_victory", game.hud.message_panel)
	game.hud.show_game_over(3250)
	await capture("10_defeat", game.hud.message_panel)
	var retry_button: Button = game.hud.get_node("Root/MessagePanel/RetryButton")
	# Dispatch pointer input through the viewport: decorative backdrops must not
	# intercept taps even when their drawing z-index is below the result panel.
	var click_position := retry_button.get_global_rect().get_center()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = click_position
		click.global_position = click_position
		click.pressed = down
		root.push_input(click)
		await process_frame
	await create_timer(4.0).timeout
	if current_scene == null or current_scene.scene_file_path != "res://scenes/Main.tscn":
		failures.append("Retry did not return to the main scene")
	elif current_scene.hud.coop_menu.visible:
		await capture("11_retry", current_scene.hud.coop_menu)
	else:
		failures.append("Retry did not reopen mode selection")
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MENU_STYLE_CAPTURE_PASS" if failures.is_empty() else "MENU_STYLE_CAPTURE_FAIL")
	quit(0 if failures.is_empty() else 1)
