extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1672, 941)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	RenderingServer.set_default_clear_color(Color.GREEN)
	for hero in ["Mutki", "Greg"]:
		var fighter: PlayerFighter = load("res://scenes/characters/%s.tscn" % hero).instantiate()
		root.add_child(fighter)
		fighter.activate_player()
		fighter.position = Vector2(836, 862)
		fighter.scale = Vector2.ONE * 2.3525
		fighter.sprite.pause()
		fighter.sprite.set_frame_and_progress(0, 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://source_art/supers_20260925/gameplay/%s-idle-end-green.png" % hero.to_lower())
		print(hero, " actual idle: ", fighter.sprite.animation, " frame 0")
		fighter.queue_free()
		await process_frame
	quit()
