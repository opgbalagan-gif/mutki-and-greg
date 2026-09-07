extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("SOLO_SUPER_FAIL: " + message)

func texture_bytes(frames: SpriteFrames) -> int:
	if frames == null:
		return 0
	var unique := {}
	var total := 0
	for animation in frames.get_animation_names():
		for index in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation, index)
			if texture is AtlasTexture:
				texture = texture.atlas
			if texture == null or unique.has(texture.get_instance_id()):
				continue
			unique[texture.get_instance_id()] = true
			total += texture.get_width() * texture.get_height() * 4
	return total

func report_memory(label: String, game: Node) -> void:
	print("SUPER_MEMORY ", label, " render_MiB=", Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		" static_MiB=", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		" assist_MiB=", texture_bytes(game.arena_assist.sprite.sprite_frames) / 1048576.0)

func _run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.character_selected.emit("greg")
	game.hud.story_panel._finish()
	var scene_id := game.get_instance_id()
	await create_timer(0.7).timeout
	report_memory("before", game)
	check(texture_bytes(game.greg.sprite.sprite_frames) < 80 * 1048576, "Greg textures stay within the mobile memory budget")
	check(texture_bytes(game.spawner.get_target().sprite.sprite_frames) < 160 * 1048576, "enemy textures stay within the mobile memory budget")
	var previous_defeated := 0
	for activation in 3:
		var deadline := Time.get_ticks_msec() + 8000
		while game.spawner.get_target() == null and Time.get_ticks_msec() < deadline:
			await process_frame
		check(game.spawner.get_target() != null, "replacement enemies arrive after the preceding wave")
		game.super_charge = 100.0
		game.hud.set_super(100.0)
		game.hud.super_button.pressed.emit()
		check(game.assist_video.playing, "each activation starts its clip")
		if activation > 0:
			game.assist_video._finish()
		deadline = Time.get_ticks_msec() + 9000
		while game.assist_video.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(game.arena_assist.playing, "video leads into the arena wave")
		report_memory("wave_" + str(activation), game)
		check(texture_bytes(game.arena_assist.sprite.sprite_frames) < 80 * 1048576, "super does not retain full transparent canvases")
		deadline = Time.get_ticks_msec() + 7000
		while game.arena_assist.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not paused and not game.input_locked, "wave resumes the existing fight")
		await create_timer(2.5).timeout
		check(current_scene != null and current_scene.get_instance_id() == scene_id, "no scene restart after the wave or enemy replacements")
		check(game.mission_phase == "combat" and game.selected_fighter_id == "greg", "same hero and mission remain active")
		check(game.wave_manager._total_defeated > previous_defeated, "defeat progress is retained across super activations")
		previous_defeated = game.wave_manager._total_defeated
		report_memory("resumed_" + str(activation), game)
		# Continue with ordinary controls after the special, rather than only checking its callback.
		var target: EnemyBase = game.spawner.get_target()
		if target != null:
			game._try_attack(-1, target.approach_side)
			check(game.greg.state.begins_with("attack_"), "normal attack works after the super")
			await create_timer(1.0).timeout
	check(game.wave_manager.current_wave_number() >= 2, "super at the end of round one advances to round two")
	game.wave_manager.stop()
	game.spawner.stop_combat()
	await create_timer(0.6).timeout
	game.queue_free()
	await process_frame
	print("SOLO_SUPER_PASS: natural-video/skip/repeated-super/replacements/round-transition/progress/controls/no-restart" if failures.is_empty() else "SOLO_SUPER_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
