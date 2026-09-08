extends SceneTree

class TestAssistPlayer extends AssistVideoPlayer:
	var helper_requested := ""
	func play_helper(helper_id: String) -> bool:
		helper_requested = helper_id
		return play_stream(load("res://tests/fixtures/assist_test.ogv") as VideoStream)

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ASSIST_VIDEO_FAIL: " + message)

func _run() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	for fighter_id in ["greg", "mutki"]:
		var game: Node = scene.instantiate()
		root.add_child(game)
		current_scene = game
		game.hud.character_selected.emit(fighter_id)
		game.intro_video._finish()
		await create_timer(0.6).timeout
		var expected_helper := "mutki" if fighter_id == "greg" else "greg"
		var expected_title := "ПОМОЩЬ МУТКИ" if fighter_id == "greg" else "ПОМОЩЬ ГРИШИ"
		check(game.hud.special_name == expected_title, "help title identifies the partner")
		var portrait := game.hud.fighter_portrait.texture as AtlasTexture
		check((portrait.region.position.x == 410) == (expected_helper == "mutki"), "help avatar identifies the partner")
		var missing := AssistVideoPlayer.new()
		game.add_child(missing)
		check(not missing.play_helper("unknown") and not paused, "unavailable video does not pause combat")
		if not ResourceLoader.exists(AssistVideoPlayer.VIDEO_PATHS[expected_helper]):
			check(not missing.play_helper(expected_helper) and not paused, "not-yet-added partner clip leaves fallback available")
		missing.queue_free()
		game.assist_video.queue_free()
		var player := TestAssistPlayer.new()
		game.add_child(player)
		game.assist_video = player
		player.finished.connect(game._on_assist_video_finished)
		var target: Node = game.spawner.get_target()
		var impacts := {"count": 0}
		target.damaged.connect(func(_enemy, _hp, _max_hp): impacts.count += 1)
		game.super_charge = 100.0
		game.hud.set_super(100.0)
		game.hud.super_button.pressed.emit()
		check(player.helper_requested == expected_helper, "button requests the partner's video")
		check(player.playing and paused and game.input_locked, "clip pauses and locks the fight")
		check(game.music.stream_paused and game.super_charge == 0.0, "music paused and charge consumed once")
		var enemy_position: Vector2 = target.position
		var hp: int = game.active_fighter.hp
		await create_timer(0.1).timeout
		check(target.position == enemy_position and game.active_fighter.hp == hp, "no enemy movement or damage during clip")
		game._try_super()
		check(player.playing and impacts.count == 0, "repeat activation does not restart or deal early damage")
		check(player._backdrop.find_children("*", "Button", true, false).is_empty(), "video has no skip buttons")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		await process_frame
		check(player.playing and paused, "Escape does not skip the clip")
		var deadline := Time.get_ticks_msec() + 6500
		while player.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not player.playing, "natural completion closes the video")
		if fighter_id == "greg":
			check(game.arena_assist.playing and impacts.count == 0, "Mutki starts the arena wave before dealing damage")
			while game.arena_assist.playing and Time.get_ticks_msec() < deadline:
				await process_frame
		check(not paused and not game.input_locked and not game.music.stream_paused, "controls and music restored")
		check(impacts.count == 1, "help applies exactly one impact")
		player._finish()
		check(impacts.count == 1, "late completion cannot repeat impact")
		# Let the existing hit-stop/shake coroutine finish before destroying its owner.
		while game._impact_busy:
			await process_frame
		game.queue_free()
		await process_frame
	var cleanup_player := TestAssistPlayer.new()
	root.add_child(cleanup_player)
	cleanup_player.play_helper("greg")
	check(paused, "cleanup case starts paused")
	cleanup_player.queue_free()
	await process_frame
	check(not paused, "removing the player cannot leave the scene paused")
	print("ASSIST_VIDEO_PASS: partner/title/avatar/button/pause/no-duplicate/natural-finish/no-skip/no-escape/resume/cleanup" if failures.is_empty() else "ASSIST_VIDEO_FAIL")
	quit(0 if failures.is_empty() else 1)
