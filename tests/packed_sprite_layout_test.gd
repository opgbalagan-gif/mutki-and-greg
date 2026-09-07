extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var examples := [
		"characters/greg/idle_video/greg_idle_video_001.png",
		"characters/greg/attack_01/greg_attack_01_005.png",
		"enemies/enemy_01_thug/walk_video/enemy_01_walk_video_001.png",
		"characters/mutki/assist_super/mutki_assist_super_001.png",
		"characters/mutki/assist_super/mutki_assist_super_025.png",
	]
	for path in examples:
		var original: Texture2D = load("res://assets/" + path)
		var packed: AtlasTexture = load("res://assets/packed_sprites/" + path.replace(".png", ".tres"))
		var original_image := original.get_image()
		var packed_image := packed.get_image()
		var original_box := original_image.get_used_rect()
		var packed_box := packed_image.get_used_rect()
		packed_box.position += Vector2i(packed.margin.position)
		if original.get_size() != packed.get_size() or original_box != packed_box:
			failures += 1
			push_error("PACKED_LAYOUT_FAIL: canvas or opaque-pixel position changed: " + path)
		var expected := original_image.get_region(Rect2i(Vector2i(packed.margin.position), packed_image.get_size())).get_data()
		var actual := packed_image.get_data()
		for offset in range(0, actual.size(), 4):
			if expected[offset + 3] != actual[offset + 3]:
				failures += 1
				push_error("PACKED_LAYOUT_FAIL: alpha changed: " + path)
				break
			if actual[offset + 3] == 0:
				continue
			if expected[offset] != actual[offset] or expected[offset + 1] != actual[offset + 1] or expected[offset + 2] != actual[offset + 2]:
				failures += 1
				push_error("PACKED_LAYOUT_FAIL: visible detail changed: " + path)
				break
	print("PACKED_LAYOUT_PASS: logical-size/floor-pivot/visible-pixels/alpha-preserved" if failures == 0 else "PACKED_LAYOUT_FAIL: " + str(failures))
	quit(0 if failures == 0 else 1)
