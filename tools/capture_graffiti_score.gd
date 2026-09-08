extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://artifacts/graffiti_score/" + label + ".png")
	if result != OK:
		failures.append("Could not save " + label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/graffiti_score")
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.character_selected.emit("greg")
	game.intro_video._finish()
	await create_timer(1.0).timeout
	game.wave_manager.stop()
	game.spawner.stop_combat()
	game.set_process(false)
	game.hud.mission_panel.hide()
	for points in [0, 1, 9876543210]:
		game.hud.set_score(points)
		var digits: GraffitiNumber = game.hud._score_digits
		var bounds := digits.content_rect()
		if bounds.position.x < -0.1 or bounds.end.x > digits.size.x + 0.1 or bounds.end.y > digits.size.y + 0.1:
			failures.append("Score overflows at " + str(points))
		if digits.text != GameHUD._number(points):
			failures.append("Displayed score changed at " + str(points))
	game.hud.set_score(128750)
	game.hud.set_skill_chain(2640, 3.4, 24, 0.72)
	await capture("01_combat")
	game.hud.show_chain_result(8976)
	await capture("02_banked")
	game.hud.show_chain_result(0, true)
	if game.hud._chain_digits.visible or not game.hud.combo_label.visible:
		failures.append("Broken chain did not restore its readable text")
	await capture("03_broken")
	game.queue_free()
	await process_frame
	root.size = Vector2i(1200, 450)
	root.content_scale_size = Vector2i(1200, 450)
	var sheet := ColorRect.new()
	sheet.color = Color("121b10")
	sheet.size = Vector2(1200, 450)
	root.add_child(sheet)
	for index in 10:
		var digit := GraffitiNumber.new()
		digit.text = str(index)
		digit.alignment = 1
		digit.digit_height = 174
		digit.position = Vector2(20 + (index % 5) * 234, 20 + (index / 5) * 210)
		digit.size = Vector2(220, 180)
		sheet.add_child(digit)
	await capture("04_digits")
	sheet.queue_free()
	await process_frame
	print("GRAFFITI_SCORE_PASS: all-digits/zero/large-score/no-overflow/chain/multiplier/banked/broken" if failures.is_empty() else "GRAFFITI_SCORE_FAIL: " + str(failures))
	quit(0 if failures.is_empty() else 1)
