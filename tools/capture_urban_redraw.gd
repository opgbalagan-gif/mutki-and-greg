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
	for card_index in MissionData.INTRO.size():
		var panel: StoryPanel = game.hud.story_panel
		var expected_art := String(MissionData.INTRO[card_index]["art"])
		if not ResourceLoader.exists(expected_art) or panel.artwork.texture == null:
			failures.append("Missing artwork: " + expected_art)
		elif panel.artwork.texture.resource_path != expected_art:
			failures.append("Unexpected artwork fallback: " + expected_art)
		await capture("intro_%02d" % (card_index + 1))
		for control in [panel.chapter_label, panel.title_label, panel.speaker_label, panel.body_label, panel.page_label, panel.next_button, panel.skip_button]:
			if control.visible and control.get_global_rect().end.y > root.size.y:
				failures.append("Control extends below viewport: " + control.text)
		panel.next_slide()
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
