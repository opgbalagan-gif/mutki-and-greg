extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("COOP_SUPER_FAIL: " + message)

func _run() -> void:
	var hero := "mutki" if OS.get_cmdline_user_args().has("--guest-mutki") else "greg"
	var opponent := "greg" if hero == "mutki" else "mutki"
	var scene: PackedScene = load("res://scenes/Main.tscn")

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
	host.coop.choose_hero(opponent)
	guest.coop.choose_hero(hero)
	await create_timer(1.25).timeout
	host.intro_video._finish()
	guest.intro_video._finish()
	await create_timer(0.6).timeout
	var target: EnemyBase = guest.spawner.get_target(-1)
	var host_target: EnemyBase = host.spawner.get_target(-1)
	var host_hp := host_target.hp
	var impacts := {"count": 0}
	target.damaged.connect(func(_enemy, _hp, _max): impacts.count += 1)
	guest.coop.charges[hero] = 100.0
	guest.hud.super_button.pressed.emit()
	check(guest.coop.local_phase == "super_video" and host.coop.local_phase == "combat", "P2's super belongs only to P2's arena")
	check(guest.assist_video.playing and not host.assist_video.playing, "only the initiating phone shows its super clip")
	host.coop._set_paused(true)
	guest.coop._set_paused(true)
	var video_position: float = guest.assist_video._video.stream_position
	await create_timer(0.3).timeout
	check(is_equal_approx(guest.assist_video._video.stream_position, video_position), "network interruption pauses the local clip")
	host.coop._set_paused(false)
	guest.coop._set_paused(false)
	guest.assist_video._finish()
	check(guest.arena_assist.playing and not host.arena_assist.playing, "only P2 renders the arena move")
	check(guest.arena_assist.fighter_id == hero and not guest.active_fighter.sprite.visible, "local hero owns the move without duplicate body")
	check(impacts.count == 0, "local super waits for its impact frame")
	host.coop._set_paused(true)
	guest.coop._set_paused(true)
	var arena_frame: int = guest.arena_assist.sprite.frame
	await create_timer(0.4).timeout
	check(guest.arena_assist.sprite.frame == arena_frame and impacts.count == 0, "network pause freezes the local move")
	host.coop._set_paused(false)
	guest.coop._set_paused(false)
	var deadline := Time.get_ticks_msec() + 6000
	while guest.coop.local_phase == "super_attack" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(impacts.count == 1 and not paused, "P2's move hits once and releases its pause")
	check(host_target.hp == host_hp and host.coop.chains[opponent].points == 0, "P2's move cannot damage host enemies or credit host points")
	var earned: int = guest.coop.chains[hero].points
	guest.coop.on_super_impact(1)
	guest.assist_video._finish()
	check(impacts.count == 1 and guest.coop.chains[hero].points == earned, "late callbacks do not duplicate local points")
	host.coop._disconnect("Test disconnect")
	guest.coop._disconnect("Test disconnect")
	check(not paused and not guest.arena_assist.playing, "disconnect cleans up local special and pause")
	while host._impact_busy or guest._impact_busy:
		await process_frame
	host.queue_free()
	guest_view.queue_free()
	await process_frame
	print("COOP_SUPER_PASS: independent-P2-super/own-enemies/impact-once/pause/disconnect" if failures.is_empty() else "COOP_SUPER_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
