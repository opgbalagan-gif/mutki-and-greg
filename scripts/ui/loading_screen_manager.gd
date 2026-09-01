class_name LoadingScreenManager
extends Control

const LOADING_SCREEN_DIR := "res://assets/loading_screens"
const SUPPORTED_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]
const LOADING_SCREEN_PATHS: Array[String] = [
	"res://assets/loading_screens/loading_01_cyber.png",
	"res://assets/loading_screens/loading_02.png",
	"res://assets/loading_screens/loading_03.png",
	"res://assets/loading_screens/loading_04.png",
	"res://assets/loading_screens/loading_05.png",
	"res://assets/loading_screens/loading_06.png",
]
const MINIMUM_VISIBLE_TIME := 2.0

@export_file("*.tscn") var target_scene_path := "res://scenes/Main.tscn"

@onready var artwork: TextureRect = $Artwork
@onready var progress_bar: ProgressBar = $BottomPanel/ProgressBar
@onready var progress_label: Label = $BottomPanel/ProgressLabel
@onready var status_label: Label = $BottomPanel/StatusLabel

static var _last_texture_path := ""

var _elapsed := 0.0
var _loaded_scene: PackedScene
var _transition_started := false


func _ready() -> void:
	set_process(false)
	_show_random_artwork()
	progress_bar.value = 0.0
	progress_label.text = "0%"
	var request_error := ResourceLoader.load_threaded_request(target_scene_path, "PackedScene")
	if request_error != OK:
		_show_error("Не удалось начать загрузку")
		return
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _loaded_scene != null:
		if _elapsed >= MINIMUM_VISIBLE_TIME:
			_open_loaded_scene()
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(target_scene_path, progress)
	if not progress.is_empty():
		_set_progress(float(progress[0]))

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			_set_progress(1.0)
			_loaded_scene = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
			if _elapsed >= MINIMUM_VISIBLE_TIME:
				_open_loaded_scene()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_error("Ошибка загрузки уровня")


func _show_random_artwork() -> void:
	var candidates := _find_loading_screens()
	if candidates.is_empty():
		push_warning("No loading screens found in %s" % LOADING_SCREEN_DIR)
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var chosen_path := choose_loading_screen(candidates, _last_texture_path, rng)
	var chosen_texture := load(chosen_path) as Texture2D
	if chosen_texture == null:
		push_error("Loading screen could not be loaded: %s" % chosen_path)
		return
	artwork.texture = chosen_texture
	_last_texture_path = chosen_path


static func choose_loading_screen(
	available_paths: Array[String],
	previous_path: String,
	rng: RandomNumberGenerator
) -> String:
	if available_paths.is_empty():
		return ""
	var choices := available_paths.duplicate()
	if choices.size() > 1 and choices.has(previous_path):
		choices.erase(previous_path)
	return choices[rng.randi_range(0, choices.size() - 1)]


func _find_loading_screens() -> Array[String]:
	var paths := LOADING_SCREEN_PATHS.duplicate()
	for file_name: String in DirAccess.get_files_at(LOADING_SCREEN_DIR):
		var extension := file_name.get_extension().to_lower()
		var candidate_path := LOADING_SCREEN_DIR.path_join(file_name)
		if SUPPORTED_EXTENSIONS.has(extension) and not paths.has(candidate_path):
			paths.append(candidate_path)
	paths.sort()
	return paths


func _set_progress(normalized_value: float) -> void:
	var percent := clampf(normalized_value, 0.0, 1.0) * 100.0
	progress_bar.value = percent
	progress_label.text = "%d%%" % roundi(percent)


func _open_loaded_scene() -> void:
	if _transition_started:
		return
	_transition_started = true
	set_process(false)
	if _loaded_scene == null:
		_show_error("Уровень не найден")
		return
	get_tree().change_scene_to_packed(_loaded_scene)


func _show_error(message: String) -> void:
	set_process(false)
	status_label.text = message
	progress_label.text = "!"
	push_error("LoadingScreenManager: %s (%s)" % [message, target_scene_path])
