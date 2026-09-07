extends SceneTree

var failures: Array[String] = []
var host: Node
var guest: Node
var capture_mode := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("COOP_TEST_FAIL: " + message)


func capture(label: String) -> void:
	if not capture_mode:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/coop/" + label + ".png")


func _run() -> void:
	capture_mode = OS.get_cmdline_user_args().has("--capture")
	var host_hero := "mutki" if OS.get_cmdline_user_args().has("--host-mutki") else "greg"
	var guest_hero := "greg" if host_hero == "mutki" else "mutki"
	if capture_mode:
		DirAccess.make_dir_recursive_absolute("res://artifacts/coop")
		root.size = Vector2i(720, 1280)
		root.content_scale_size = Vector2i(720, 1280)
	var scene: PackedScene = load("res://scenes/Main.tscn")
	host = scene.instantiate()
	root.add_child(host)
	current_scene = host
	await process_frame
	check(not host.hud._player_tags.greg.visible and not host.hud._player_tags.mutki.visible, "solo selection has no player labels")
	await capture("01_modes")
	host.coop.lobby.show_connect()
	await capture("02_connect")
	# A separate physics world proves the guest cannot damage host combat actors.
	var guest_view := SubViewport.new()
	guest_view.size = Vector2i(720, 1280)
	guest_view.world_2d = World2D.new()
	root.add_child(guest_view)
	guest = scene.instantiate()
	guest_view.add_child(guest)
	for session: CoopSession in [host.coop, guest.coop]:
		session.enabled = true
		session.connected = true
		session.test_transport = true
		session.room_code = "ABC234"
		session.lobby.show_room("ABC234")
	host.coop.is_host = true
	host.coop.outbound.connect(guest.coop.receive)
	guest.coop.outbound.connect(host.coop.receive)
	host.coop.show_character_selection()
	guest.coop.show_character_selection()
	host.coop.choose_hero(host_hero)
	guest.coop.choose_hero(host_hero)
	check(host.coop.guest_hero.is_empty(), "same hero cannot be claimed by both phones")
	await capture("03_room")
	guest.coop.choose_hero(guest_hero)
	check(host.hud._player_tags[host_hero].text == "P1" and host.hud._player_tags[guest_hero].text == "P2", "P1 identifies host and P2 guest on original artwork")
	check(guest.hud._player_tags[host_hero].text == "P1" and guest.hud._player_tags[guest_hero].text == "P2", "both phones show the same ownership labels")
	await capture("03_selection_p1_greg")
	host.hud.set_coop_selection("mutki", "greg", true)
	check(host.hud._player_tags.mutki.text == "P1" and host.hud._player_tags.greg.text == "P2", "host may choose Mutki and remains P1")
	await capture("03_selection_p1_mutki")
	host.hud.set_coop_selection(host_hero, guest_hero, true)
	await create_timer(1.2).timeout
	check(host.coop.phase == "intro" and guest.coop.phase == "intro", "both choices start one shared intro")
	check(host.greg.player_enabled and host.mutki.player_enabled, "both heroes are present on host")
	check(guest.mutki.network_replica and guest.selected_fighter_id == guest_hero, "guest controls selected hero as a replica")
	host.hud.story_panel._finish()
	check(host.coop.phase == "intro", "one player cannot start combat before teammate is ready")
	guest.hud.story_panel._finish()
	check(host.coop.phase == "combat", "both ready starts combat")
	var old_revision: int = host.coop.revision - 1
	host.coop.receive({"type": "command", "sequence": 500, "revision": old_revision, "action": "ready"})
	check(host.coop._last_command < 500, "stale phase commands are ignored")
	await create_timer(0.6).timeout
	await capture("04_combat")
	check(guest.spawner.active_enemies.is_empty() and guest.coop._replicas.size() == 3, "guest displays shared enemies without running its own spawns")
	var snapshots_before: int = host.coop._sequence
	guest.coop.receive({"type": "snapshot", "sequence": -1})
	check(host.coop._sequence == snapshots_before, "out-of-order state is ignored")
	var accumulated := {"greg": 0, "mutki": 0}
	var deadline := Time.get_ticks_msec() + 90000
	var rounds := 0
	while rounds < 3 and Time.get_ticks_msec() < deadline:
		if host.coop.phase == "combat":
			for id in ["greg", "mutki"]:
				var fighter: PlayerFighter = host.coop._fighter(id)
				var target: EnemyBase = null
				var distance := INF
				for enemy: EnemyBase in host.spawner.active_enemies:
					var gap := absf(enemy.position.x - fighter.position.x)
					if enemy.state != "dead" and gap < distance:
						target = enemy
						distance = gap
				if target != null and distance < 235.0 and fighter.state == "idle":
					var session: CoopSession = host.coop if id == host_hero else guest.coop
					session.request_action("attack", -1, signi(int(target.position.x - fighter.position.x)))
		elif host.coop.phase == "round":
			rounds += 1
			for id in ["greg", "mutki"]:
				accumulated[id] += host.coop.round_scores[id]
			check(host.coop.totals == accumulated, "round points add to cumulative totals")
			check(host.coop.totals == guest.coop.totals and guest.coop.phase == "round", "both devices display identical round results")
			await capture("05_round_%d" % rounds)
			var spawn_count: int = host.wave_manager.spawned_count
			host.coop.request_action("ready")
			await create_timer(0.5).timeout
			check(host.coop.phase == "round" and host.wave_manager.spawned_count == spawn_count, "round waits without spawning until both ready")
			guest.coop.request_action("ready")
		elif host.coop.phase == "failed":
			check(false, "both heroes survive the automated cooperative mission")
			break
		await create_timer(0.025).timeout
	check(rounds == 3 and host.coop.phase == "exit", "three shared rounds lead to story exit")
	check(host.wave_manager._total_defeated == 18, "exactly 18 shared enemies defeated")
	check(host.coop.totals.greg > 0 and host.coop.totals.mutki > 0, "each hero earns their own score")
	guest.coop.request_action("exit")
	check(host.coop.phase == "outro" and guest.coop.phase == "outro", "either phone can inspect the common exit")
	host.hud.story_panel._finish()
	check(host.coop.phase == "outro", "ending also waits for both players")
	guest.hud.story_panel._finish()
	check(host.coop.phase == "complete" and guest.coop.phase == "complete", "both receive the final winner screen")
	await capture("06_final")
	host.coop.request_action("ready")
	guest.coop.request_action("ready")
	check(host.coop.phase == "intro" and host.coop.totals.greg == 0 and host.coop.totals.mutki == 0, "replay in same room resets scores and story")
	host.hud.story_panel._finish()
	guest.hud.story_panel._finish()
	host.mutki.take_damage(9999)
	check(host.coop.phase == "combat" and host.greg.position.x == GameBalance.PLAYER_X, "one fallen hero leaves teammate able to finish")
	host.greg.take_damage(9999)
	check(host.coop.phase == "failed" and not host.wave_manager.running, "both fallen stop the shared mission")
	host.coop._set_paused(true)
	check(paused and host.coop.lobby.screen == "paused", "connection pause stops simulation")
	host.coop._set_paused(false)
	check(not paused and host.coop.lobby.screen == "round", "resuming restores result screen")
	host.coop._disconnect("Test disconnect")
	check(host.coop.lobby.screen == "error" and not host.coop.connected, "disconnect offers a safe return to menu")
	host.queue_free()
	guest_view.queue_free()
	await process_frame
	print("COOP_TEST_PASS: two-worlds/hero-ownership/real-combat/3-rounds/scores/barriers/replay/death/disconnect" if failures.is_empty() else "COOP_TEST_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
