extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func capture(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var error := screenshot.save_png("res://artifacts/mutki_hit_v2/" + file_name)
	assert(error == OK)

func _run() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.hud.character_selected.emit("mutki")
	game.intro_video._finish()
	game.wave_manager.stop()
	game.spawner.stop_combat()
	for enemy in game.spawner.active_enemies:
		enemy.queue_free()
	game.spawner.active_enemies.clear()
	var fighter: PlayerFighter = game.active_fighter
	fighter.sprite.pause()
	fighter.sprite.frame = 0
	await capture("game_idle.png")
	fighter.take_damage(1)
	await create_timer(0.15).timeout
	fighter.sprite.pause()
	fighter.sprite.frame = 2
	await capture("game_hit.png")
	fighter.state = "idle"
	fighter.face_direction(1)
	fighter.take_damage(999)
	await create_timer(0.15).timeout
	fighter.sprite.pause()
	fighter.sprite.frame = 20
	await capture("game_fall_right.png")
	fighter.facing_direction = -1
	fighter._apply_facing()
	await capture("game_fall_left.png")
	print("MUTKI_CAPTURE_PASS: idle/hit/full-fall/both-directions")
	game.queue_free()
	await process_frame
	quit()
