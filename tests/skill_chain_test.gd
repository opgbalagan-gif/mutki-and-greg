extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SKILL_CHAIN_FAIL: " + message)

func _run() -> void:
	var chain := SkillChain.new()
	chain.hit()
	check(chain.advance(3.0) == 0, "chain stays live until the bank delay")
	chain.hit()
	check(chain.hits == 2 and is_equal_approx(chain.multiplier, 1.2), "second hit grows multiplier and extends chain")
	chain.add_bonus(120)
	check(chain.advance(3.3) == 384, "timeout banks base points times multiplier")
	check(chain.advance(10.0) == 0 and chain.bank() == 0, "points can only be banked once")
	for index in 80:
		chain.hit()
	check(chain.multiplier == 5.0, "multiplier caps at five")
	chain.clear()
	check(chain.points == 0 and chain.hits == 0 and chain.multiplier == 1.0, "broken chain loses pending points and multiplier")
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.character_selected.emit("greg")
	game.hud.story_panel._finish()
	game.wave_manager.stop()
	game.spawner.stop_combat()
	game._on_fighter_attack_landed(null, 1)
	check(game.super_charge == 0 and game.score == 0, "single hit is pending score and does not charge combo assistance")
	game._on_fighter_attack_landed(null, 1)
	check(is_equal_approx(game.super_charge, 15.0), "second consecutive hit charges assistance with multiplier")
	game._bank_skill_points(game.skill_chain.bank())
	check(game.score == 240 and game.combo == 0, "successful chain moves multiplied points to total score")
	game._on_fighter_attack_landed(null, 1)
	game._on_fighter_damaged(1)
	check(game.skill_chain.points == 0 and game.score == 240, "damage discards pending chain but preserves banked score")
	check(is_equal_approx(game.super_charge, 15.0), "damage preserves previously earned assistance")
	var defeated := EnemyBase.new()
	defeated.enemy_id = GameBalance.STANDARD_ENEMY_ID
	defeated.hp = 0
	game._credit_defeat(defeated)
	game._credit_defeat(defeated)
	check(game.skill_chain.points == int(GameBalance.ENEMIES[GameBalance.STANDARD_ENEMY_ID].score), "lethal-hit reward is credited only once")
	game._on_fighter_damaged(1)
	game._on_enemy_defeated(defeated, defeated.enemy_id)
	check(game.skill_chain.points == 0, "late death animation cannot restore a broken chain")
	defeated.free()
	for index in 12:
		game._on_fighter_attack_landed(null, 1)
	check(game.super_charge == 100.0 and not game.hud.super_button.disabled, "sustained combo fills and enables help")
	var before_total: int = game.score
	var expected: int = game.skill_chain.bank()
	game.skill_chain.add_bonus(expected)
	game._on_mission_waves_completed()
	check(game.score == before_total + expected and game.skill_chain.points == 0, "mission completion banks its final pending chain")
	var health_parent: Node = game.hud.hp_bar.get_parent()
	check(health_parent.name == "AttachedHealth" and health_parent.get_parent() == game.hud.super_button.get_parent(), "health is attached to the help component")
	check(game.hud.super_button is AssistButton, "help uses the portrait and radial charge button")
	while game._impact_busy:
		await process_frame
	# Let the cancelled opening-spawn timer release its suspended coroutine.
	await create_timer(0.4).timeout
	game.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	print("SKILL_CHAIN_PASS: multiplier/bank-once/break/charge-only-from-combo/end-of-mission/compact-health" if failures.is_empty() else "SKILL_CHAIN_FAIL")
	quit(0 if failures.is_empty() else 1)
