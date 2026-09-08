extends Node2D

@onready var mutki: Mutki = $Mutki
@onready var greg: Greg = $Greg
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: GameHUD = $GameHUD
@onready var camera: Camera2D = $Camera2D
@onready var flash: ColorRect = $ImpactLayer/Flash
@onready var music: AudioStreamPlayer = $Music
@onready var attack_sfx: AudioStreamPlayer = $SFX/AttackSwing
@onready var hit_sfx: AudioStreamPlayer = $SFX/HitImpact
@onready var fall_sfx: AudioStreamPlayer = $SFX/BodyFall

var active_fighter: PlayerFighter = null
var selected_fighter_id := ""
var score := 0
var combo := 0
var skill_chain := SkillChain.new()
var _credited_defeats: Dictionary = {}
var super_charge := 0.0
var input_locked := true
var game_over := false
var debug_enabled := false
var _impact_busy := false
var mission_phase := "select"
var mission_elapsed := 0.0
var assist_video: AssistVideoPlayer
var intro_video: AssistVideoPlayer
var _intro_active := false
var arena_assist: MutkiArenaAssist
var _assist_video_target: Node
var _music_was_paused := false
var coop: CoopSession


func _ready() -> void:
	Engine.time_scale = 1.0
	intro_video = AssistVideoPlayer.new()
	add_child(intro_video)
	intro_video.finished.connect(_on_intro_video_finished)
	assist_video = AssistVideoPlayer.new()
	add_child(assist_video)
	assist_video.finished.connect(_on_assist_video_finished)
	arena_assist = MutkiArenaAssist.new()
	add_child(arena_assist)
	arena_assist.impact.connect(_on_mutki_assist_impact)
	arena_assist.finished.connect(_on_mutki_assist_finished)
	hit_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	_start_music()
	mutki.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	greg.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	for fighter: PlayerFighter in [mutki, greg]:
		fighter.attack_landed.connect(_on_fighter_attack_landed.bind(fighter))
		fighter.hp_changed.connect(_on_fighter_hp_changed.bind(fighter))
		fighter.damaged.connect(_on_fighter_damaged.bind(fighter))
		fighter.died.connect(_on_fighter_died.bind(fighter))
	greg.super_impact.connect(_on_greg_super_impact)
	greg.super_finished.connect(_on_greg_super_finished)
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	spawner.enemy_defeated.connect(_on_enemy_defeated)
	wave_manager.spawn_requested.connect(spawner.spawn_enemy)
	wave_manager.wave_changed.connect(_on_wave_changed)
	wave_manager.progress_changed.connect(hud.set_mission_progress)
	wave_manager.run_completed.connect(_on_mission_waves_completed)
	hud.super_pressed.connect(_try_super)
	hud.retry_pressed.connect(_restart)
	hud.character_selected.connect(_select_character)
	hud.story_finished.connect(_on_story_finished)
	hud.exit_pressed.connect(_inspect_exit)
	hud.set_score(score)
	hud.set_combo(combo)
	hud.set_super(super_charge)
	hud.hide_message()
	hud.show_character_select()
	coop = CoopSession.new()
	add_child(coop)
	coop.setup(self)
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--smoke-test"):
		_select_character("mutki" if user_args.has("--smoke-mutki") else "greg")
		intro_video._finish()
		_run_smoke_test.call_deferred()


func _start_music() -> void:
	var mp3_stream := music.stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = true
	if not music.playing:
		music.play()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_try_attack(-1, _screen_direction(event.position.x))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_attack(-1, _screen_direction(event.position.x))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT]:
			if coop.enabled:
				coop.request_action("face", -1, -1 if event.keycode in [KEY_A, KEY_LEFT] else 1)
			elif not input_locked and active_fighter != null:
				active_fighter.face_direction(-1 if event.keycode in [KEY_A, KEY_LEFT] else 1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_try_attack(-1, active_fighter.facing_direction if active_fighter != null else 0)
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_7:
			var requested_attack: int = event.keycode - KEY_1
			if active_fighter != null and requested_attack < GameBalance.FIGHTERS[selected_fighter_id].attacks.size():
				_try_attack(requested_attack, active_fighter.facing_direction)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			_try_super()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			_toggle_debug()
			get_viewport().set_input_as_handled()
		elif debug_enabled and not coop.enabled and event.keycode == KEY_F6 and active_fighter != null:
			active_fighter.take_damage(10)
			get_viewport().set_input_as_handled()
		elif debug_enabled and not coop.enabled and event.keycode == KEY_F7 and active_fighter != null:
			active_fighter.heal(10)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if coop != null and coop.enabled:
		return
	if mission_phase == "combat":
		mission_elapsed += _delta
		if not input_locked:
			var banked := skill_chain.advance(_delta)
			if banked > 0:
				_bank_skill_points(banked)
			elif skill_chain.points > 0:
				_update_skill_hud()
	if not debug_enabled or active_fighter == null:
		return
	var lines := [
		"F3 DEBUG | F6 -10 HP | F7 +10 HP | SPACE/1-7 attack | G special",
		active_fighter.debug_status(),
		"SUPER %.0f/100 | Wave %d | Score %d | Combo %d" % [super_charge, wave_manager.current_wave_number(), score, combo],
	]
	var enemy := spawner.current_enemy
	if is_instance_valid(enemy):
		lines.append(enemy.debug_status(active_fighter.position.x))
	else:
		lines.append("Enemy: waiting for next spawn")
	hud.set_debug_text("\n".join(lines))


func _select_character(fighter_id: String) -> void:
	if coop != null and coop.enabled:
		coop.choose_hero(fighter_id)
		return
	if active_fighter != null or not GameBalance.FIGHTERS.has(fighter_id):
		return
	selected_fighter_id = fighter_id
	if coop != null:
		coop.lobby.hide()
	active_fighter = greg if fighter_id == "greg" else mutki
	var inactive_fighter: PlayerFighter = mutki if fighter_id == "greg" else greg
	inactive_fighter.deactivate_player()
	var config: Dictionary = GameBalance.FIGHTERS[fighter_id]
	hud.configure_fighter(fighter_id, String(config.display_name), config.attacks.size())
	active_fighter.activate_player()
	mission_phase = "intro"
	input_locked = true
	play_intro()


func play_intro() -> void:
	if _intro_active:
		return
	_intro_active = true
	hud.story_panel.hide()
	music.stream_paused = true
	var stream := load(MissionData.INTRO_VIDEO) as VideoStream
	if not intro_video.play_stream(stream):
		push_warning("Intro video could not start; continuing to the mission.")
		_on_intro_video_finished.call_deferred()


func cancel_intro() -> void:
	if not _intro_active:
		return
	_intro_active = false
	intro_video.cancel()
	# A fresh mission resumes music even if the coop tree was paused before playback.
	music.stream_paused = false


func _on_intro_video_finished() -> void:
	if not _intro_active or mission_phase != "intro":
		return
	if coop != null and coop.enabled:
		coop.story_finished()
		return
	cancel_intro()
	_on_story_finished()


func _try_attack(attack_index: int = -1, direction: int = 0) -> void:
	if coop.enabled:
		coop.request_action("attack", attack_index, direction)
		return
	if input_locked or game_over or active_fighter == null or active_fighter.state != "idle":
		return
	if direction != 0:
		active_fighter.face_direction(direction)
	else:
		var enemy := spawner.get_target()
		if is_instance_valid(enemy):
			active_fighter.face_target(enemy)
	if active_fighter.try_attack(attack_index):
		_play_sfx(attack_sfx, randf_range(0.96, 1.06))


func _try_super() -> void:
	if coop.enabled:
		coop.request_action("super")
		return
	if input_locked or game_over or active_fighter == null or active_fighter.state != "idle" or super_charge < 100.0:
		return
	var enemy := spawner.get_target(active_fighter.facing_direction)
	if not is_instance_valid(enemy):
		enemy = spawner.get_target()
	if not is_instance_valid(enemy):
		return
	input_locked = true
	super_charge = 0.0
	hud.set_super(super_charge)
	var helper_id := "mutki" if selected_fighter_id == "greg" else "greg"
	_music_was_paused = music.stream_paused
	if assist_video.play_helper(helper_id):
		_assist_video_target = enemy
		music.stream_paused = true
		return
	if selected_fighter_id == "greg":
		_begin_mutki_assist()
	else:
		greg.perform_super(enemy)


func _on_assist_video_finished() -> void:
	if coop != null and coop.enabled:
		coop.on_super_video_finished()
		return
	music.stream_paused = _music_was_paused
	var target := _assist_video_target
	_assist_video_target = null
	if mission_phase == "combat" and not game_over:
		# The clip introduces the move; the actual hit belongs to its arena animation.
		if selected_fighter_id == "greg" and is_instance_valid(target):
			_begin_mutki_assist()
			return
		if selected_fighter_id != "greg":
			_on_greg_super_impact(target)
	_on_greg_super_finished()


func _begin_mutki_assist() -> void:
	var floor_position := Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	mutki.sprite.hide()
	input_locked = true
	get_tree().paused = true
	arena_assist.start(floor_position)


func _on_mutki_assist_impact() -> void:
	if coop.enabled:
		coop.on_super_impact()
		return
	if mission_phase != "combat" or game_over:
		return
	# The supplied animation sends a wave left AND right.
	for enemy: EnemyBase in spawner.active_enemies.duplicate():
		if is_instance_valid(enemy) and enemy.hp > 0:
			enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
			_credit_defeat(enemy)
	skill_chain.add_bonus(500)
	_update_skill_hud()
	_play_sfx(hit_sfx, 0.76)
	_impact(0.072, 18.0, Color(0.55, 0.25, 1.0, 0.45))


func _on_mutki_assist_finished() -> void:
	mutki.sprite.show()
	if coop.enabled:
		coop.on_super_animation_finished()
	else:
		get_tree().paused = false
		_on_greg_super_finished()


func _on_fighter_hp_changed(current: int, maximum: int, fighter: PlayerFighter) -> void:
	if coop == null or not coop.enabled or fighter == active_fighter:
		hud.set_hp(current, maximum)


func _on_fighter_attack_landed(enemy: Node, _damage: int, fighter: PlayerFighter = null) -> void:
	if coop != null and coop.enabled:
		coop.on_hit(enemy, fighter)
		return
	_play_sfx(hit_sfx, randf_range(0.94, 1.08))
	skill_chain.hit()
	_credit_defeat(enemy)
	combo = skill_chain.hits
	if combo >= 2:
		super_charge = minf(100.0, super_charge + float(GameBalance.SUPER.charge_per_combo_hit) * skill_chain.multiplier)
	_update_skill_hud()
	hud.set_super(super_charge)
	var hit_stop := float(GameBalance.FIGHTERS[selected_fighter_id].hit_stop)
	_impact(hit_stop, 9.0, Color(1.0, 0.88, 0.58, 0.42))


func _on_fighter_damaged(_amount: int, fighter: PlayerFighter = null) -> void:
	if coop != null and coop.enabled:
		coop.on_damage(fighter)
		return
	_play_sfx(hit_sfx, randf_range(0.82, 0.92))
	var lost_chain := skill_chain.points > 0
	skill_chain.clear()
	combo = 0
	if lost_chain:
		hud.show_chain_result(0, true)
	_impact(0.035, 6.0, Color(1.0, 0.18, 0.12, 0.30))


func _on_fighter_died(fighter: PlayerFighter = null) -> void:
	if coop != null and coop.enabled:
		coop.on_death(fighter)
		return
	_play_sfx(fall_sfx, 0.86)
	game_over = true
	mission_phase = "failed"
	input_locked = true
	wave_manager.stop()
	spawner.stop_combat()
	# Stop combat immediately, then let the complete fall remain visible.
	var fallen_fighter := active_fighter
	if fallen_fighter.sprite.animation == "death_video" and fallen_fighter.sprite.is_playing():
		await fallen_fighter.sprite.animation_finished
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(fallen_fighter) or active_fighter != fallen_fighter or mission_phase != "failed":
		return
	hud.show_game_over(score, mission_elapsed)


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy.has_method("set_debug_draw"):
		enemy.set_debug_draw(debug_enabled)


func _on_enemy_defeated(_enemy: Node, _enemy_id: String) -> void:
	if mission_phase != "combat" and not (coop.enabled and mission_phase == "super_attack"):
		return
	_play_sfx(fall_sfx, randf_range(0.94, 1.04))
	wave_manager.enemy_defeated()


func _on_greg_super_impact(enemy: Node) -> void:
	if coop.enabled:
		coop.on_super_impact()
		return
	if is_instance_valid(enemy) and enemy.has_method("receive_hit"):
		_play_sfx(hit_sfx, 0.76)
		enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
		skill_chain.add_bonus(500)
		_credit_defeat(enemy)
		_update_skill_hud()
		_impact(0.072, 18.0, Color(0.35, 0.95, 1.0, 0.55))


func _on_greg_super_finished() -> void:
	if coop.enabled:
		coop.on_super_animation_finished()
		return
	input_locked = mission_phase != "combat" or game_over


func _credit_defeat(enemy: Node) -> void:
	if not is_instance_valid(enemy) or not enemy is EnemyBase or enemy.hp > 0:
		return
	var instance_id := enemy.get_instance_id()
	if _credited_defeats.has(instance_id):
		return
	_credited_defeats[instance_id] = true
	skill_chain.add_bonus(int(GameBalance.ENEMIES[enemy.enemy_id].score))


func _update_skill_hud() -> void:
	hud.set_skill_chain(skill_chain.points, skill_chain.multiplier, skill_chain.hits, skill_chain.remaining / SkillChain.BANK_DELAY)


func _bank_skill_points(value: int) -> void:
	score += value
	combo = 0
	hud.set_score(score)
	hud.show_chain_result(value)


func _screen_direction(screen_x: float) -> int:
	var center_x := get_viewport().get_visible_rect().size.x * 0.5
	return -1 if screen_x < center_x else 1


func _on_story_finished() -> void:
	if coop.enabled:
		coop.story_finished()
		return
	if mission_phase == "intro":
		mission_phase = "combat"
		mission_elapsed = 0.0
		input_locked = false
		wave_manager.start_run(MissionData.WAVE_COUNT)
	elif mission_phase == "outro":
		mission_phase = "complete"
		var max_hp := int(GameBalance.FIGHTERS[selected_fighter_id].max_hp)
		var health_percent := roundi(float(active_fighter.hp) / float(max_hp) * 100.0)
		hud.show_mission_complete(score, health_percent, mission_elapsed)


func _on_wave_changed(wave_number: int, wave_size: int) -> void:
	hud.set_wave(wave_number, wave_size)
	hud.set_mission_objective(MissionData.objective(wave_number))


func _on_mission_waves_completed() -> void:
	if coop.enabled:
		coop.waves_completed()
		return
	if game_over or mission_phase != "combat":
		return
	var banked := skill_chain.bank()
	if banked > 0:
		_bank_skill_points(banked)
	mission_phase = "exit"
	input_locked = true
	spawner.stop_combat()
	hud.show_exit()


func _inspect_exit() -> void:
	if coop.enabled:
		coop.request_action("exit")
		return
	if mission_phase != "exit":
		return
	mission_phase = "outro"
	hud.hide_exit()
	hud.show_story(MissionData.OUTRO, false)


func _play_sfx(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _impact(hit_stop: float, shake_strength: float, color: Color) -> void:
	flash.color = color
	var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(flash, "color:a", 0.0, 0.16)
	if not _impact_busy:
		_impact_busy = true
		Engine.time_scale = 0.06
		await get_tree().create_timer(hit_stop, true, false, true).timeout
		Engine.time_scale = 1.0
		for index in 6:
			var strength := shake_strength * (1.0 - float(index) / 6.0)
			camera.offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
			await get_tree().process_frame
		camera.offset = Vector2.ZERO
		_impact_busy = false


func _toggle_debug() -> void:
	debug_enabled = not debug_enabled
	hud.set_debug_visible(debug_enabled)
	if active_fighter != null:
		active_fighter.set_debug_draw(debug_enabled)
	spawner.set_all_debug_draw(debug_enabled)


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/ui/LoadingScreen.tscn")


func _run_smoke_test() -> void:
	print("SMOKE: character selected: ", selected_fighter_id)
	var music_stream := music.stream as AudioStreamMP3
	if music_stream == null or not music_stream.loop or not music.playing:
		push_error("SMOKE_TEST_FAIL: soundtrack is not loaded, playing and looping")
		get_tree().quit(20)
		return
	print("SMOKE: soundtrack loaded, playing and looping")
	var weakest_attack_damage := 999999
	for attack: Dictionary in GameBalance.FIGHTERS[selected_fighter_id].attacks:
		weakest_attack_damage = mini(weakest_attack_damage, int(attack.damage))
	for enemy_id: String in GameBalance.ENEMIES:
		if int(GameBalance.ENEMIES[enemy_id].max_hp) > weakest_attack_damage * 2:
			push_error("SMOKE_TEST_FAIL: enemy needs more than two weakest attacks: " + enemy_id)
			get_tree().quit(16)
			return
	print("SMOKE: every enemy is balanced for one or two regular hits")
	if selected_fighter_id == "greg":
		var health_levels := [100, 90, 75, 50, 25, 10, 0, 30, 80, 100]
		for health_value: int in health_levels:
			hud.greg_health_bar.set_health(float(health_value), 100.0)
			await get_tree().create_timer(0.27).timeout
			var expected_width := 930.0 * float(health_value) / 100.0
			if absf(hud.greg_health_bar.current_fill_width() - expected_width) > 1.0:
				push_error(
					"SMOKE_TEST_FAIL: Greg health fill width mismatch at %d%% (%.2f vs %.2f)"
					% [health_value, hud.greg_health_bar.current_fill_width(), expected_width]
				)
				get_tree().quit(15)
				return
		print("SMOKE: Greg health bar 100->0 and 30->80 tween sequence completed")
	var deadline := Time.get_ticks_msec() + 12000
	while not is_instance_valid(spawner.current_enemy) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(spawner.current_enemy):
		push_error("SMOKE_TEST_FAIL: first enemy did not spawn")
		get_tree().quit(2)
		return
	while spawner.active_enemies.size() < WaveManager.GROUP_SIZE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if spawner.active_enemies.size() < WaveManager.GROUP_SIZE:
		push_error("SMOKE_TEST_FAIL: opening enemy group did not fill")
		get_tree().quit(17)
		return
	for enemy: EnemyBase in spawner.active_enemies:
		if enemy.enemy_id != GameBalance.STANDARD_ENEMY_ID:
			push_error("SMOKE_TEST_FAIL: opening group contains a different enemy type")
			get_tree().quit(19)
			return
	var opening_death_variants := {}
	for enemy: EnemyBase in spawner.active_enemies:
		opening_death_variants[enemy.death_variant] = true
	if not opening_death_variants.has(1) or not opening_death_variants.has(2):
		push_error("SMOKE_TEST_FAIL: enemy group does not alternate death variants")
		get_tree().quit(14)
		return
	var left_enemy: EnemyBase = null
	var right_enemy: EnemyBase = null
	for enemy: EnemyBase in spawner.active_enemies:
		if enemy.approach_side < 0 and left_enemy == null:
			left_enemy = enemy
		elif enemy.approach_side > 0 and right_enemy == null:
			right_enemy = enemy
	if not is_instance_valid(left_enemy) or not is_instance_valid(right_enemy):
		push_error("SMOKE_TEST_FAIL: enemies did not spawn from both sides")
		get_tree().quit(21)
		return
	if left_enemy.sprite.flip_h == right_enemy.sprite.flip_h:
		push_error("SMOKE_TEST_FAIL: left and right enemy animations are not mirrored")
		get_tree().quit(22)
		return
	if left_enemy.hit_box.position.x <= 0.0 or right_enemy.hit_box.position.x >= 0.0:
		push_error("SMOKE_TEST_FAIL: enemy attack hitboxes do not face the arena center")
		get_tree().quit(23)
		return
	print("SMOKE: opening group contains ", spawner.active_enemies.size(), " enemies from both sides")
	print("SMOKE: left/right enemy animations and attack hitboxes are mirrored")
	var first_enemy := spawner.current_enemy
	var second_enemy: EnemyBase = null
	for candidate: EnemyBase in spawner.active_enemies:
		if candidate.approach_side == first_enemy.approach_side and candidate.formation_slot == 1:
			second_enemy = candidate
			break
	var second_enemy_start_hp := second_enemy.hp if is_instance_valid(second_enemy) else -1
	print("SMOKE: enemy spawned and walking: ", first_enemy.enemy_id)
	if first_enemy.enemy_id == "enemy_01_thug":
		for animation_name in ["walk", "attack_01", "attack_02", "hit", "death_01", "death_02"]:
			if (
				not first_enemy.sprite.sprite_frames.has_animation(animation_name)
				or first_enemy.sprite.sprite_frames.get_frame_count(animation_name) < 2
			):
				push_error("SMOKE_TEST_FAIL: missing ordinary-enemy video animation: " + animation_name)
				get_tree().quit(13)
				return
	deadline = Time.get_ticks_msec() + 18000
	while is_instance_valid(first_enemy) and Time.get_ticks_msec() < deadline:
		var front_ready := absf(first_enemy.position.x - first_enemy.target_x) <= 5.0
		var cleave_ready := (
			selected_fighter_id != "greg"
			or not is_instance_valid(second_enemy)
			or absf(second_enemy.position.x - second_enemy.target_x) <= 5.0
		)
		if front_ready and cleave_ready and active_fighter.state == "idle":
			_try_attack()
		await get_tree().create_timer(0.04).timeout
	if is_instance_valid(first_enemy):
		push_error("SMOKE_TEST_FAIL: attack/hit/death cycle did not finish")
		get_tree().quit(3)
		return
	if selected_fighter_id == "greg" and is_instance_valid(second_enemy) and second_enemy.hp >= second_enemy_start_hp:
		push_error("SMOKE_TEST_FAIL: Greg's attack did not reach the next enemy")
		get_tree().quit(18)
		return
	if selected_fighter_id == "greg":
		print("SMOKE: Greg's attack reached the next enemy in formation")
	print("SMOKE: attacks, hit, knockback and death completed")
	deadline = Time.get_ticks_msec() + 5000
	while not is_instance_valid(spawner.current_enemy) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(spawner.current_enemy):
		push_error("SMOKE_TEST_FAIL: next enemy did not spawn")
		get_tree().quit(4)
		return
	print("SMOKE: enemy formation advanced after defeat")
	super_charge = 100.0
	hud.set_super(super_charge)
	hud.super_button.pressed.emit()
	deadline = Time.get_ticks_msec() + 10000
	while (greg.busy or input_locked) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if greg.busy or assist_video.playing or input_locked or super_charge != 0.0:
		push_error("SMOKE_TEST_FAIL: Greg special button did not finish")
		get_tree().quit(5)
		return
	print("SMOKE: Greg Power triggered from the Super Attack button")
	if selected_fighter_id == "greg":
		wave_manager.stop()
		spawner.set_all_physics_enabled(false)
		var hp_before_armored_attack := active_fighter.hp
		active_fighter.try_attack(0)
		var damage_during_attack := active_fighter.take_damage(1)
		if damage_during_attack or active_fighter.hp != hp_before_armored_attack or not active_fighter.state.begins_with("attack_"):
			push_error("SMOKE_TEST_FAIL: enemy damage interrupted Greg's attack")
			get_tree().quit(6)
			return
		deadline = Time.get_ticks_msec() + 3000
		while active_fighter.state.begins_with("attack_") and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var expected_attack_return_frame := int(GameBalance.FIGHTERS.greg.idle_after_attack_frame)
		if active_fighter.state != "idle" or absi(active_fighter.sprite.frame - expected_attack_return_frame) > 1:
			push_error("SMOKE_TEST_FAIL: Greg attack did not return through the aligned idle frame")
			get_tree().quit(7)
			return
		var pre_hit_animation := active_fighter.sprite.animation
		var pre_hit_scale := active_fighter.sprite.scale
		var pre_hit_position := active_fighter.sprite.position
		active_fighter.take_damage(1)
		if (
			active_fighter.sprite.animation != "hit_video"
			or active_fighter.sprite.animation == pre_hit_animation
			or not active_fighter.sprite.scale.is_equal_approx(pre_hit_scale)
			or not active_fighter.sprite.position.is_equal_approx(pre_hit_position)
		):
			push_error("SMOKE_TEST_FAIL: Greg hit animation did not start at the fixed size and position")
			get_tree().quit(8)
			return
		deadline = Time.get_ticks_msec() + 3000
		while active_fighter.state == "hit" and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if active_fighter.state != "idle" or active_fighter.sprite.animation != "idle_video":
			push_error("SMOKE_TEST_FAIL: Greg did not return from hit to idle")
			get_tree().quit(9)
			return
		active_fighter.take_damage(9999)
		if active_fighter.state != "dead" or active_fighter.sprite.animation != "death_video":
			push_error("SMOKE_TEST_FAIL: Greg death animation did not start")
			get_tree().quit(11)
			return
		deadline = Time.get_ticks_msec() + 3000
		var last_death_frame := active_fighter.sprite.sprite_frames.get_frame_count("death_video") - 1
		while active_fighter.sprite.frame < last_death_frame and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if active_fighter.sprite.frame != last_death_frame:
			push_error("SMOKE_TEST_FAIL: Greg death animation did not reach its final frame")
			get_tree().quit(12)
			return
		print("SMOKE: attack priority held, hit animation kept Greg's size and death held its final frame")
	print("SMOKE_TEST_PASS: soundtrack/select/two-sided-spawn/mirroring/attacks/hit/death/respawn/special/player-reactions")
	get_tree().quit(0)
