class_name AssistVideoPlayer
extends CanvasLayer

signal finished

const VIDEO_PATHS := {
	"greg": "res://assets/videos/assists/greg.ogv",
	"mutki": "res://assets/videos/assists/mutki.ogv",
}

var playing := false
var _was_paused := false
var _backdrop: ColorRect
var _video: VideoStreamPlayer
var _elapsed := 0.0
var transition_to_gameplay := false
var _transition: TextureRect
var _fade: Tween


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backdrop = ColorRect.new()
	_backdrop.color = Color.BLACK
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(_video)
	_video.finished.connect(_finish)
	_transition = TextureRect.new()
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_transition.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_transition)
	_transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition.hide()
	visible = false
	set_process(false)


func play_helper(fighter_id: String) -> bool:
	if playing or not VIDEO_PATHS.has(fighter_id):
		return false
	var path: String = VIDEO_PATHS[fighter_id]
	if not ResourceLoader.exists(path):
		return false
	var stream := load(path) as VideoStream
	return play_stream(stream)


func play_stream(stream: VideoStream) -> bool:
	if playing or stream == null:
		return false
	_clear_transition()
	_backdrop.show()
	_video.stream = stream
	_video.play()
	if not _video.is_playing():
		_video.stream = null
		return false
	playing = true
	_elapsed = 0.0
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	set_process(true)
	return true


func _process(delta: float) -> void:
	if _video.paused:
		return
	_elapsed += delta
	var texture := _video.get_video_texture()
	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		var dimensions := texture.get_size()
		var fit := minf(_backdrop.size.x / dimensions.x, _backdrop.size.y / dimensions.y)
		_video.size = dimensions * fit
		_video.position = (_backdrop.size - _video.size) * 0.5
	# A broken clip must not leave the battle paused indefinitely.
	if _elapsed > 60.0:
		_finish()


func _finish() -> void:
	_stop(true)


func cancel() -> void:
	_stop(false)
	_clear_transition()
	visible = false


func set_suspended(value: bool) -> void:
	if playing:
		_video.paused = value
		visible = not value
	if _fade != null and _fade.is_valid():
		if value:
			_fade.pause()
		else:
			_fade.play()
		visible = not value


func _stop(notify_finished: bool) -> void:
	if not playing:
		return
	var last_image: Image
	if notify_finished and transition_to_gameplay and _video.get_video_texture() != null:
		last_image = _video.get_video_texture().get_image()
	_video.stop()
	_video.paused = false
	_video.stream = null
	playing = false
	visible = false
	set_process(false)
	get_tree().paused = _was_paused
	if notify_finished:
		if last_image != null and not last_image.is_empty():
			_transition.texture = ImageTexture.create_from_image(last_image)
			_transition.modulate.a = 1.0
			_transition.show()
			_backdrop.hide()
			visible = true
			_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_fade.tween_property(_transition, "modulate:a", 0.0, 0.18)
			_fade.tween_callback(_clear_transition)
		finished.emit()


func _clear_transition() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	_transition.hide()
	_transition.texture = null
	if not playing:
		visible = false


func _exit_tree() -> void:
	if playing:
		get_tree().paused = _was_paused
