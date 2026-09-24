extends SceneTree

var failures: Array[String] = []
var capture_mode := false


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("ARENA_SUPER_FAIL: " + message)


func capture(label: String) -> void:
	if not capture_mode:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/arena_supers/" + label + ".png")


func _run() -> void:
	capture_mode = OS.get_cmdline_user_args().has("--capture")
	root.size = Vector2i(720, 1280)
	root.content_scale_size = Vector2i(720, 1280)
	DirAccess.make_dir_recursive_absolute("res://artifacts/arena_supers")
	for hero in ["mutki", "greg"]:
		var game: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game._select_character(hero)
		game.intro_video._finish()
		await create_timer(0.6).timeout
		game.active_fighter.face_direction(-1 if hero == "greg" else 1)
		var impacts := {-1: 0, 1: 0}
		var target: EnemyBase = game.spawner.get_target(1)
		var other: EnemyBase = game.spawner.get_target(-1)
		target.damaged.connect(func(_enemy, _hp, _max): impacts[1] += 1)
		other.damaged.connect(func(_enemy, _hp, _max): impacts[-1] += 1)
		game.super_charge = 100.0
		game._try_super()
		check(game.assist_video.playing and paused and game.input_locked, hero + " intro freezes arena")
		check(game.assist_video._video.stream.resource_path == AssistVideoPlayer.VIDEO_PATHS[hero], hero + " own clip")
		var old_position := target.position
		await create_timer(0.25).timeout
		check(target.position == old_position and impacts[1] == 0 and impacts[-1] == 0, "no early damage or enemy movement")
		game._try_super()
		check(game.super_charge == 0.0, "charge consumed once")
		var deadline := Time.get_ticks_msec() + 8000
		while game.assist_video.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(game.arena_assist.playing and not paused and game.input_locked, "gameplay move resumes live arena with controls locked")
		check(game.arena_assist.fighter_id == hero and not game.active_fighter.sprite.visible, "one correct hero without a duplicate idle body")
		check(not game.active_fighter.take_damage(5), "super cannot be interrupted by enemy damage")
		var screen_rect: Rect2 = game.arena_assist.get_global_transform_with_canvas() * game.arena_assist.get_visual_rect()
		check(game.arena_assist.get_viewport_rect().encloses(screen_rect.grow(3.0)), "wide effects fit portrait viewport including camera shake")
		await capture(hero + "_01_start")
		game.arena_assist.set_suspended(true)
		var frozen_frame: int = game.arena_assist.sprite.frame
		await create_timer(0.2).timeout
		check(game.arena_assist.sprite.frame == frozen_frame, "network suspension freezes animation")
		game.arena_assist.set_suspended(false)
		var events: Array[int] = []
		game.arena_assist.impact.connect(func(side: int): events.append(side))
		deadline = Time.get_ticks_msec() + 6000
		while events.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		check(events.size() == 1 and events[0] == game.active_fighter.facing_direction, "first hit follows facing")
		check(impacts[events[0]] == 1 and impacts[-events[0]] == 0, "only struck side takes damage at first contact")
		await capture(hero + "_02_hit")
		while events.size() < 2 and Time.get_ticks_msec() < deadline:
			await process_frame
		check(events.size() == 2 and events[1] == -events[0], "rotation hits other side once")
		await capture(hero + "_03_return_hit")
		# Final-wave completion must wait until the hero is restored.
		game._on_mission_waves_completed()
		check(game.mission_phase == "combat" and game._pending_super_completion, "final mission exit waits for move recovery")
		if capture_mode:
			var last: int = game.arena_assist.sprite.sprite_frames.get_frame_count("super") - 1
			while game.arena_assist.sprite.frame < last and Time.get_ticks_msec() < deadline:
				await process_frame
			game.arena_assist.sprite.pause()
			await capture(hero + "_04_handoff_before")
			game.arena_assist._on_animation_finished()
			game.active_fighter.sprite.pause()
			await capture(hero + "_05_handoff_after")
		while game.arena_assist.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(impacts[1] == 1 and impacts[-1] == 1, "exactly one damage event per target")
		check(game.active_fighter.sprite.visible and game.active_fighter.state == "idle", "normal hero restored after recovery")
		check(game.mission_phase == "exit" and not paused, "deferred mission exit finishes")
		game.assist_video._finish()
		game._on_arena_super_impact(1)
		check(impacts[1] == 1, "late callbacks cannot deal extra damage")
		game.mission_phase = "combat"
		game.input_locked = false
		game._try_attack(0, 1)
		check(game.active_fighter.state.begins_with("attack_"), "ordinary controls work after super")
		await capture(hero + "_06_resumed")
		while game._impact_busy:
			await process_frame
		game.queue_free()
		await process_frame
	print("ARENA_SUPER_PASS: own-clips/both-heroes/real-time-arena/two-hit-sides/one-body/portrait-bounds/pause/recovery/final-wave" if failures.is_empty() else "ARENA_SUPER_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
