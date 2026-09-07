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
var _replicas: Dictionary = {}
var _bridge: JavaScriptObject
var _last_send := 0
var _last_receive := 0
var _sequence := 0
var _received_sequence := -1
var _command_sequence := 0
var _last_command := -1
var _next_enemy_id := 0
var _started := false
var _selection_open := false
var _start_pending := false
var _remote_visible := true
var _paused := false
var _ended := false
var _story_done := false
var _hud_scores: Label
var test_transport := false
var _super_targets: Array = []
var _super_impact_sent := false
var _video_revision := -1
var _super_video_done := false
var _video_music_was_paused := false
var _last_video_ack := 0


func setup(owner_game: Node) -> void:
	game = owner_game
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


func _begin_run() -> void:
	_started = true
	game.game_over = false
	game.mission_elapsed = 0.0
	totals = {"greg": 0, "mutki": 0}
	round_scores = totals.duplicate()
	round_start = totals.duplicate()
	charges = {"greg": 0.0, "mutki": 0.0}
	_credited.clear()
	for chain: SkillChain in chains.values():
		chain.clear()
	for enemy in game.spawner.get_children():
		enemy.queue_free()
	game.spawner.active_enemies.clear()
	game.spawner.current_enemy = null
	game.spawner._next_spawn_side = 1
	game.wave_manager.wait_between_rounds = true
	round_number = 0
	_activate_fighters()
	_change_phase("intro")


func _activate_fighters() -> void:
	local_hero = host_hero if is_host else guest_hero
	game.selected_fighter_id = local_hero
	game.active_fighter = _fighter(local_hero)
	for id in ["greg", "mutki"]:
		var fighter := _fighter(id)
		fighter.network_replica = not is_host
		fighter.activate_player()
		fighter.position = Vector2(290 if id == "greg" else 430, GameBalance.GROUND_Y)
		fighter.face_direction(-1 if id == "greg" else 1)
		fighter.z_index = 1 if id == local_hero else 0
		if not is_host:
			fighter.hurt_box.set_deferred("monitorable", false)
	game.hud.configure_fighter(local_hero, GameBalance.FIGHTERS[local_hero].display_name, 0)
	game.hud.special_name = "СУПЕРУДАР"
	var portrait := AtlasTexture.new()
	portrait.atlas = load(MissionData.CANONICAL_ART)
	portrait.region = Rect2(95, 70, 320, 325) if local_hero == "greg" else Rect2(410, 85, 300, 340)
	game.hud.super_button.portrait = portrait
	game.hud.super_button.ready_caption = "СУПЕР"
	game.hud.super_button.tooltip_text = "Помощь Мутки: волна в обе стороны" if local_hero == "greg" else "Суперудар по врагам выбранной стороны"
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
			_disconnect("Напарник не отвечает. Проверьте интернет и создайте новую комнату.")
			return
		if is_host:
			var local_visible := true if _bridge == null else bool(_bridge.visible())
			_set_paused(silence > 3500 or not _remote_visible or not local_visible)
		elif silence > 3500:
			_set_paused(true)
	if phase == "super_video" and _super_video_done and not _paused:
		var acknowledged := bool(ready_players.host if is_host else ready_players.guest)
		if not acknowledged and now - _last_video_ack >= 500:
			_notify_video_done()
	if is_host and _started and phase == "combat" and not _paused:
		game.mission_elapsed += delta
		for id: String in chains:
			totals[id] += chains[id].advance(delta)
	if _started:
		_update_hud()
	if is_host and now - _last_send >= 50:
		_last_send = now
		_send_snapshot()


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
		_disconnect(str(message.get("reason", "Комната занята.")))
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
	elif type == "command" and _started:
		var serial := int(message.get("sequence", -1))
		if serial <= _last_command or int(message.get("revision", -1)) != revision:
			return
		_last_command = serial
		# The guest never supplies a fighter identity, score, health or game state.
		_execute_action("guest", str(message.get("action", "")), int(message.get("attack", -1)), int(message.get("direction", 0)))


func request_action(action: String, attack: int = -1, direction: int = 0) -> void:
	if not enabled or not connected or _ended or _paused or not _started:
		return
	if is_host:
		_execute_action("host", action, attack, direction)
	else:
		_command_sequence += 1
		_send({"type": "command", "sequence": _command_sequence, "revision": revision, "action": action, "attack": attack, "direction": direction})


func _execute_action(player: String, action: String, attack: int, direction: int) -> void:
	if _paused or _ended:
		return
	var id := host_hero if player == "host" else guest_hero
	if action == "video_done" and phase == "super_video":
		ready_players[player] = true
		if ready_players.host and ready_players.guest:
			_begin_super_animation()
		_send_snapshot()
		return
	if action == "ready" and phase in ["intro", "round", "outro", "complete", "failed"]:
		ready_players[player] = true
		_update_ready()
		if ready_players.host and ready_players.guest:
			_advance_phase()
		_send_snapshot()
		return
	if action == "exit" and phase == "exit":
		_change_phase("outro")
		return
	if phase != "combat":
		return
	var fighter := _fighter(id)
	if fighter.state != "idle":
		return
	if action == "face":
		fighter.face_direction(clampi(direction, -1, 1))
	elif action == "attack":
		if attack < -1 or attack >= GameBalance.FIGHTERS[id].attacks.size():
			return
		if direction != 0:
			fighter.face_direction(clampi(direction, -1, 1))
		if fighter.try_attack(attack):
			game._play_sfx(game.attack_sfx, 1.0)
	elif action == "super" and float(charges[id]) >= 100.0:
		var targets: Array = []
		for enemy: EnemyBase in game.spawner.active_enemies:
			if enemy.state != "dead" and (id == "greg" or signf(enemy.position.x - fighter.position.x) == fighter.facing_direction):
				targets.append(enemy)
		if targets.is_empty():
			return
		charges[id] = 0.0
		if id == "greg":
			_super_targets = targets
			_super_impact_sent = false
			_change_phase("super_video")
			return
		fighter.try_attack(0)
		for enemy: EnemyBase in targets:
			enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
			on_hit(enemy, fighter)
		chains[id].add_bonus(500)
		game._impact(0.055, 13.0, Color(0.35, 0.95, 1.0, 0.45))


func on_hit(enemy: Node, fighter: PlayerFighter) -> void:
	if not is_host or phase not in ["combat", "super_attack"]:
		return
	var id := fighter.fighter_id
	var chain: SkillChain = chains[id]
	chain.hit()
	if is_instance_valid(enemy) and enemy.hp <= 0 and not _credited.has(enemy.get_instance_id()):
		_credited[enemy.get_instance_id()] = true
		chain.add_bonus(int(GameBalance.ENEMIES[enemy.enemy_id].score))
	if chain.hits >= 2:
		charges[id] = minf(100.0, float(charges[id]) + float(GameBalance.SUPER.charge_per_combo_hit) * chain.multiplier)
	game._play_sfx(game.hit_sfx, 1.0)
	game._impact(0.035, 5.0, Color(1.0, 0.88, 0.58, 0.22))


func on_damage(fighter: PlayerFighter) -> void:
	if not is_host:
		return
	chains[fighter.fighter_id].clear()
	game._play_sfx(game.hit_sfx, 0.9)


func on_death(fighter: PlayerFighter) -> void:
	if not is_host or phase not in ["combat", "super_attack"]:
		return
	game._play_sfx(game.fall_sfx, 0.86)
	var survivor := _fighter("mutki" if fighter.fighter_id == "greg" else "greg")
	if survivor.hp > 0:
		survivor.position.x = GameBalance.PLAYER_X
		return
	game.wave_manager.stop()
	game.spawner.stop_combat()
	_bank_round()
	_change_phase("failed")
	game.game_over = true


func story_finished() -> void:
	if phase not in ["intro", "outro"]:
		return
	_story_done = true
	lobby.show_wait("Ты готов. Ждём напарника…")
	request_action("ready")


func _change_phase(next_phase: String) -> void:
	phase = next_phase
	game.mission_phase = phase
	game.input_locked = phase != "combat"
	revision += 1
	ready_players = {"host": false, "guest": false}
	_story_done = false
	_render_phase()
	_send_snapshot()


func _advance_phase() -> void:
	match phase:
		"intro":
			_change_phase("combat")
			round_number = 1
			game.wave_manager.start_run(MissionData.WAVE_COUNT)
		"round":
			if round_number < MissionData.WAVE_COUNT:
				# A surviving teammate brings a fallen hero back for the next round.
				for id in ["greg", "mutki"]:
					var fighter := _fighter(id)
					if fighter.hp <= 0:
						fighter.activate_player()
						fighter.hp = ceili(float(GameBalance.FIGHTERS[id].max_hp) * 0.5)
					fighter.position.x = 290 if id == "greg" else 430
				_change_phase("combat")
				round_start = totals.duplicate()
				game.wave_manager.continue_after_round()
				round_number = game.wave_manager.current_wave_number()
			else:
				game.wave_manager.continue_after_round()
		"outro":
			_change_phase("complete")
		"complete", "failed":
			_begin_run()


func _bank_round() -> void:
	for id: String in chains:
		totals[id] += chains[id].bank()
		round_scores[id] = int(totals[id]) - int(round_start[id])


func _on_round_completed(number: int) -> void:
	if not enabled or not is_host or phase not in ["combat", "super_attack"]:
		return
	round_number = number
	_bank_round()
	_change_phase("round")


func waves_completed() -> void:
	if is_host:
		_change_phase("exit")


func _render_phase() -> void:
	if phase != "super_video" and _video_revision >= 0:
		game.assist_video.cancel()
		game.music.stream_paused = _video_music_was_paused
		get_tree().paused = _paused or phase == "super_attack"
		_video_revision = -1
	get_tree().paused = _paused or phase in ["super_video", "super_attack"]
	game.hud.hide_message()
	game.hud.hide_exit()
	if phase not in ["intro", "outro"]:
		game.hud.story_panel.hide()
	lobby.hide()
	match phase:
		"super_video":
			_show_super_video()
		"super_attack":
			game.hud.get_node("Root/BottomPanel").show()
		"intro":
			game.hud.show_story(MissionData.INTRO)
		"outro":
			game.hud.show_story(MissionData.OUTRO, false)
		"combat":
			game.hud.get_node("Root/BottomPanel").show()
		"round":
			lobby.show_results("РАУНД %d / %d ЗАВЕРШЁН" % [round_number, MissionData.WAVE_COUNT], round_scores, totals)
		"exit":
			game.hud.show_exit()
		"complete":
			lobby.show_results("МИССИЯ ПРОЙДЕНА ВМЕСТЕ!", round_scores, totals, true)
		"failed":
			lobby.show_results("МИССИЯ НЕ ПРОЙДЕНА", round_scores, totals)
			lobby.set_status("Оба героя повержены. Подтвердите готовность, чтобы попробовать ещё раз.")
	_update_ready()


func _update_ready() -> void:
	lobby.set_ready_state(bool(ready_players.host if is_host else ready_players.guest), bool(ready_players.guest if is_host else ready_players.host))


func _update_hud() -> void:
	var fighter := _fighter(local_hero)
	var chain: SkillChain = chains[local_hero]
	game.hud.set_hp(fighter.hp, int(GameBalance.FIGHTERS[local_hero].max_hp))
	game.hud.set_score(int(totals[local_hero]))
	game.hud.set_super(float(charges[local_hero]))
	game.hud.set_skill_chain(chain.points, chain.multiplier, chain.hits, chain.remaining / SkillChain.BANK_DELAY)
	game.hud.super_button.disabled = float(charges[local_hero]) < 100.0 or fighter.hp <= 0 or phase != "combat"
	_hud_scores.text = "ГРИША  %d    •    МУТКИ  %d\n%s" % [totals.greg, totals.mutki, ("Ты — Гриша" if local_hero == "greg" else "Ты — Мутки") + (" · Ты повержен. Напарник может закончить раунд." if fighter.hp <= 0 else " · HP напарника: %d" % _fighter("mutki" if local_hero == "greg" else "greg").hp)]


func _set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	if is_host:
		get_tree().paused = value or phase in ["super_video", "super_attack"]
	game.assist_video.set_suspended(value)
	game.arena_assist.set_suspended(value)
	if value:
		if not is_host:
			for fighter: PlayerFighter in [game.greg, game.mutki]:
				fighter.sprite.pause()
			for enemy: EnemyBase in _replicas.values():
				enemy.sprite.pause()
		lobby.show_connection_problem("Вернитесь в игру на обоих телефонах. Бой продолжится после восстановления связи.")
	else:
		if phase in ["intro", "outro"]:
			if _story_done:
				lobby.show_wait("Ты готов. Ждём напарника…")
			else:
				lobby.hide()
		elif _started:
			_render_phase()
		else:
			if _selection_open:
				show_character_selection()
			else:
				lobby.show_room(room_code)
			_refresh_room()


func _disconnect(message: String) -> void:
	_ended = true
	connected = false
	game.assist_video.cancel()
	game.arena_assist.cancel()
	game.mutki.sprite.show()
	if _video_revision >= 0:
		game.music.stream_paused = _video_music_was_paused
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


func _show_super_video() -> void:
	if _video_revision == revision:
		if _super_video_done:
			lobby.show_wait("Напарник досматривает ролик…")
		return
	_video_revision = revision
	_super_video_done = false
	_video_music_was_paused = game.music.stream_paused
	game.music.stream_paused = true
	if not game.assist_video.play_helper("mutki"):
		on_super_video_finished.call_deferred()
	get_tree().paused = true
	game.assist_video.set_suspended(_paused)


func on_super_video_finished() -> void:
	if _ended or phase != "super_video" or _super_video_done:
		return
	_super_video_done = true
	get_tree().paused = true
	lobby.show_wait("Напарник досматривает ролик…")
	_notify_video_done()


func _notify_video_done() -> void:
	_last_video_ack = Time.get_ticks_msec()
	request_action("video_done")


func _begin_super_animation() -> void:
	if not is_host or phase != "super_video":
		return
	_change_phase("super_attack")
	game._begin_mutki_assist()
	_send_snapshot()


func on_super_impact() -> void:
	if not is_host or phase != "super_attack" or _super_impact_sent:
		return
	_super_impact_sent = true
	for enemy: EnemyBase in _super_targets:
		if is_instance_valid(enemy) and enemy.hp > 0:
			enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
			on_hit(enemy, game.greg)
	chains.greg.add_bonus(500)
	game._impact(0.055, 13.0, Color(0.55, 0.25, 1.0, 0.45))


func on_super_animation_finished() -> void:
	if not is_host or phase != "super_attack":
		return
	_super_targets.clear()
	get_tree().paused = _paused
	_change_phase("combat")


func _visual(node: Node2D) -> Dictionary:
	var sprite: AnimatedSprite2D = node.sprite
	return {"x": node.position.x, "y": node.position.y, "sx": sprite.position.x, "sy": sprite.position.y, "scale": sprite.scale.x,
		"flip": sprite.flip_h, "animation": String(sprite.animation), "frame": sprite.frame, "progress": sprite.frame_progress,
		"playing": sprite.is_playing(), "hp": node.hp, "state": node.state}


func make_snapshot() -> Dictionary:
	_sequence += 1
	var data := {"type": "snapshot", "sequence": _sequence, "host": host_hero, "guest": guest_hero, "phase": phase, "revision": revision,
		"round": round_number, "totals": totals.duplicate(), "round_scores": round_scores.duplicate(), "ready": ready_players.duplicate(), "paused": _paused}
	if not _started:
		return data
	data.fighters = {}
	data.chains = {}
	data.charges = charges.duplicate()
	data.elapsed = game.mission_elapsed
	data.defeated = game.wave_manager._total_defeated
	data.enemies = []
	data.assist = game.arena_assist.snapshot()
	for id in ["greg", "mutki"]:
		data.fighters[id] = _visual(_fighter(id))
		data.fighters[id].direction = _fighter(id).facing_direction
		var chain: SkillChain = chains[id]
		data.chains[id] = {"points": chain.points, "hits": chain.hits, "remaining": chain.remaining}
	for enemy: EnemyBase in game.spawner.active_enemies:
		if not enemy.has_meta("network_id"):
			_next_enemy_id += 1
			enemy.set_meta("network_id", str(_next_enemy_id))
		var visual := _visual(enemy)
		visual.id = enemy.get_meta("network_id")
		visual.kind = enemy.enemy_id
		data.enemies.append(visual)
	return data


func _send_snapshot() -> void:
	if is_host and connected:
		_send(make_snapshot(), true)


func _apply_snapshot(data: Dictionary) -> void:
	var serial := int(data.get("sequence", -1))
	if serial <= _received_sequence:
		return
	_received_sequence = serial
	host_hero = str(data.get("host", ""))
	guest_hero = str(data.get("guest", ""))
	_refresh_room()
	if not data.has("fighters") or host_hero not in ["greg", "mutki"] or guest_hero not in ["greg", "mutki"] or host_hero == guest_hero:
		return
	if not _started:
		_started = true
		_activate_fighters()
	var old_revision := revision
	revision = int(data.revision)
	phase = str(data.phase)
	game.mission_phase = phase
	game.input_locked = phase != "combat"
	round_number = int(data.round)
	totals = data.totals.duplicate()
	round_scores = data.round_scores.duplicate()
	charges = data.charges.duplicate()
	ready_players = data.ready.duplicate()
	game.mission_elapsed = float(data.elapsed)
	game.hud.set_wave(round_number, 0)
	game.hud.set_mission_progress(int(data.defeated), 18)
	for id in ["greg", "mutki"]:
		_apply_visual(_fighter(id), data.fighters[id])
		_fighter(id).facing_direction = int(data.fighters[id].direction)
		chains[id].points = int(data.chains[id].points)
		chains[id].hits = int(data.chains[id].hits)
		chains[id].remaining = float(data.chains[id].remaining)
	game.arena_assist.apply_snapshot(data.get("assist", {}))
	game.mutki.sprite.visible = not game.arena_assist.playing
	var present: Dictionary = {}
	for visual: Dictionary in data.enemies:
		var id := str(visual.id)
		present[id] = true
		if not _replicas.has(id):
			var enemy := EnemySpawner.SCENES[str(visual.kind)].instantiate() as EnemyBase
			enemy.network_replica = true
			game.spawner.add_child(enemy)
			enemy.hurt_box.set_deferred("monitorable", false)
			_replicas[id] = enemy
		_apply_visual(_replicas[id], visual)
	for id in _replicas.keys():
		if not present.has(id):
			_replicas[id].queue_free()
			_replicas.erase(id)
	if old_revision != revision:
		_story_done = false
		_render_phase()
	_update_ready()
	_set_paused(bool(data.paused))
	# A new phase can arrive while a connection pause is still active.
	if _paused and lobby.screen != "paused":
		lobby.show_connection_problem("Вернитесь в игру на обоих телефонах.")


func _apply_visual(node: Node2D, data: Dictionary) -> void:
	var sprite: AnimatedSprite2D = node.sprite
	node.position = Vector2(float(data.x), float(data.y))
	node.hp = int(data.hp)
	node.state = str(data.state)
	sprite.position = Vector2(float(data.sx), float(data.sy))
	sprite.scale = Vector2.ONE * float(data.scale)
	sprite.flip_h = bool(data.flip)
	var animation := StringName(data.animation)
	if sprite.sprite_frames.has_animation(animation):
		sprite.animation = animation
		sprite.set_frame_and_progress(int(data.frame), float(data.progress))
		if bool(data.playing) and not bool(_paused):
			sprite.play()
		else:
			sprite.pause()
