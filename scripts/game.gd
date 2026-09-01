extends Node2D

@onready var mutki: Mutki = $Mutki
@onready var greg: Greg = $Greg
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: GameHUD = $GameHUD
@onready var camera: Camera2D = $Camera2D
@onready var flash: ColorRect = $ImpactLayer/Flash
@onready var attack_sfx: AudioStreamPlayer = $SFX/AttackSwing
@onready var hit_sfx: AudioStreamPlayer = $SFX/HitImpact
@onready var fall_sfx: AudioStreamPlayer = $SFX/BodyFall

var active_fighter: PlayerFighter = null
var selected_fighter_id := ""
var score := 0
var combo := 0
var super_charge := 0.0
var input_locked := true
var game_over := false
var debug_enabled := false
var _impact_busy := false


func _ready() -> void:
	Engine.time_scale = 1.0
	mutki.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	greg.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	for fighter: PlayerFighter in [mutki, greg]:
		fighter.attack_landed.connect(_on_fighter_attack_landed)
		fighter.hp_changed.connect(hud.set_hp)
		fighter.damaged.connect(_on_fighter_damaged)
		fighter.died.connect(_on_fighter_died)
	greg.super_impact.connect(_on_greg_super_impact)
	greg.super_finished.connect(_on_greg_super_finished)
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	spawner.enemy_defeated.connect(_on_enemy_defeated)
	wave_manager.spawn_requested.connect(spawner.spawn_enemy)
	wave_manager.wave_changed.connect(hud.set_wave)
	hud.super_pressed.connect(_try_super)
	hud.retry_pressed.connect(_restart)
	hud.character_selected.connect(_select_character)
	hud.set_score(score)
	hud.set_combo(combo)
	hud.set_super(super_charge)
	hud.hide_message()
	hud.show_character_select()
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--smoke-test"):
		_select_character("mutki" if user_args.has("--smoke-mutki") else "greg")
		_run_smoke_test.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_try_attack()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_attack()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_attack()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_try_attack(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			_try_super()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			_toggle_debug()
			get_viewport().set_input_as_handled()
		elif debug_enabled and event.keycode == KEY_F6 and active_fighter != null:
			active_fighter.take_damage(10)
			get_viewport().set_input_as_handled()
		elif debug_enabled and event.keycode == KEY_F7 and active_fighter != null:
			active_fighter.heal(10)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not debug_enabled or active_fighter == null:
		return
	var lines := [
		"F3 DEBUG | F6 -10 HP | F7 +10 HP | SPACE/1-4 attack | G special",
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
	if active_fighter != null or not GameBalance.FIGHTERS.has(fighter_id):
		return
	selected_fighter_id = fighter_id
	active_fighter = greg if fighter_id == "greg" else mutki
	var inactive_fighter: PlayerFighter = mutki if fighter_id == "greg" else greg
	inactive_fighter.deactivate_player()
	var config: Dictionary = GameBalance.FIGHTERS[fighter_id]
	hud.configure_fighter(fighter_id, String(config.display_name), config.attacks.size())
	active_fighter.activate_player()
	input_locked = false
	wave_manager.start_run.call_deferred()


func _try_attack(attack_index: int = -1) -> void:
	if input_locked or game_over or active_fighter == null:
		return
	if active_fighter.try_attack(attack_index):
		_play_sfx(attack_sfx, randf_range(0.96, 1.06))


func _try_super() -> void:
	if input_locked or game_over or active_fighter == null or super_charge < 100.0:
		return
	var enemy := spawner.current_enemy
	if not is_instance_valid(enemy):
		return
	input_locked = true
	super_charge = 0.0
	hud.set_super(super_charge)
	if selected_fighter_id == "greg":
		if not greg.perform_power(enemy):
			input_locked = false
	else:
		greg.perform_super(enemy)


func _on_fighter_attack_landed(_enemy: Node, _damage: int) -> void:
	_play_sfx(hit_sfx, randf_range(0.94, 1.08))
	combo += 1
	score += 30 * maxi(1, combo)
	super_charge = minf(100.0, super_charge + float(GameBalance.SUPER.charge_per_hit))
	hud.set_combo(combo)
	hud.set_score(score)
	hud.set_super(super_charge)
	var hit_stop := float(GameBalance.FIGHTERS[selected_fighter_id].hit_stop)
	_impact(hit_stop, 9.0, Color(1.0, 0.88, 0.58, 0.42))


func _on_fighter_damaged(_amount: int) -> void:
	_play_sfx(hit_sfx, randf_range(0.82, 0.92))
	combo = 0
	hud.set_combo(combo)
	_impact(0.035, 6.0, Color(1.0, 0.18, 0.12, 0.30))


func _on_fighter_died() -> void:
	_play_sfx(fall_sfx, 0.86)
	game_over = true
	input_locked = true
	wave_manager.stop()
	spawner.set_all_physics_enabled(false)
	hud.show_game_over(score)


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy.has_signal("attack_landed"):
		enemy.attack_landed.connect(func(_damage: int): combo = 0; hud.set_combo(combo))
	if enemy.has_method("set_debug_draw"):
		enemy.set_debug_draw(debug_enabled)


func _on_enemy_defeated(_enemy: Node, enemy_id: String) -> void:
	_play_sfx(fall_sfx, randf_range(0.94, 1.04))
	var config: Dictionary = GameBalance.ENEMIES[enemy_id]
	score += int(config.score)
	super_charge = minf(100.0, super_charge + float(GameBalance.SUPER.charge_per_kill))
	hud.set_score(score)
	hud.set_super(super_charge)
	wave_manager.enemy_defeated()


func _on_greg_super_impact(enemy: Node) -> void:
	if is_instance_valid(enemy) and enemy.has_method("receive_hit"):
		_play_sfx(hit_sfx, 0.76)
		enemy.receive_hit(int(GameBalance.SUPER.damage), float(GameBalance.SUPER.knockback))
		score += 500
		hud.set_score(score)
		_impact(0.072, 18.0, Color(0.35, 0.95, 1.0, 0.55))


func _on_greg_super_finished() -> void:
	input_locked = false


func _play_sfx(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _impact(hit_stop: float, shake_strength: float, color: Color) -> void:
	flash.color = color
	var fade := create_tween()
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
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _run_smoke_test() -> void:
	print("SMOKE: character selected: ", selected_fighter_id)
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
	print("SMOKE: opening group contains ", spawner.active_enemies.size(), " enemies")
	var first_enemy := spawner.current_enemy
	var second_enemy := spawner.active_enemies[1]
	var second_enemy_start_hp := second_enemy.hp
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
		if first_enemy.position.x <= 432.0 and active_fighter.state == "idle":
			active_fighter.try_attack()
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
	deadline = Time.get_ticks_msec() + 5000
	while (greg.busy or input_locked) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if greg.busy or super_charge != 0.0:
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
	print("SMOKE_TEST_PASS: select/spawn/attacks/hit/death/respawn/special/player-reactions")
	get_tree().quit(0)
