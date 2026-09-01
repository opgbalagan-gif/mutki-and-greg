class_name AnimationLibraryBuilder
extends RefCounted

static func png_paths(directory: String) -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for file_name in DirAccess.get_files_at(directory):
		var resource_name := ""
		if file_name.ends_with(".png"):
			resource_name = file_name
		elif file_name.ends_with(".png.import"):
			resource_name = file_name.trim_suffix(".import")
		elif file_name.ends_with(".png.remap"):
			resource_name = file_name.trim_suffix(".remap")
		if resource_name.is_empty():
			continue
		var resource_path := directory.path_join(resource_name)
		if not result.has(resource_path):
			result.append(resource_path)
	result.sort()
	return result

static func ping_pong_paths(paths: Array[String]) -> Array[String]:
	var result: Array[String] = paths.duplicate()
	for index in range(paths.size() - 2, 0, -1):
		result.append(paths[index])
	return result


static func round_trip_paths(paths: Array[String]) -> Array[String]:
	var result: Array[String] = paths.duplicate()
	for index in range(paths.size() - 2, -1, -1):
		result.append(paths[index])
	return result

static func add_animation(
	frames: SpriteFrames,
	animation_name: String,
	paths: Array[String],
	fps: float,
	looped: bool,
	durations: Array[float] = []
) -> void:
	if frames.has_animation(animation_name):
		frames.remove_animation(animation_name)
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, looped)
	for index in paths.size():
		var texture := load(paths[index]) as Texture2D
		if texture == null:
			push_error("Missing animation texture: " + paths[index])
			continue
		var duration := durations[index] if index < durations.size() else 1.0
		frames.add_frame(animation_name, texture, duration)

static func build_fighter(fighter_id: String) -> SpriteFrames:
	var root := "res://assets/characters/" + fighter_id
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var idle_fps := 4.0 if fighter_id == "mutki" else 6.0
	add_animation(frames, "idle", png_paths(root.path_join("idle")), idle_fps, true)
	for attack in GameBalance.FIGHTERS[fighter_id].attacks:
		var animation_name := String(attack.animation)
		add_animation(frames, animation_name, png_paths(root.path_join(animation_name)), 12.0, false)
	if fighter_id == "greg":
		var idle_video_paths := png_paths(root.path_join("idle_video"))
		add_animation(frames, "idle_video", ping_pong_paths(idle_video_paths), 12.0, true)
		add_animation(frames, "hit_video", png_paths(root.path_join("hit_video")), 15.0, false)
		add_animation(frames, "death_video", png_paths(root.path_join("death_video")), 12.0, false)
	var hit_paths := png_paths(root.path_join("hit"))
	add_animation(frames, "hit", hit_paths, 6.0, false, [1.5])
	if fighter_id == "greg":
		var super_paths := png_paths(root.path_join("super"))
		var punch_paths := png_paths(root.path_join("punch"))
		var super_sequence: Array[String] = []
		for index in mini(3, super_paths.size()):
			super_sequence.append(super_paths[index])
		if not punch_paths.is_empty():
			super_sequence.append(punch_paths[-1])
		for index in range(3, super_paths.size()):
			super_sequence.append(super_paths[index])
		add_animation(frames, "super", super_sequence, 14.0, false)
	return frames

static func build_enemy(enemy_id: String) -> SpriteFrames:
	var root := "res://assets/enemies/" + enemy_id
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var video_idle := png_paths(root.path_join("idle_video"))
	if not video_idle.is_empty():
		var video_walk := png_paths(root.path_join("walk_video"))
		var video_attack_01 := png_paths(root.path_join("attack_01_video"))
		var video_attack_02 := png_paths(root.path_join("attack_02_video"))
		var video_hit := png_paths(root.path_join("hit_video"))
		var video_death_01 := png_paths(root.path_join("death_01_video"))
		var video_death_02 := png_paths(root.path_join("death_02_video"))
		add_animation(frames, "idle", video_idle, 1.0, true)
		add_animation(frames, "walk", video_walk, 15.0, true)
		add_animation(frames, "attack_01", round_trip_paths(video_attack_01), 15.0, false)
		add_animation(frames, "attack_02", video_attack_02, 15.0, false)
		add_animation(frames, "hit", video_hit, 15.0, false)
		add_animation(frames, "death_01", video_death_01, 12.0, false)
		add_animation(frames, "death_02", video_death_02, 12.0, false)
		# Compatibility alias for tooling and any older scene logic.
		add_animation(frames, "death", video_death_01, 12.0, false)
		return frames
	var idle := png_paths(root.path_join("idle"))
	var walk := png_paths(root.path_join("walk"))
	var attack := png_paths(root.path_join("attack"))
	var hit := png_paths(root.path_join("hit"))
	var death := png_paths(root.path_join("death"))
	add_animation(frames, "idle", idle, 3.0, true)
	add_animation(frames, "walk", walk, 6.5, true)
	var attack_sequence: Array[String] = []
	if not idle.is_empty():
		attack_sequence.append(idle[0])
	if not attack.is_empty():
		attack_sequence.append(attack[0])
		attack_sequence.append(attack[0])
	if not idle.is_empty():
		attack_sequence.append(idle[0])
	add_animation(frames, "attack", attack_sequence, 8.0, false, [1.25, 0.65, 0.55, 1.35])
	add_animation(frames, "hit", hit, 7.0, false, [1.65])
	var death_sequence: Array[String] = []
	if not hit.is_empty():
		death_sequence.append(hit[0])
	if not death.is_empty():
		death_sequence.append(death[0])
		death_sequence.append(death[0])
	add_animation(frames, "death", death_sequence, 6.0, false, [0.8, 1.65, 1.65])
	return frames
