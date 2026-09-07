extends SceneTree

var failures: Array[String] = []
var deaths := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MUTKI_REACTIONS_FAIL: " + message)

func _run() -> void:
	var fighter: PlayerFighter = load("res://scenes/characters/Mutki.tscn").instantiate()
	root.add_child(fighter)
	fighter.position = Vector2(GameBalance.PLAYER_X, GameBalance.GROUND_Y)
	fighter.activate_player()
	fighter.died.connect(func(): deaths += 1)
	var library := fighter.sprite.sprite_frames
	var neutral := library.get_frame_texture("idle", 0).get_image()
	check(library.get_frame_count("idle") == 18, "idle loops through the first ten source frames and back")
	check(library.get_frame_count("hit") == 9, "damage has a complete reaction and recovery")
	check(library.get_frame_count("death_video") == 21, "death contains the full fall")
	for attack in GameBalance.FIGHTERS.mutki.attacks:
		var name: String = attack.animation
		for index in [0, library.get_frame_count(name) - 1]:
			check(library.get_frame_texture(name, index).get_image().get_data() == neutral.get_data(), "attack bookend matches the new idle: " + name)
	for direction in [-1, 1]:
		fighter.face_direction(direction)
		var scale_before := fighter.sprite.scale
		var position_before := fighter.sprite.position
		# An incoming hit must cancel an actual open attack window.
		check(fighter.try_attack(0), "can start attack before damage")
		fighter.sprite.frame = 3
		check(fighter._active_window, "attack window was active")
		check(fighter.take_damage(1), "ordinary damage accepted")
		check(fighter.state == "hit" and fighter.sprite.animation == "hit", "new hit animation plays")
		check(not fighter._active_window and not fighter.try_attack(), "reaction cancels damage and blocks attacking")
		check(fighter.sprite.scale == scale_before and fighter.sprite.position == position_before, "reaction preserves floor and size")
		fighter.face_direction(-direction)
		check(fighter.facing_direction == direction, "reaction stays on the committed side")
		var deadline := Time.get_ticks_msec() + 2000
		while fighter.state == "hit" and Time.get_ticks_msec() < deadline:
			await process_frame
		check(fighter.state == "idle", "reaction returns to idle")
		check(fighter.sprite.animation == "idle" and fighter.sprite.modulate == Color.WHITE, "returns to the new live stance")
		check(fighter.take_damage(999), "lethal hit accepted")
		check(fighter.state == "dead" and fighter.sprite.animation == "death_video", "lethal hit starts fall")
		check(not fighter.take_damage(1) and not fighter.try_attack(), "death rejects more damage and attacks")
		# All opaque pixels must stay inside the source canvas AND the portrait arena.
		for index in library.get_frame_count("death_video"):
			var texture := library.get_frame_texture("death_video", index)
			var box := texture.get_image().get_used_rect()
			if texture is AtlasTexture:
				box.position += Vector2i(texture.margin.position)
			check(box.position.x > 10 and box.position.y > 10 and box.end.x < 758 and box.end.y < 502, "fall has transparent margin: %d" % index)
			for corner in [Vector2(box.position), Vector2(box.end)]:
				var offset: Vector2 = corner - Vector2(texture.get_size()) / 2.0
				offset.x *= direction
				var point := fighter.position + fighter.sprite.position + offset * fighter.sprite.scale
				check(point.x > 0 and point.x < 720 and point.y > 0 and point.y < 1280, "fall fits portrait viewport in either direction")
		deadline = Time.get_ticks_msec() + 3000
		while fighter.sprite.is_playing() and Time.get_ticks_msec() < deadline:
			await process_frame
		check(fighter.sprite.frame == 20 and fighter.state == "dead", "holds the final complete lying pose")
		fighter.activate_player()
		check(fighter.state == "idle" and fighter.hp == 110 and fighter.sprite.modulate == Color.WHITE, "replay restores stance and health")
	check(deaths == 2, "one death signal for each lethal hit")
	fighter.queue_free()
	await process_frame
	if failures.is_empty():
		print("MUTKI_REACTIONS_PASS: source-idle/attack-bookends/hit-interruption/recovery/full-fall/both-sides/no-crop/replay")
	quit(0 if failures.is_empty() else 1)
