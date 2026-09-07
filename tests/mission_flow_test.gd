extends SceneTree

var failures: Array[String] = []
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MISSION_TEST_FAIL: " + message)


func _run() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.mission_phase == "select", "starts at character selection")
	var fighter_id := "mutki" if OS.get_cmdline_user_args().has("--mutki") else "greg"
	game.hud.character_selected.emit(fighter_id)
	check(game.mission_phase == "intro" and game.input_locked, "intro blocks combat")
	await create_timer(0.5).timeout
	check(game.spawner.active_enemies.is_empty(), "no enemies spawn behind story cards")
	game.hud.story_panel.next_slide()
	check(game.hud.story_panel.slide_index == 1, "story next navigation")
	game.hud.story_panel.previous_slide()
	check(game.hud.story_panel.slide_index == 0, "story back navigation")
	game.hud.story_panel.skip_button.pressed.emit()
	check(game.mission_phase == "combat" and not game.input_locked, "skip starts mission")
	await create_timer(0.45).timeout
	check(game.spawner.active_enemies.size() == 3, "opening group fills")
	var fighter: PlayerFighter = game.active_fighter
	game._try_attack(-1, -1)
	check(fighter.facing_direction == -1 and fighter.sprite.flip_h and fighter.hit_box.position.x < 0, "left attack faces and hits left")
	game._try_attack(-1, 1)
	check(fighter.facing_direction == -1, "repeated tap cannot turn a committed attack")
	game.super_charge = 100.0
	game._try_super()
	check(game.super_charge == 100.0 and not game.input_locked, "busy special request preserves charge and input")
	var deadline := Time.get_ticks_msec() + 5000
	while fighter.state != "idle" and Time.get_ticks_msec() < deadline:
		await process_frame
	var right_key := InputEventKey.new()
	right_key.keycode = KEY_D
	right_key.pressed = true
	game._unhandled_input(right_key)
	var right_idle_flipped := false # Both video idles are normalized to face right.
	check(fighter.facing_direction == 1 and fighter.sprite.flip_h == right_idle_flipped and fighter.hit_box.position.x > 0, "D turns idle fighter and hitbox right")
	fighter.face_direction(-1)
	check(fighter.sprite.flip_h != right_idle_flipped and fighter.hit_box.position.x < 0, "idle art turns left after returning from attack")
	fighter.face_direction(1)
	check(game._screen_direction(0) == -1 and game._screen_direction(719) == 1, "touch sides respect viewport center")
	# Complete the mission through real hit windows, enemy animations and signals.
	# No healing or direct enemy damage: this also checks the first-mission balance.
	deadline = Time.get_ticks_msec() + 90000
	while game.mission_phase == "combat" and Time.get_ticks_msec() < deadline:
		var target: EnemyBase = game.spawner.get_target()
		if is_instance_valid(target) and fighter.state == "idle":
			if absf(target.position.x - fighter.position.x) <= 235.0:
				game._try_attack(-1, target.approach_side)
		await create_timer(0.025).timeout
	check(game.mission_phase == "exit", "all three waves reach an explicit exit")
	check(not game.wave_manager.running and game.input_locked, "waves and combat stop at exit")
	check(game.wave_manager._total_defeated == 18, "mission defeats exactly eighteen enemies")
	await create_timer(0.8).timeout
	check(game.spawner.active_enemies.is_empty(), "no fourth wave or late respawn")
	game.hud.exit_button.pressed.emit()
	check(game.mission_phase == "outro" and game.hud.story_panel.visible, "exit opens ending")
	check(not game.hud.story_panel.skip_button.visible, "ending has no intro skip button")
	for card_index in MissionData.OUTRO.size():
		check(game.mission_phase == "outro" and game.input_locked, "ending stays locked until the final card")
		check(game.hud.story_panel.artwork.texture != null, "ending artwork loads")
		game.hud.story_panel.next_slide()
	check(game.mission_phase == "complete" and game.hud.message_panel.visible, "ending shows mission result")
	game._on_greg_super_finished()
	check(game.input_locked, "late super callback cannot unlock completed mission")
	game.queue_free()
	await process_frame
	# Replay starts a fresh mission and death cannot be undone by late callbacks.
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.hud.character_selected.emit(fighter_id)
	for card_index in MissionData.INTRO.size():
		check(game.mission_phase == "intro" and game.input_locked, "reading the full intro blocks combat")
		check(game.hud.story_panel.artwork.texture != null, "intro artwork loads")
		game.hud.story_panel.next_slide()
	check(game.mission_phase == "combat" and not game.input_locked, "last intro card starts combat")
	await create_timer(0.45).timeout
	game.active_fighter.take_damage(9999)
	check(game.mission_phase == "failed" and not game.wave_manager.running, "death fails and stops mission")
	check(not game.hud.message_panel.visible, "result panel leaves the fall visible")
	game._on_greg_super_finished()
	await create_timer(0.7).timeout
	check(game.input_locked and game.mission_phase == "failed", "death remains locked after async callbacks")
	var result_deadline := Time.get_ticks_msec() + 4000
	while not game.hud.message_panel.visible and Time.get_ticks_msec() < result_deadline:
		await process_frame
	check(game.hud.message_panel.visible, "defeat result appears after the full fall")
	var fallen: AnimatedSprite2D = game.active_fighter.sprite
	check(fallen.animation == "death_video" and fallen.frame == fallen.sprite_frames.get_frame_count("death_video") - 1, "fall reaches its final frame before defeat result")
	if failures.is_empty():
		print("MISSION_TEST_PASS: ", fighter_id, " intro/navigation/turn-lock/special/full-combat/18-enemies/exit/ending/replay/death")
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
