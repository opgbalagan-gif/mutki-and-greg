extends SceneTree


func _initialize() -> void:
	var actual_paths := LoadingScreenManager.LOADING_SCREEN_PATHS
	if actual_paths.size() < 6:
		push_error("LOADING_SCREEN_TEST_FAIL: expected at least 6 loading screens")
		quit(4)
		return
	for path: String in actual_paths:
		if load(path) as Texture2D == null:
			push_error("LOADING_SCREEN_TEST_FAIL: could not load texture: " + path)
			quit(5)
			return
	print("LOADING_SCREEN_TEST: %d real textures loaded" % actual_paths.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	var candidates: Array[String] = ["screen_a", "screen_b", "screen_c"]
	for previous_path: String in candidates:
		for iteration in 100:
			var chosen := LoadingScreenManager.choose_loading_screen(candidates, previous_path, rng)
			if chosen == previous_path or not candidates.has(chosen):
				push_error("LOADING_SCREEN_TEST_FAIL: repeated or unknown path")
				quit(1)
				return
	if LoadingScreenManager.choose_loading_screen([], "", rng) != "":
		push_error("LOADING_SCREEN_TEST_FAIL: empty list did not return an empty path")
		quit(2)
		return
	var only_one: Array[String] = ["only_screen"]
	if LoadingScreenManager.choose_loading_screen(only_one, "only_screen", rng) != "only_screen":
		push_error("LOADING_SCREEN_TEST_FAIL: single-item fallback failed")
		quit(3)
		return
	print("LOADING_SCREEN_TEST_PASS: 300 randomized non-repeat selections")
	quit(0)
