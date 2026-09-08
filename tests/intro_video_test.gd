extends SceneTree

var failures: Array[String] = []
var capture_mode := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("INTRO_VIDEO_FAIL: " + message)


func capture(label: String) -> void:
	if not capture_mode:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/intro_video_20260909/" + label + ".png")


func _run() -> void:
	capture_mode = OS.get_cmdline_user_args().has("--capture")
	if capture_mode:
		DirAccess.make_dir_recursive_absolute("res://artifacts/intro_video_20260909")
		root.size = Vector2i(720, 1280)
		root.content_scale_size = Vector2i(720, 1280)
	var scene: PackedScene = load("res://scenes/Main.tscn")
	for hero in ["greg", "mutki"]:
		var game: Node = scene.instantiate()
		root.add_child(game)
		current_scene = game
		game.hud.character_selected.emit(hero)
		var started := Time.get_ticks_msec()
		var finishes := {"count": 0}
		game.intro_video.finished.connect(func(): finishes.count += 1)
		check(game.intro_video.playing and game.input_locked and paused, "selection starts video with combat frozen: " + hero)
		check(game.intro_video._video.stream.resource_path == MissionData.INTRO_VIDEO, "plays the supplied intro resource")
		check(game.music.stream_paused and not game.hud.story_panel.visible, "only video soundtrack; no slideshow")
		check(game.intro_video._backdrop.find_children("*", "Button", true, false).is_empty(), "no slideshow or skip buttons")
		await create_timer(1.0).timeout
		for key in [KEY_ESCAPE, KEY_SPACE, KEY_G]:
			var event := InputEventKey.new()
			event.keycode = key
			event.pressed = true
			root.push_input(event)
		var tap := InputEventScreenTouch.new()
		tap.position = Vector2(360, 1217)
		tap.pressed = true
		root.push_input(tap)
		await process_frame
		check(game.intro_video.playing and game.mission_phase == "intro", "keyboard and old skip location cannot skip the clip")
		check(game.spawner.active_enemies.is_empty() and game.mission_elapsed == 0.0, "no enemies or mission time during video")
		await capture(hero + "_intro")
		while game.intro_video.playing and Time.get_ticks_msec() - started < 24000:
			await process_frame
		var watched := float(Time.get_ticks_msec() - started) / 1000.0
		check(watched >= 14.8 and watched < 24.0 and finishes.count == 1, "full 15-second clip ends naturally once")
		check(game.mission_phase == "combat" and not game.input_locked and not paused, "video ends directly in combat")
		check(not game.music.stream_paused and game.intro_video._video.stream == null, "music resumes and video resource is released")
		await create_timer(0.5).timeout
		check(game.spawner.active_enemies.size() == 3 and game.mission_elapsed < 1.0, "first wave starts after video, with a fresh mission timer")
		await capture(hero + "_combat")
		game.intro_video._finish()
		check(finishes.count == 1, "late completion cannot repeat the transition")
		game.queue_free()
		await process_frame
		print("INTRO_SOLO_PASS: ", hero, " natural-video/direct-combat/audio/input/no-slides")
	# The two clients deliberately finish at different times. The host must wait.
	var host: Node = scene.instantiate()
	root.add_child(host)
	current_scene = host
	var guest_view := SubViewport.new()
	guest_view.size = Vector2i(720, 1280)
	guest_view.world_2d = World2D.new()
	root.add_child(guest_view)
	var guest: Node = scene.instantiate()
	guest_view.add_child(guest)
	for session: CoopSession in [host.coop, guest.coop]:
		session.enabled = true
		session.connected = true
		session.test_transport = true
		session.host_hero = "greg"
		session.guest_hero = "mutki"
	host.coop.is_host = true
	host.coop.outbound.connect(guest.coop.receive)
	guest.coop.outbound.connect(host.coop.receive)
	host.coop._begin_run()
	check(host.intro_video.playing and guest.intro_video.playing, "both clients start the intro")
	await create_timer(0.5).timeout
	host.coop._set_paused(true)
	host.coop._send_snapshot()
	var host_position: float = host.intro_video._elapsed
	var guest_position: float = guest.intro_video._elapsed
	await create_timer(0.4).timeout
	check(host.intro_video._elapsed == host_position and guest.intro_video._elapsed == guest_position, "network pause freezes both videos")
	host.coop._set_paused(false)
	host.coop._send_snapshot()
	await create_timer(0.25).timeout
	check(host.intro_video._elapsed > host_position and guest.intro_video._elapsed > guest_position, "resume continues both videos without restarting")
	host.intro_video._finish()
	check(host.coop.phase == "intro" and guest.intro_video.playing and host.input_locked and paused, "first finisher waits for the second video")
	check(host.spawner.active_enemies.is_empty() and host.music.stream_paused, "waiting client cannot start enemies or battle music")
	# A completed intro remains acknowledged after a pause/resume.
	host.coop._set_paused(true)
	host.coop._send_snapshot()
	host.coop._set_paused(false)
	host.coop._send_snapshot()
	check(not host.intro_video.playing and guest.intro_video.playing, "waiting does not restart the clip")
	guest.intro_video._finish()
	check(host.coop.phase == "combat" and guest.coop.phase == "combat" and not paused, "both completions automatically start shared combat")
	check(not host.music.stream_paused and not guest.music.stream_paused, "both soundtracks restore after the intro barrier")
	await create_timer(0.5).timeout
	check(host.spawner.active_enemies.size() == 3 and guest.coop._replicas.size() == 3, "one shared first wave after intro")
	host.wave_manager.stop()
	host.spawner.stop_combat()
	host.coop._begin_run()
	check(host.intro_video.playing and guest.intro_video.playing, "replay restarts the supplied video on both clients")
	host.coop._disconnect("Test disconnect during intro")
	guest.coop._disconnect("Test disconnect during intro")
	host.intro_video._finish()
	check(not host.intro_video.playing and not guest.intro_video.playing and host.input_locked and not paused, "disconnect cancels the video without a late battle start")
	host.queue_free()
	guest_view.queue_free()
	await process_frame
	print("INTRO_VIDEO_PASS: two-heroes/natural-completion/audio/no-skip/direct-combat/coop-pause/barrier/replay/disconnect" if failures.is_empty() else "INTRO_VIDEO_FAIL")
	quit(0 if failures.is_empty() else 1)
