class_name CoopSession
extends Node

signal outbound(message: Dictionary) # In-process transport seam used by integration tests.

var game: Node
var lobby: CoopLobby
var enabled := false
var is_host := false
var connected := false
var local_hero := ""
var host_hero := ""
var guest_hero := ""
var room_code := ""
var phase := "lobby"
var revision := 0
var round_number := 0
var totals := {"greg": 0, "mutki": 0}
var round_scores := {"greg": 0, "mutki": 0}
var round_start := {"greg": 0, "mutki": 0}
var chains := {"greg": SkillChain.new(), "mutki": SkillChain.new()}
var charges := {"greg": 0.0, "mutki": 0.0}
var ready_players := {"host": false, "guest": false}
var _credited: Dictionary = {}
# Each phone simulates only its own arena. The host coordinates the session.
const MODE := "separate-arenas-v2"
var local_phase := "idle"
var round_states := {"greg": "fighting", "mutki": "fighting"}
var progress := {"greg": {}, "mutki": {}}
var _active_round := 0
var _report_sequence := 0
var _last_report := -1
var _pending_round := false
var _bridge: JavaScriptObject
var _last_send := 0
var _last_receive := 0
var _sequence := 0
var _received_sequence := -1
var _command_sequence := 0
var _last_command := -1
var _started := false
var _selection_open := false
var _start_pending := false
var _remote_visible := true
var _paused := false
var _ended := false
var _story_done := false
var _last_story_ack := 0
var _hud_scores: Label
var test_transport := false
var _browser_test := false
var _super_targets: Array = []
var _super_impact_sent := false
var _video_music_was_paused := false


func setup(owner_game: Node) -> void:
	game = owner_game
	_browser_test = OS.get_cmdline_user_args().has("--coop-test")
	process_mode = Node.PROCESS_MODE_ALWAYS
	lobby = CoopLobby.new()
	game.hud.get_node("Root").add_child(lobby)
	lobby.action_requested.connect(_on_lobby_action)
	game.hud.coop_menu = lobby
	game.wave_manager.round_completed.connect(_on_round_completed)
	_hud_scores = Label.new()
	_hud_scores.position = Vector2(20, 86)
	_hud_scores.size = Vector2(680, 68)
	_hud_scores.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_scores.add_theme_font_size_override("font_size", 23)
	_hud_scores.add_theme_color_override("font_color", Color("68edff"))
	_hud_scores.add_theme_color_override("font_shadow_color", Color("101b25"))
	_hud_scores.add_theme_constant_override("shadow_offset_y", 2)
	_hud_scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_scores.hide()
	game.hud.get_node("Root").add_child(_hud_scores)
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("GregMutkiCoop")
		if _bridge != null:
			var invitation := String(_bridge.inviteCode())
			if not invitation.is_empty():
				lobby.show_connect(invitation)


func _exit_tree() -> void:
	if _bridge != null:
		_bridge.close()
	if get_tree() != null:
		get_tree().paused = false


func _on_lobby_action(action: String, value: String) -> void:
	match action:
		"solo":
			game.hud.set_coop_selection()
			lobby.hide()
		"online":
			lobby.show_connect()
		"menu":
			if enabled:
				game._restart()
			else:
				lobby.show_modes()
		"host", "join":
			if _bridge == null:
				lobby.set_status("Режим на двух телефонах работает в браузерной версии игры. Откройте её на обоих телефонах.")
				return
			enabled = true
			is_host = action == "host"
			_ended = false
			connected = false
			host_hero = ""
			guest_hero = ""
			local_hero = ""
			lobby.set_status("Создаём комнату…" if is_host else "Подключаемся…")
			if is_host:
				_bridge.host()
			else:
				room_code = value.strip_edges().to_upper()
				_bridge.join(room_code)
		"select":
			show_character_selection()
		"copy":
			if _bridge != null:
				_bridge.copyInvite()
		"ready":
			request_action("ready")


func choose_hero(id: String) -> void:
	if not enabled or _started or id not in ["greg", "mutki"]:
		return
	if is_host:
		if id == guest_hero:
			return
		host_hero = id
		local_hero = id
		_refresh_room()
		_maybe_start()
		_send_snapshot()
	elif connected:
		_send({"type": "choose", "hero": id})


func _refresh_room() -> void:
	local_hero = host_hero if is_host else guest_hero
	lobby.update_room(local_hero, guest_hero if is_host else host_hero, connected)
	game.hud.set_coop_selection(host_hero, guest_hero, is_host)


func show_character_selection() -> void:
	_selection_open = true
	lobby.hide()
	game.hud.show_character_select()
	game.hud.set_coop_selection(host_hero, guest_hero, is_host)


func _maybe_start() -> void:
	if _start_pending or not is_host or not connected or host_hero.is_empty() or guest_hero.is_empty() or host_hero == guest_hero:
		return
	_start_pending = true
	# Keep both P1/P2 markers visible before the common story opens.
	await get_tree().create_timer(1.1, false).timeout
	_start_pending = false
	if connected and not _ended and not _started and not host_hero.is_empty() and not guest_hero.is_empty():
		_begin_run()


func _clear_enemies() -> void:
	for enemy in game.spawner.get_children():
		game.spawner.remove_child(enemy)
		enemy.queue_free()
	game.spawner.active_enemies.clear()
	game.spawner.current_enemy = null
	game.spawner._next_spawn_side = 1


func _reset_local_run() -> void:
	_started = true
	_active_round = 0
	_pending_round = false
	local_phase = "idle"
	game.game_over = false
	game.mission_elapsed = 0.0
	game.wave_manager.stop()
	game.wave_manager.wait_between_rounds = true
	_clear_enemies()
	totals = {"greg": 0, "mutki": 0}
	round_scores = totals.duplicate()
	round_start = totals.duplicate()
	charges = {"greg": 0.0, "mutki": 0.0}
	round_states = {"greg": "fighting", "mutki": "fighting"}
	progress = {"greg": {}, "mutki": {}}
	_credited.clear()
	for chain: SkillChain in chains.values():
		chain.clear()
	_activate_fighters()


func _begin_run() -> void:
	if not is_host:
		return
	_reset_local_run()
	round_number = 0
	_change_phase("intro")


func _activate_fighters() -> void:
	local_hero = host_hero if is_host else guest_hero
	game.selected_fighter_id = local_hero
	game.active_fighter = _fighter(local_hero)
	for id in ["greg", "mutki"]:
		var fighter := _fighter(id)
		fighter.network_replica = false
		fighter.deactivate_player()
		fighter.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	game.active_fighter.activate_player()
	game.active_fighter.face_direction(1)
	var config: Dictionary = GameBalance.FIGHTERS[local_hero]
	game.hud.configure_fighter(local_hero, config.display_name, config.attacks.size())
	game.hud._chain_view.position.y = 160
	game.hud.mission_panel.position.y = 280
	_hud_scores.show()
	lobby.hide()


func _fighter(id: String) -> PlayerFighter:
	return game.greg if id == "greg" else game.mutki


func _process(delta: float) -> void:
	if not enabled or _ended:
		return
	var now := Time.get_ticks_msec()
	if _bridge != null:
		var batch = JSON.parse_string(String(_bridge.poll()))
		if batch is Array:
			for event in batch:
				_handle_transport(event)
	if _ended or not connected:
		return
	if not test_transport:
		var silence := now - _last_receive
		if silence > 20000:
			_disconnect("Второй игрок не отвечает. Проверьте интернет и создайте новую комнату.")
			return
		if is_host:
			var local_visible := true if _bridge == null else bool(_bridge.visible())
			_set_paused(silence > 3500 or not _remote_visible or not local_visible)
		elif silence > 3500:
			_set_paused(true)
	if phase in ["intro", "outro"] and _story_done and not _paused:
		var acknowledged := bool(ready_players.host if is_host else ready_players.guest)
		if not acknowledged and now - _last_story_ack >= 500:
			_last_story_ack = now
			request_action("ready")
	if _started and phase == "combat" and local_phase == "combat" and not _paused:
		game.mission_elapsed += delta
		totals[local_hero] += chains[local_hero].advance(delta)
	if _started:
		_update_hud()
	if now - _last_send >= 100:
		_last_send = now
		# Only local test HTML supplies this flag and installs this observer.
		# It lets the browser test aim real inputs without changing gameplay.
		if _browser_test and _bridge != null and _started:
			_bridge.testState(JSON.stringify(_browser_test_state()))
		if is_host:
			_send_snapshot()
		elif _started and phase == "combat":
			_submit_progress()


func _browser_test_state() -> Dictionary:
	var enemies := []
	for enemy: EnemyBase in game.spawner.active_enemies:
		enemies.append({"x": enemy.position.x, "hp": enemy.hp, "state": enemy.state})
	return {"hero": local_hero, "x": game.active_fighter.position.x, "state": game.active_fighter.state,
		"local_phase": local_phase, "enemies": enemies}


func _handle_transport(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"room":
			room_code = str(event.code)
			lobby.show_room(room_code)
			_refresh_room()
		"connected":
			connected = true
			_last_receive = Time.get_ticks_msec()
			if not is_host:
				show_character_selection()
			elif not _selection_open:
				lobby.show_room(room_code)
			_refresh_room()
			if is_host:
				_send_snapshot()
		"message":
			receive(event.data)
		"notice":
			lobby.set_status(str(event.message))
		"error":
			if _started:
				_disconnect(str(event.message))
			else:
				_bridge.close()
				connected = false
				lobby.show_connect(room_code if not is_host else "")
				lobby.set_status(str(event.message))
		"closed":
			_disconnect(str(event.message))


func _send(message: Dictionary, state_update: bool = false) -> void:
	outbound.emit(message.duplicate(true))
	if _bridge != null:
		if state_update:
			_bridge.snapshot(JSON.stringify(message))
		else:
			_bridge.send(JSON.stringify(message))


func receive(message: Dictionary) -> void:
	if not enabled or _ended or not connected:
		return
	_last_receive = Time.get_ticks_msec()
	var type := str(message.get("type", ""))
	if type == "presence":
		_remote_visible = bool(message.get("visible", true))
		return
	if type == "rejected":
		_disconnect(str(message.get("reason", "Версии игры отличаются.")))
		return
	if not is_host:
		if type == "snapshot":
			_apply_snapshot(message)
		return
	if type == "choose" and not _started:
		var id := str(message.get("hero", ""))
		if id in ["greg", "mutki"] and id != host_hero:
			guest_hero = id
			_refresh_room()
			_maybe_start()
		_send_snapshot()
	elif type == "progress" and phase == "combat":
		_accept_progress(message)
	elif type == "command" and _started:
		var serial := int(message.get("sequence", -1))
		if serial <= _last_command or int(message.get("revision", -1)) != revision:
			return
		_last_command = serial
		# Only session actions cross the network; attacks stay on the sender's phone.
		_session_action("guest", str(message.get("action", "")))


func request_action(action: String, attack: int = -1, direction: int = 0) -> void:
	if not enabled or not connected or _ended or _paused or not _started:
		return
	if action in ["attack", "face", "super"]:
		_local_action(action, attack, direction)
	elif is_host:
		_session_action("host", action)
	else:
		_command_sequence += 1
		_send({"type": "command", "sequence": _command_sequence, "revision": revision, "action": action})


func _session_action(player: String, action: String) -> void:
	if _paused or _ended:
		return
	if action == "ready" and phase in ["intro", "round", "outro", "complete", "failed"]:
		ready_players[player] = true
		_update_ready()
		if ready_players.host and ready_players.guest:
			_advance_phase()
		_send_snapshot()
	elif action == "exit" and phase == "exit":
		_change_phase("outro")


func _local_action(action: String, attack: int, direction: int) -> void:
	if phase != "combat" or local_phase != "combat" or _fighter(local_hero).state != "idle":
		return
	var fighter := _fighter(local_hero)
	if action == "face":
		fighter.face_direction(clampi(direction, -1, 1))
	elif action == "attack":
		if attack < -1 or attack >= GameBalance.FIGHTERS[local_hero].attacks.size():
			return
		if direction != 0:
			fighter.face_direction(clampi(direction, -1, 1))
		if fighter.try_attack(attack):
			game._play_sfx(game.attack_sfx, 1.0)
	elif action == "super" and float(charges[local_hero]) >= 100.0:
		_super_targets.clear()
		for enemy: EnemyBase in game.spawner.active_enemies:
			if enemy.hp > 0 and (local_hero == "greg" or enemy.approach_side == fighter.facing_direction):
				_super_targets.append(enemy)
		if _super_targets.is_empty():
			return
		charges[local_hero] = 0.0
		_super_impact_sent = false
		if local_hero == "greg":
			local_phase = "super_video"
			_video_music_was_paused = game.music.stream_paused
			game.music.stream_paused = true
			if not game.assist_video.play_helper("mutki"):
				on_super_video_finished.call_deferred()
			_sync_pause()
		else:
			fighter.try_attack(0)
			local_phase = "super_attack"
			on_super_impact()
			on_super_animation_finished()


func on_hit(enemy: Node, fighter: PlayerFighter) -> void:
	if _ended or phase != "combat" or fighter != game.active_fighter or round_states[local_hero] != "fighting":
		return
	var chain: SkillChain = chains[local_hero]
	chain.hit()
	if is_instance_valid(enemy) and enemy.hp <= 0 and not _credited.has(enemy.get_instance_id()):
		_credited[enemy.get_instance_id()] = true
		chain.add_bonus(int(GameBalance.ENEMIES[enemy.enemy_id].score))
	if chain.hits >= 2:
		charges[local_hero] = minf(100.0, float(charges[local_hero]) + float(GameBalance.SUPER.charge_per_combo_hit) * chain.multiplier)
	game._play_sfx(game.hit_sfx, 1.0)
	game._impact(0.035, 5.0, Color(1.0, 0.88, 0.58, 0.22))


func on_damage(fighter: PlayerFighter) -> void:
	if fighter != game.active_fighter:
		return
	chains[local_hero].clear()
	game._play_sfx(game.hit_sfx, 0.9)


func on_death(fighter: PlayerFighter) -> void:
	if phase != "combat" or fighter != game.active_fighter or round_states[local_hero] != "fighting":
		return
	game._play_sfx(game.fall_sfx, 0.86)
	game.spawner.stop_combat()
	game.wave_manager.abandon_round()
	_finish_local_round("fallen")


func _local_progress() -> Dictionary:
	return {"score": int(totals[local_hero]), "hp": _fighter(local_hero).hp,
		"defeated": game.wave_manager._total_defeated, "status": round_states[local_hero],
		"activity": local_phase, "charge": float(charges[local_hero]), "elapsed": game.mission_elapsed}


func _submit_progress() -> void:
	progress[local_hero] = _local_progress()
	if is_host:
		_maybe_finish_round()
		_send_snapshot()
	else:
		_report_sequence += 1
		_send({"type": "progress", "sequence": _report_sequence, "revision": revision, "value": progress[local_hero].duplicate()})


func _accept_progress(message: Dictionary) -> void:
	var serial := int(message.get("sequence", -1))
	if serial <= _last_report or int(message.get("revision", -1)) != revision or not message.get("value") is Dictionary:
		return
	var value: Dictionary = message.value
	var status := str(value.get("status", ""))
	var points := int(value.get("score", -1))
	var defeated := int(value.get("defeated", -1))
	var health := int(value.get("hp", -1))
	var expected := 0
	for index in round_number:
		expected += GameBalance.WAVES[index].size()
	if status not in ["fighting", "cleared", "fallen"] or points < int(totals[guest_hero]) or points > 100000000:
		return
	if defeated < 0 or defeated > expected or health < 0 or health > int(GameBalance.FIGHTERS[guest_hero].max_hp):
		return
	if (status == "fallen" and health != 0) or (status == "cleared" and health <= 0):
		return
	if round_states[guest_hero] != "fighting":
		return
	_last_report = serial
	# This friendly score race trusts each phone's own combat. No remote actor,
	# health value or hit can mutate the local arena.
	totals[guest_hero] = points
	progress[guest_hero] = {"score": points, "hp": health, "defeated": defeated, "status": status,
		"activity": str(value.get("activity", "combat")), "charge": clampf(float(value.get("charge", 0.0)), 0.0, 100.0),
		"elapsed": maxf(0.0, float(value.get("elapsed", 0.0)))}
	round_states[guest_hero] = status
	_maybe_finish_round()


func _finish_local_round(status: String) -> void:
	if round_states[local_hero] != "fighting":
		return
	totals[local_hero] += chains[local_hero].bank()
	round_states[local_hero] = status
	local_phase = "waiting"
	game.input_locked = true
	_show_local_wait()
	_submit_progress()


func _on_round_completed(_number: int) -> void:
	if not enabled or phase != "combat":
		return
	if local_phase in ["super_video", "super_attack"]:
		_pending_round = true
		return
	_finish_local_round("cleared")


func _maybe_finish_round() -> void:
	if not is_host or phase != "combat" or "fighting" in round_states.values():
		return
	for id in ["greg", "mutki"]:
		round_scores[id] = int(totals[id]) - int(round_start[id])
	_change_phase("failed" if round_states.greg == "fallen" and round_states.mutki == "fallen" else "round")


func story_finished() -> void:
	if _ended or _story_done or phase not in ["intro", "outro"]:
		return
	_story_done = true
	lobby.show_wait("Второй игрок досматривает сюжет…")
	_last_story_ack = Time.get_ticks_msec()
	request_action("ready")
	_sync_pause()


func _change_phase(next_phase: String) -> void:
	phase = next_phase
	revision += 1
	ready_players = {"host": false, "guest": false}
	_story_done = false
	_render_phase()
	_send_snapshot()


func _advance_phase() -> void:
	match phase:
		"intro":
			round_number = 1
			_change_phase("combat")
		"round":
			if round_number < MissionData.WAVE_COUNT:
				round_number += 1
				round_start = totals.duplicate()
				round_states = {"greg": "fighting", "mutki": "fighting"}
				_change_phase("combat")
			else:
				_change_phase("exit")
		"outro":
			_change_phase("complete")
		"complete", "failed":
			_begin_run()


func _start_local_round() -> void:
	if _active_round == round_number:
		return
	_active_round = round_number
	local_phase = "combat"
	_pending_round = false
	if game.active_fighter.hp <= 0:
		_clear_enemies()
		game.active_fighter.activate_player()
		game.active_fighter.hp = ceili(float(GameBalance.FIGHTERS[local_hero].max_hp) * 0.5)
		game.active_fighter.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	_sync_pause()
	if round_number == 1:
		game.wave_manager.start_run(MissionData.WAVE_COUNT)
	else:
		game.wave_manager.continue_after_round()


func waves_completed() -> void:
	# The shared coordinator alone advances after BOTH local wave barriers.
	pass


func _show_local_wait() -> void:
	lobby.show_wait("ТВОЙ РАУНД ЗАВЕРШЁН" if _fighter(local_hero).hp > 0 else "ТЫ ПОВЕРЖЕН", "Второй игрок ещё сражается на своей арене.")


func _render_phase() -> void:
	if phase != "intro":
		game.cancel_intro()
	game.hud.hide_message()
	game.hud.hide_exit()
	if phase not in ["intro", "outro"]:
		game.hud.story_panel.hide()
	lobby.hide()
	match phase:
		"intro":
			game.mission_phase = "intro"
			if _story_done:
				lobby.show_wait("Второй игрок досматривает сюжет…")
			else:
				game.play_intro()
				game.intro_video.set_suspended(_paused)
		"outro":
			game.hud.show_story(MissionData.OUTRO, false)
		"combat":
			_start_local_round()
			game.hud.get_node("Root/BottomPanel").show()
			if local_phase == "waiting":
				_show_local_wait()
		"round":
			lobby.show_results("РАУНД %d / %d ЗАВЕРШЁН" % [round_number, MissionData.WAVE_COUNT], round_scores, totals)
		"exit":
			game.wave_manager.stop()
			game.spawner.stop_combat()
			game.hud.show_exit()
		"complete":
			lobby.show_results("СОРЕВНОВАНИЕ ЗАВЕРШЕНО!", round_scores, totals, true)
		"failed":
			game.wave_manager.stop()
			game.spawner.stop_combat()
			lobby.show_results("ОБА ГЕРОЯ ПОВЕРЖЕНЫ", round_scores, totals)
			lobby.set_status("Подтвердите готовность, чтобы начать новую попытку.")
	_sync_pause()
	_update_ready()


func _sync_pause() -> void:
	game.mission_phase = local_phase if phase == "combat" and local_phase in ["super_video", "super_attack"] else phase
	game.input_locked = _paused or phase != "combat" or local_phase != "combat"
	get_tree().paused = _paused or phase == "intro" or (phase == "combat" and local_phase in ["super_video", "super_attack"])


func _update_ready() -> void:
	lobby.set_ready_state(bool(ready_players.host if is_host else ready_players.guest), bool(ready_players.guest if is_host else ready_players.host))


func _update_hud() -> void:
	var fighter := _fighter(local_hero)
	var chain: SkillChain = chains[local_hero]
	game.hud.set_hp(fighter.hp, int(GameBalance.FIGHTERS[local_hero].max_hp))
	game.hud.set_score(int(totals[local_hero]))
	game.hud.set_super(float(charges[local_hero]))
	game.hud.set_skill_chain(chain.points, chain.multiplier, chain.hits, chain.remaining / SkillChain.BANK_DELAY)
	game.hud.super_button.disabled = float(charges[local_hero]) < 100.0 or game.input_locked
	var opponent := "mutki" if local_hero == "greg" else "greg"
	var other_status := "сражается" if round_states[opponent] == "fighting" else "закончил раунд"
	_hud_scores.text = "ГРИША  %d    •    МУТКИ  %d\nТвоя арена · %s %s" % [totals.greg, totals.mutki, "Мутки" if opponent == "mutki" else "Гриша", other_status]
	if phase == "combat" and local_phase == "waiting" and lobby.screen == "wait":
		lobby.set_status("Твой счёт: %d · Счёт соперника: %d\nОн ещё сражается на своей арене." % [totals[local_hero], totals[opponent]])


func _set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	_sync_pause()
	game.intro_video.set_suspended(value)
	game.assist_video.set_suspended(value)
	game.arena_assist.set_suspended(value)
	if value:
		lobby.show_connection_problem("Вернитесь в игру на обоих телефонах. Сессия продолжится после восстановления связи.")
	elif phase in ["intro", "outro"]:
		if _story_done:
			lobby.show_wait("Второй игрок досматривает сюжет…")
		else:
			lobby.hide()
	elif _started:
		_render_phase()
	elif _selection_open:
		show_character_selection()
	else:
		lobby.show_room(room_code)
		_refresh_room()


func _disconnect(message: String) -> void:
	_ended = true
	connected = false
	game.cancel_intro()
	game.assist_video.cancel()
	game.arena_assist.cancel()
	game.mutki.sprite.show()
	game.music.stream_paused = false
	if _bridge != null:
		_bridge.close()
	game.input_locked = true
	game.wave_manager.stop()
	game.spawner.stop_combat()
	for fighter: PlayerFighter in [game.greg, game.mutki]:
		fighter._deactivate_hit_box()
		fighter.sprite.pause()
	get_tree().paused = false
	lobby.show_connection_problem(message, true)


func on_super_video_finished() -> void:
	if _ended or phase != "combat" or local_phase != "super_video":
		return
	local_phase = "super_attack"
	game._begin_mutki_assist()
	_sync_pause()


func on_super_impact() -> void:
	if _ended or phase != "combat" or local_phase != "super_attack" or _super_impact_sent:
		return
	_super_impact_sent = true
	for enemy: EnemyBase in _super_targets:
		if is_instance_valid(enemy) and enemy.hp > 0:
			enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
			on_hit(enemy, game.active_fighter)
	chains[local_hero].add_bonus(500)
	game._impact(0.055, 13.0, Color(0.55, 0.25, 1.0, 0.45))


func on_super_animation_finished() -> void:
	if _ended or phase != "combat" or local_phase != "super_attack":
		return
	_super_targets.clear()
	game.music.stream_paused = _video_music_was_paused
	local_phase = "combat"
	_sync_pause()
	if _pending_round:
		_pending_round = false
		_finish_local_round("cleared")


func make_snapshot() -> Dictionary:
	_sequence += 1
	if _started:
		progress[local_hero] = _local_progress()
	return {"type": "snapshot", "mode": MODE, "sequence": _sequence, "host": host_hero, "guest": guest_hero, "phase": phase, "revision": revision,
		"round": round_number, "totals": totals.duplicate(), "round_scores": round_scores.duplicate(), "round_start": round_start.duplicate(),
		"ready": ready_players.duplicate(), "paused": _paused, "round_states": round_states.duplicate(), "progress": progress.duplicate(true)}


func _send_snapshot() -> void:
	if is_host and connected:
		_send(make_snapshot(), true)


func _apply_snapshot(data: Dictionary) -> void:
	if data.get("mode", "") != MODE:
		_disconnect("Версии сетевого режима отличаются. Обновите игру на обоих телефонах.")
		return
	var serial := int(data.get("sequence", -1))
	if serial <= _received_sequence:
		return
	_received_sequence = serial
	host_hero = str(data.get("host", ""))
	guest_hero = str(data.get("guest", ""))
	_refresh_room()
	if data.get("phase", "lobby") == "lobby" or host_hero not in ["greg", "mutki"] or guest_hero not in ["greg", "mutki"] or host_hero == guest_hero:
		return
	var changed := revision != int(data.revision)
	if changed and data.phase == "intro":
		_reset_local_run()
	elif not _started:
		return
	revision = int(data.revision)
	phase = str(data.phase)
	round_number = int(data.round)
	# Never roll back locally earned points with a delayed echo from the host.
	totals[host_hero] = int(data.totals[host_hero])
	if phase != "combat":
		totals[local_hero] = int(data.totals[local_hero])
	round_scores = data.round_scores.duplicate()
	round_start = data.round_start.duplicate()
	progress[host_hero] = data.progress[host_hero].duplicate()
	round_states[host_hero] = data.round_states[host_hero]
	if changed:
		round_states[local_hero] = data.round_states[local_hero]
	ready_players = data.ready.duplicate()
	if changed:
		_story_done = false
		_render_phase()
	_update_ready()
	_set_paused(bool(data.paused))
	if _paused and lobby.screen != "paused":
		lobby.show_connection_problem("Вернитесь в игру на обоих телефонах.")
