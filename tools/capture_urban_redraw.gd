extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/urban_redraw/review/" + label + ".png")
	if error != OK:
		failures.append("Could not save " + label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/urban_redraw/review")
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var loading: LoadingScreenManager = load("res://scenes/ui/LoadingScreen.tscn").instantiate()
	root.add_child(loading)
	loading.set_process(false)
	loading._set_progress(0.6)
	if loading.artwork.texture == null or not LoadingScreenManager.LOADING_SCREEN_PATHS.has(loading.artwork.texture.resource_path):
		failures.append("Loading screen does not show a restored loading illustration")
	await capture("loading")
	ResourceLoader.load_threaded_get(loading.target_scene_path)
	loading.queue_free()
	await process_frame
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(0.5).timeout
	await capture("00_menu")
	game.hud.character_selected.emit("mutki")
	await create_timer(1.0).timeout
	await capture("intro_video")
	game.intro_video._finish()
	await create_timer(0.7).timeout
	await capture("combat")
	game.wave_manager.stop()
	game.spawner.stop_combat()
	game._on_mission_waves_completed()
	await capture("exit")
	game.hud.exit_button.pressed.emit()
	for card_index in MissionData.OUTRO.size():
		await capture("outro_%02d" % (card_index + 1))
		game.hud.story_panel.next_slide()
	await capture("result")
	game.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("URBAN_UI_CAPTURE_PASS" if failures.is_empty() else "URBAN_UI_CAPTURE_FAIL")
	quit(0 if failures.is_empty() else 1)
