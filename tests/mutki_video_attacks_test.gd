extends SceneTree

class TargetDummy extends Node2D:
	var hits := 0
	var damage := 0
	func receive_hit(amount: int, _knockback: float) -> void:
		hits += 1
		damage += amount

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MUTKI_V2_FAIL: " + message)

func target_at(x: float) -> TargetDummy:
	var target := TargetDummy.new()
	target.position.x = x
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.position.y = -124
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(118, 238)
	collider.shape = shape
	area.add_child(collider)
	target.add_child(area)
	root.add_child(target)
	return target

func _run() -> void:
	var fighter: PlayerFighter = load("res://scenes/characters/Mutki.tscn").instantiate()
	root.add_child(fighter)
	fighter.activate_player()
	var left := target_at(-190)
	var right := target_at(190)
	await physics_frame
	await physics_frame
	var idle_scale := fighter.sprite.scale
	var idle_position := fighter.sprite.position
	var attacks: Array = GameBalance.FIGHTERS.mutki.attacks
	check(attacks.size() == 7, "seven supplied attacks are playable")
	for direction in [-1, 1]:
		for index in attacks.size():
			left.hits = 0
			right.hits = 0
			left.damage = 0
			right.damage = 0
			fighter.face_direction(direction)
			check(fighter.try_attack(index), "attack starts from idle")
			fighter.face_direction(-direction)
			check(fighter.facing_direction == direction, "attack direction remains committed")
			var active_frames := {}
			var deadline := Time.get_ticks_msec() + 5000
			while fighter.state != "idle" and Time.get_ticks_msec() < deadline:
				if fighter._active_window:
					active_frames[fighter.sprite.frame] = true
				await process_frame
			var expected: TargetDummy = left if direction < 0 else right
			var opposite: TargetDummy = right if direction < 0 else left
			check(fighter.state == "idle", "attack returns to idle: %d" % index)
			check(expected.hits == 1 and expected.damage == int(attacks[index].damage), "one hit on the selected side: %d / %d" % [index, direction])
			check(opposite.hits == 0, "opposite side stays unharmed")
			check(active_frames.has(int(attacks[index].active_frame)), "impact frame opens hitbox")
			check(active_frames.has(int(attacks[index].active_end_frame)), "hitbox persists through follow-through")
			check(active_frames.size() == 2, "hitbox closes after two active frames")
			check(fighter.sprite.scale.is_equal_approx(idle_scale), "return preserves body scale")
			check(fighter.sprite.position.is_equal_approx(idle_position), "return preserves floor and pivot")
			check(not fighter._active_window, "idle has no active hitbox")
	fighter.take_damage(1)
	check(fighter.sprite.scale.is_equal_approx(idle_scale) and fighter.sprite.position.is_equal_approx(idle_position), "hit stun keeps the new design aligned")
	var hit_deadline := Time.get_ticks_msec() + 2000
	while fighter.state == "hit" and Time.get_ticks_msec() < hit_deadline:
		await process_frame
	check(fighter.state == "idle", "hit stun returns to the video idle")
	fighter.queue_free()
	left.queue_free()
	right.queue_free()
	await process_frame
	if failures.is_empty():
		print("MUTKI_V2_PASS: seven-attacks/both-sides/single-hit/impact-windows/turn-lock/idle-alignment/hit-stun")
	quit(0 if failures.is_empty() else 1)
