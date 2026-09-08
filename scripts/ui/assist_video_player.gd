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
	visible = false
	set_process(false)


func play_helper(helper_id: String) -> bool:
	if playing or not VIDEO_PATHS.has(helper_id):
		return false
	var path: String = VIDEO_PATHS[helper_id]
	if not ResourceLoader.exists(path):
		return false
	var stream := load(path) as VideoStream
	return play_stream(stream)


func play_stream(stream: VideoStream) -> bool:
	if playing or stream == null:
		return false
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


func set_suspended(value: bool) -> void:
	if playing:
		_video.paused = value
		visible = not value


func _stop(notify_finished: bool) -> void:
	if not playing:
		return
	_video.stop()
	_video.paused = false
	_video.stream = null
	playing = false
	visible = false
	set_process(false)
	get_tree().paused = _was_paused
	if notify_finished:
		finished.emit()


func _exit_tree() -> void:
	if playing:
		get_tree().paused = _was_paused
