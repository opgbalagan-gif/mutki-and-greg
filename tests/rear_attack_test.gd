extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("REAR_ATTACK_FAIL: " + message)

func _run() -> void:
	for hero in ["greg", "mutki"]:
		for direction in [-1, 1]:
			var arena := Node2D.new()
			root.add_child(arena)
			var fighter: PlayerFighter = load("res://scenes/characters/" + ("Greg" if hero == "greg" else "Mutki") + ".tscn").instantiate()
			arena.add_child(fighter)
			fighter.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
			fighter.activate_player()
			fighter.face_direction(direction)
			var spawner := EnemySpawner.new()
			arena.add_child(spawner)
			spawner._next_spawn_side = direction
			for index in 4:
				spawner.spawn_enemy(GameBalance.STANDARD_ENEMY_ID)
			var hits := {-1: 0, 1: 0}
			for enemy in spawner.active_enemies:
				check(enemy._can_attack == (enemy.formation_slot == 0), "only the front enemy on EACH side attacks")
				enemy.attack_landed.connect((func(_damage: int, side: int): hits[side] += 1).bind(enemy.approach_side))
				# Exercise actual movement, animation and collision at the approach's end.
				enemy.position.x = enemy.target_x + 20.0 * enemy.approach_side
			var initial_hp := fighter.hp
			var deadline := Time.get_ticks_msec() + 8000
			while (hits[-1] == 0 or hits[1] == 0) and Time.get_ticks_msec() < deadline:
				await process_frame
			check(hits[-1] > 0 and hits[1] > 0, "%s facing %d receives attacks from both sides" % [hero, direction])
			check(fighter.hp < initial_hp, "real enemy collisions reduce health")
			check(fighter.facing_direction == direction, "rear damage does not require turning the hero")
			spawner.stop_combat()
			# Wait out the previous hit, then time a punch just before the rear hit frame.
			deadline = Time.get_ticks_msec() + 3000
			while fighter.state != "idle" and Time.get_ticks_msec() < deadline:
				await process_frame
			var rear := spawner.get_target(-direction)
			rear.state = "walk"
			rear.position.x = rear.target_x
			rear.set_formation_slot(0, rear.target_x, true)
			rear.set_physics_process(true)
			deadline = Time.get_ticks_msec() + 5000
			while not (rear.state == "attack" and rear.sprite.frame == 4) and Time.get_ticks_msec() < deadline:
				await process_frame
			check(rear.state == "attack" and rear.sprite.frame == 4, "rear enemy winds up its next real attack")
			var before_punch_hp := fighter.hp
			check(fighter.try_attack(0), "hero starts a forward punch")
			deadline = Time.get_ticks_msec() + 1200
			while fighter.hp == before_punch_hp and Time.get_ticks_msec() < deadline:
				await process_frame
			check(fighter.hp == before_punch_hp - int(rear.config.damage), "rear hit damages a punching hero exactly once")
			check(fighter.state == "hit", "rear impact interrupts the forward punch")
			if hero == "greg":
				rear.stop_combat()
				deadline = Time.get_ticks_msec() + 3000
				while fighter.state != "idle" and Time.get_ticks_msec() < deadline:
					await process_frame
				fighter.try_attack(0)
				var front := spawner.get_target(direction)
				var protected_hp := fighter.hp
				check(not fighter.take_damage(1, front) and fighter.hp == protected_hp, "Greg retains frontal protection during his punch")
			spawner.stop_combat()
			arena.queue_free()
			await process_frame
	print("REAR_ATTACK_PASS: both-heroes/both-facing-directions/two-fronts/real-collision/rear-damage-during-punch/front-protection" if failures.is_empty() else "REAR_ATTACK_FAIL: " + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
