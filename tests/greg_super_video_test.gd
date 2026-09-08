extends SceneTree

var failures: Array[String] = []
var capture_mode := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GREG_SUPER_FAIL: " + message)


func capture(label: String) -> void:
	if not capture_mode:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/greg_super/" + label + ".png")


func check_assist_layout(game: Node) -> void:
	var assist: MutkiArenaAssist = game.arena_assist
	check(assist.position == Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y), "assist appears at arena center regardless of facing or player ownership")
	var viewport := assist.get_viewport_rect()
	for index in assist.sprite.sprite_frames.get_frame_count("assist_super"):
		var texture := assist.sprite.sprite_frames.get_frame_texture("assist_super", index)
		var frame_rect := Rect2(-texture.get_size() * 0.5, texture.get_size())
		var screen_rect: Rect2 = assist.sprite.get_global_transform_with_canvas() * frame_rect
		check(viewport.encloses(screen_rect.grow(18.0)), "entire wave frame %d fits with maximum camera shake" % index)


func _run() -> void:
	capture_mode = OS.get_cmdline_user_args().has("--capture")
	if capture_mode:
		DirAccess.make_dir_recursive_absolute("res://artifacts/greg_super")
		root.size = Vector2i(720, 1280)
		root.content_scale_size = Vector2i(720, 1280)
	check(ResourceLoader.exists(AssistVideoPlayer.VIDEO_PATHS.mutki), "provided clip is a packaged Godot video resource")
	var scene: PackedScene = load("res://scenes/Main.tscn")
	for try_skipping in [false, true]:
		var game: Node = scene.instantiate()
		root.add_child(game)
		current_scene = game
		game.hud.character_selected.emit("greg")
		game.intro_video._finish()
		await create_timer(0.6).timeout
		game.greg.face_direction(-1 if try_skipping else 1)
		var enemy: EnemyBase = game.spawner.get_target(1)
		var impacts := {"count": 0}
		enemy.damaged.connect(func(_enemy, _hp, _max): impacts.count += 1)
		var other_enemy: EnemyBase = game.spawner.get_target(-1)
		var other_impacts := {"count": 0}
		other_enemy.damaged.connect(func(_enemy, _hp, _max): other_impacts.count += 1)
		game.super_charge = 100.0
		game.hud.set_super(100.0)
		game.hud.super_button.pressed.emit()
		check(game.assist_video.playing and paused and game.input_locked, "Greg button plays the real clip with combat paused")
		check(game.assist_video._video.stream.resource_path == AssistVideoPlayer.VIDEO_PATHS.mutki, "button uses the user's clip")
		var old_position := enemy.position
		var old_hp := enemy.hp
		await create_timer(0.6).timeout
		check(enemy.position == old_position and enemy.hp == old_hp and impacts.count == 0, "video deals no early damage and freezes enemies")
		await capture("01_real_clip")
		game._try_super()
		check(game.super_charge == 0.0 and impacts.count == 0, "repeat button cannot recharge or duplicate the move")
		check(game.assist_video._backdrop.find_children("*", "Button", true, false).is_empty(), "real clip has no skip buttons")
		if try_skipping:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
			var tap := InputEventScreenTouch.new()
			tap.position = Vector2(610, 1227)
			tap.pressed = true
			Input.parse_input_event(tap)
			await process_frame
			check(game.assist_video.playing and paused and impacts.count == 0, "Escape and tapping the old skip position do not end the clip")
		var deadline := Time.get_ticks_msec() + 9000
		while game.assist_video.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		deadline = Time.get_ticks_msec() + 7000
		check(paused and game.arena_assist.playing and game.arena_assist.sprite.animation == "assist_super", "natural video completion starts the supplied Mutki wave with the arena frozen")
		check(game.arena_assist.sprite.sprite_frames.get_frame_count("assist_super") == 49, "all 49 keyed frames are loaded")
		check(game.greg.visible and game.arena_assist.visible, "Greg stays on the arena while Mutki assists")
		check(impacts.count == 0 and game.input_locked, "damage waits for the animation's impact frame")
		check_assist_layout(game)
		await capture("02_arena_windup")
		while impacts.count == 0 and Time.get_ticks_msec() < deadline:
			await process_frame
		check(game.arena_assist.sprite.frame == MutkiArenaAssist.IMPACT_FRAME, "damage lands on the purple wave release frame")
		await capture("03_arena_impact")
		while game.arena_assist.playing and game.arena_assist.sprite.frame < 28 and Time.get_ticks_msec() < deadline:
			await process_frame
		await capture("04_arena_full_wave")
		while game.arena_assist.playing and Time.get_ticks_msec() < deadline:
			await process_frame
		check(impacts.count == 1 and other_impacts.count == 1 and not paused and not game.input_locked and not game.music.stream_paused, "one impact on BOTH sides then controls and music restored")
		game.assist_video._finish()
		check(impacts.count == 1, "late video callback cannot repeat the damage")
		while game._impact_busy:
			await process_frame
		game.queue_free()
		await process_frame

	# P2 plays Greg: his button must trigger the same synchronized move on P1.
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
	host.coop.is_host = true
	host.coop.outbound.connect(guest.coop.receive)
	guest.coop.outbound.connect(host.coop.receive)
	host.coop.choose_hero("mutki")
	guest.coop.choose_hero("greg")
	await create_timer(1.25).timeout
	host.intro_video._finish()
	guest.intro_video._finish()
	await create_timer(0.6).timeout
	var target: EnemyBase = host.spawner.get_target(-1)
	var impacts := {"count": 0}
	target.damaged.connect(func(_enemy, _hp, _max): impacts.count += 1)
	host.coop.charges.greg = 100.0
	host.coop._send_snapshot()
	guest.hud.super_button.pressed.emit()
	check(host.coop.phase == "super_video" and guest.coop.phase == "super_video", "P2 command starts shared video phase")
	check(host.assist_video.playing and guest.assist_video.playing and paused, "both phones play the clip while shared battle is paused")
	var old_position := target.position
	var old_points: int = host.coop.chains.greg.points
	host.coop._set_paused(true)
	guest.coop._set_paused(true)
	var video_position: float = host.assist_video._video.stream_position
	await create_timer(0.3).timeout
	check(is_equal_approx(host.assist_video._video.stream_position, video_position), "network interruption pauses the clip itself")
	host.coop._set_paused(false)
	guest.coop._set_paused(false)
	check(paused, "restoring connection does not resume combat behind the video")
	host.assist_video._finish()
	await create_timer(0.3).timeout
	check(host.coop.phase == "super_video" and paused and guest.assist_video.playing, "one completion callback waits for the other phone")
	check(target.position == old_position and impacts.count == 0 and host.coop.chains.greg.points == old_points, "no damage or score before both videos end")
	guest.assist_video._finish()
	check(host.coop.phase == "super_attack" and host.arena_assist.playing and paused, "both finished starts shared arena animation with combat frozen")
	check(guest.arena_assist.playing and guest.arena_assist.sprite.animation == "assist_super", "guest receives Mutki's purple-wave animation")
	check_assist_layout(host)
	check_assist_layout(guest)
	check(not host.mutki.sprite.visible and not guest.mutki.sprite.visible, "the existing Mutki sprite is hidden to prevent a duplicate hero")
	check(impacts.count == 0, "network super also waits for the impact frame")
	host.coop._set_paused(true)
	guest.coop._set_paused(true)
	var arena_frame: int = host.arena_assist.sprite.frame
	await create_timer(0.4).timeout
	check(host.arena_assist.sprite.frame == arena_frame and impacts.count == 0, "network pause freezes the wave before its impact")
	host.coop._set_paused(false)
	guest.coop._set_paused(false)
	check(paused, "network reconnection keeps the arena frozen until the wave ends")
	var deadline := Time.get_ticks_msec() + 6000
	while host.coop.phase == "super_attack" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(impacts.count == 1 and host.coop.phase == "combat" and not paused, "shared impact applies once and resumes combat")
	check(not guest.arena_assist.playing and host.mutki.sprite.visible and guest.mutki.sprite.visible, "both devices restore the regular Mutki after the assist")
	var earned: int = host.coop.chains.greg.points
	host.coop.on_super_impact()
	guest.assist_video._finish()
	check(impacts.count == 1 and host.coop.chains.greg.points == earned and earned > old_points, "no duplicate impact or points from late messages")
	# The bilateral wave clears the opening group; wait for a real replacement.
	deadline = Time.get_ticks_msec() + 6000
	while host.spawner.get_target() == null and Time.get_ticks_msec() < deadline:
		await process_frame
	# Exiting during a later wave cancels its pending impact and global pause.
	host.greg.face_direction(1)
	host.coop.charges.greg = 100.0
	guest.coop.request_action("super")
	check(host.assist_video.playing, "a later charged activation plays the clip again")
	host.assist_video._finish()
	guest.assist_video._finish()
	check(host.arena_assist.playing, "later activation restarts the wave at frame zero")
	var pending_target: EnemyBase = host.spawner.get_target()
	var pending_hp := pending_target.hp
	host.coop._disconnect("Test disconnect during wave")
	guest.coop._disconnect("Test disconnect during wave")
	await create_timer(0.3).timeout
	check(not paused and not host.assist_video.playing and not guest.assist_video.playing and not host.arena_assist.playing and not guest.arena_assist.playing, "disconnect cancels video and wave without leaving a global pause")
	check(pending_target.hp == pending_hp, "cancelled wave cannot apply its pending hit")
	while host._impact_busy:
		await process_frame
	host.queue_free()
	guest_view.queue_free()
	await process_frame
	print("GREG_SUPER_PASS: actual-video/natural-end/no-skip/no-escape/49-keyed-frames/both-sides/impact-once/P2-trigger/both-phones/no-duplicate-Mutki/video-and-wave-pause/disconnect" if failures.is_empty() else "GREG_SUPER_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
