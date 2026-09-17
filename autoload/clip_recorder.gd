extends Node

const ClipTimelineModule = preload("res://util/clip_timeline.gd")

## Prototype/debug-only F9 gameplay capture. This is intentionally not a
## supported player-facing sharing/export feature: output remains MJPEG-in-MP4
## without synchronized game audio. Pressing F9 arms or cancels the recorder;
## an explicit Restart from Summit consumes a pending arm and records until the
## finish trigger (or an early save / 90 s safety cap). The clip is saved to
## the user's Downloads folder (user:// fallback). Frames are JPEG-encoded
## during capture and the MP4 is muxed on a background thread so play continues.
## Capture slots are retained even when the JPEG worker is back-pressured;
## missing slots are repeated during muxing to preserve the recorded run's
## presentation duration.

signal recording_changed(active: bool)
signal encoding_changed(active: bool)
signal clip_saved(path: String)
signal clip_failed(reason: String)
signal clip_info(message: String)
signal armed_changed(armed: bool)

const RELEASE_SCOPE := &"prototype_debug"
const CAPTURE_FPS := 30.0
const MAX_CLIP_FRAMES := 2700         # = 90 s at 30 fps
const CAPTURE_WIDTH := 960
const CAPTURE_HEIGHT := 540
const JPEG_QUALITY := 0.75
const MIN_CLIP_FRAMES := 18           # ~0.6 s
const MAX_PENDING_JPEG_FRAMES := 6

var armed := false
var _recording := false
var _encoding := false
var _frames: Array[PackedByteArray] = []
var _capture_accum := 0.0
var _encode_thread: Thread = null
var _jpeg_thread: Thread = null
var _jpeg_mutex := Mutex.new()
var _jpeg_semaphore := Semaphore.new()
var _jpeg_queue: Array[Dictionary] = []
var _encoded_frames_by_slot: Dictionary = {}
var _jpeg_worker_stop := false
var _jpeg_worker_available := false
var _capture_frame_count := 0
var _dropped_capture_frames := 0
var _shutting_down := false
var _encode_temporary_path := ""
# Acceptance tests use this seam to exercise the Thread.start() failure path.
var _encode_thread_start_override: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree() -> void:
	_shutdown_capture_workers()

func _unhandled_input(event: InputEvent) -> void:
	if _shutting_down:
		return
	if event.is_action_pressed("save_clip"):
		get_viewport().set_input_as_handled()
		if _recording:
			_stop_recording()
		elif armed:
			disarm()
		elif _encoding:
			clip_info.emit("DEBUG CAPTURE — STILL ENCODING THE PREVIOUS CLIP")
		else:
			arm()

func _process(delta: float) -> void:
	if _shutting_down or not _recording or get_tree().paused:
		return
	_capture_accum += maxf(delta, 0.0)
	var interval := 1.0 / CAPTURE_FPS
	var due_slots := mini(int(floor(_capture_accum / interval)), MAX_CLIP_FRAMES - _capture_frame_count)
	if due_slots <= 0:
		return
	_capture_accum = fmod(_capture_accum, interval)
	var capture_slot := _capture_frame_count + due_slots - 1
	_capture_frame_count += due_slots
	if _jpeg_worker_available and not _can_queue_jpeg_frame():
		_dropped_capture_frames += due_slots
		_finish_at_capture_limit()
		return
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null or not viewport_texture.get_rid().is_valid():
		_dropped_capture_frames += due_slots
		_finish_at_capture_limit()
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		_dropped_capture_frames += due_slots
		_finish_at_capture_limit()
		return
	if _jpeg_worker_available:
		if _queue_jpeg_frame(image, capture_slot):
			_dropped_capture_frames += due_slots - 1
		else:
			_dropped_capture_frames += due_slots
	else:
		var encoded := _encode_jpeg_frame(image)
		if not encoded.is_empty():
			_store_encoded_frame(encoded, capture_slot)
			_dropped_capture_frames += due_slots - 1
		else:
			_dropped_capture_frames += due_slots
	_finish_at_capture_limit()

func _finish_at_capture_limit() -> void:
	if _capture_frame_count >= MAX_CLIP_FRAMES:
		_stop_recording()

func is_recording() -> bool:
	return _recording

func arm() -> void:
	if _shutting_down or _recording or armed:
		return
	armed = true
	armed_changed.emit(true)
	clip_info.emit("DEBUG CAPTURE ARMED — MJPEG VIDEO / NO GAME AUDIO")

func disarm() -> void:
	if _shutting_down or not armed:
		return
	armed = false
	armed_changed.emit(false)
	clip_info.emit("DEBUG CAPTURE DISARMED")

func begin_run_capture() -> void:
	if _shutting_down:
		return
	if _encoding:
		# Previous clip is still muxing; stay armed so the next run records.
		clip_info.emit("DEBUG CAPTURE — STILL ENCODING; NEXT RUN REMAINS ARMED")
		return
	if armed:
		armed = false
		armed_changed.emit(false)
	_start_recording()

func handle_session_respawn(reason: StringName) -> void:
	if _shutting_down:
		return
	if reason == SessionManager.RESPAWN_SUMMIT_RESTART:
		# Resolve any active capture first: a summit restart closes the run
		# capture (saved if long enough, discarded if too short) before an
		# explicitly armed restart begins a fresh capture.
		if is_recording():
			end_run_capture()
		if armed:
			begin_run_capture()
		return
	if is_recording():
		end_run_capture()

func end_run_capture() -> void:
	if _shutting_down:
		return
	_stop_recording()

func _start_recording() -> void:
	if _shutting_down or _encoding:
		clip_info.emit("DEBUG CAPTURE — STILL ENCODING THE PREVIOUS CLIP")
		return
	if _recording:
		return
	_recording = true
	_frames.clear()
	_jpeg_mutex.lock()
	_encoded_frames_by_slot.clear()
	_jpeg_mutex.unlock()
	_capture_accum = 1.0 / CAPTURE_FPS
	_capture_frame_count = 0
	_dropped_capture_frames = 0
	_start_jpeg_worker()
	recording_changed.emit(true)
	clip_info.emit("DEBUG CAPTURE RECORDING — MJPEG VIDEO / NO GAME AUDIO")

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	recording_changed.emit(false)
	_stop_jpeg_worker()
	if _capture_frame_count < MIN_CLIP_FRAMES:
		clip_info.emit("DEBUG CLIP TOO SHORT — RIDE A MOMENT BEFORE SAVING")
		_frames.clear()
		_encoded_frames_by_slot.clear()
		return
	if _frames.is_empty() and _encoded_frames_by_slot.is_empty():
		clip_info.emit("DEBUG CLIP TOO SHORT — NO USABLE FRAME WAS ENCODED")
		_frames.clear()
		_encoded_frames_by_slot.clear()
		return
	var frames := _frames.duplicate()
	if _capture_frame_count > 0 and not _encoded_frames_by_slot.is_empty():
		# The worker may have encoded only a subset of the elapsed capture slots.
		# Expand those slots before the fixed-rate MP4 mux so dropped frames do
		# not silently compress the clip's presentation time.
		frames = ClipTimelineModule.expand(_encoded_frames_by_slot, _capture_frame_count)
	_frames.clear()
	_encoded_frames_by_slot.clear()
	_encoding = true
	encoding_changed.emit(true)
	clip_info.emit("DEBUG CAPTURE ENCODING — OUTPUT IS MJPEG-IN-MP4")
	var temporary_path := "user://.clip_encode_%d.mp4" % Time.get_ticks_usec()
	_encode_temporary_path = temporary_path
	var start_error := _start_encode_thread(frames, temporary_path)
	if start_error != OK:
		_encode_thread = null
		_encoding = false
		encoding_changed.emit(false)
		_remove_file(temporary_path)
		_encode_temporary_path = ""
		_fail("MP4 encoding could not start (%s)" % error_string(start_error))

func _start_encode_thread(frames: Array, temporary_path: String) -> int:
	_encode_thread = Thread.new()
	if _encode_thread_start_override.is_valid():
		return int(_encode_thread_start_override.call(_encode_thread, frames, CAPTURE_WIDTH, CAPTURE_HEIGHT, temporary_path))
	return _encode_thread.start(_encode_clip.bind(frames, CAPTURE_WIDTH, CAPTURE_HEIGHT, temporary_path))

func _start_jpeg_worker() -> void:
	if _shutting_down:
		return
	_stop_jpeg_worker()
	_jpeg_mutex.lock()
	_jpeg_queue.clear()
	_jpeg_worker_stop = false
	_jpeg_mutex.unlock()
	_jpeg_thread = Thread.new()
	var start_error := _jpeg_thread.start(_jpeg_worker)
	if start_error != OK:
		_jpeg_thread = null
		_jpeg_worker_available = false
		push_warning("Clip JPEG worker unavailable (%s); using synchronous capture" % error_string(start_error))
		return
	_jpeg_worker_available = true

func _stop_jpeg_worker(discard_pending := false) -> void:
	if _jpeg_thread == null:
		_jpeg_worker_available = false
		_jpeg_mutex.lock()
		_jpeg_queue.clear()
		_jpeg_worker_stop = false
		_jpeg_mutex.unlock()
		_jpeg_semaphore = Semaphore.new()
		return
	_jpeg_mutex.lock()
	_jpeg_worker_stop = true
	if discard_pending:
		_jpeg_queue.clear()
	_jpeg_mutex.unlock()
	_jpeg_semaphore.post()
	_jpeg_thread.wait_to_finish()
	_jpeg_thread = null
	_jpeg_worker_available = false
	_jpeg_mutex.lock()
	_jpeg_queue.clear()
	_jpeg_worker_stop = false
	_jpeg_mutex.unlock()
	_jpeg_semaphore = Semaphore.new()

func _can_queue_jpeg_frame() -> bool:
	_jpeg_mutex.lock()
	var can_queue := _jpeg_queue.size() < MAX_PENDING_JPEG_FRAMES
	_jpeg_mutex.unlock()
	return can_queue

func _queue_jpeg_frame(image: Image, capture_slot: int = -1) -> bool:
	_jpeg_mutex.lock()
	if _jpeg_worker_stop or _jpeg_queue.size() >= MAX_PENDING_JPEG_FRAMES:
		_jpeg_mutex.unlock()
		return false
	_jpeg_queue.append({"image": image, "slot": capture_slot})
	_jpeg_mutex.unlock()
	_jpeg_semaphore.post()
	return true

func _jpeg_worker() -> void:
	while true:
		_jpeg_semaphore.wait()
		while true:
			var item: Dictionary = {}
			var should_stop := false
			_jpeg_mutex.lock()
			if not _jpeg_queue.is_empty():
				item = _jpeg_queue.pop_front()
			elif _jpeg_worker_stop:
				should_stop = true
			_jpeg_mutex.unlock()
			if not item.is_empty():
				var image: Image = item.get("image") as Image
				var capture_slot := int(item.get("slot", -1))
				var encoded := _encode_jpeg_frame(image)
				if not encoded.is_empty():
					_store_encoded_frame(encoded, capture_slot)
				continue
			if should_stop:
				return
			break

func _shutdown_capture_workers() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	# Teardown is deliberately silent: no partial clip is published and no
	# signals are emitted while subscribers may already be leaving the tree.
	armed = false
	_recording = false
	_stop_jpeg_worker(true)
	if _encode_thread != null:
		_encode_thread.wait_to_finish()
		_encode_thread = null
	if not _encode_temporary_path.is_empty():
		_remove_file(_encode_temporary_path)
	_encode_temporary_path = ""
	_encoding = false
	_frames.clear()
	_jpeg_mutex.lock()
	_encoded_frames_by_slot.clear()
	_jpeg_queue.clear()
	_jpeg_worker_stop = false
	_jpeg_mutex.unlock()

func _store_encoded_frame(encoded: PackedByteArray, capture_slot: int = -1) -> void:
	_jpeg_mutex.lock()
	_frames.append(encoded)
	if capture_slot >= 0:
		_encoded_frames_by_slot[capture_slot] = encoded
	_jpeg_mutex.unlock()

func _encode_jpeg_frame(image: Image) -> PackedByteArray:
	image.resize(CAPTURE_WIDTH, CAPTURE_HEIGHT, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	return image.save_jpg_to_buffer(JPEG_QUALITY)

func _encode_clip(frames: Array, width: int, height: int, temporary_path: String) -> void:
	# Frames arrive pre-encoded as JPEG. Stream the MP4 to a temporary file so
	# the background worker does not retain both a complete mdat and final file.
	var error := Mp4Encoder.write_to_file(frames, int(CAPTURE_FPS), width, height, temporary_path)
	_on_encoded_file.call_deferred(temporary_path, error)

func _on_encoded_file(temporary_path: String, error: Error) -> void:
	if _shutting_down:
		_remove_file(temporary_path)
		if _encode_temporary_path == temporary_path:
			_encode_temporary_path = ""
		return
	if _encode_thread != null:
		_encode_thread.wait_to_finish()
		_encode_thread = null
	_encoding = false
	encoding_changed.emit(false)
	if error != OK:
		_remove_file(temporary_path)
		if _encode_temporary_path == temporary_path:
			_encode_temporary_path = ""
		_fail("MP4 encoding failed (%s)" % error_string(error))
		return
	var directory := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var destinations: Array[String] = []
	if not directory.is_empty():
		destinations.append(directory.path_join("ski_clip_%s.mp4" % stamp))
	var fallback := OS.get_user_data_dir().path_join("ski_clip_%s.mp4" % stamp)
	if destinations.is_empty() or destinations[0] != fallback:
		destinations.append(fallback)
	var last_error := ERR_CANT_CREATE
	for path: String in destinations:
		last_error = _copy_file(temporary_path, path)
		if last_error == OK:
			_remove_file(temporary_path)
			if _encode_temporary_path == temporary_path:
				_encode_temporary_path = ""
			clip_saved.emit(path)
			clip_info.emit("DEBUG CAPTURE SAVED — %s" % path.get_file())
			return
	_remove_file(temporary_path)
	if _encode_temporary_path == temporary_path:
		_encode_temporary_path = ""
	_fail("Could not write clip (%s)" % error_string(last_error))

func _copy_file(source: String, destination: String) -> Error:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return FileAccess.get_open_error()
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		var open_error := FileAccess.get_open_error()
		input.close()
		return open_error
	var copy_error := OK
	while input.get_position() < input.get_length():
		var chunk := input.get_buffer(1024 * 1024)
		if chunk.is_empty():
			copy_error = input.get_error()
			if copy_error == OK:
				copy_error = ERR_FILE_CORRUPT
			break
		output.store_buffer(chunk)
		if output.get_error() != OK:
			copy_error = output.get_error()
			break
	output.flush()
	if copy_error == OK:
		copy_error = output.get_error()
	output.close()
	input.close()
	return copy_error

func _remove_file(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)

func _fail(reason: String) -> void:
	push_warning("Debug clip capture failed: %s" % reason)
	clip_failed.emit(reason)
	clip_info.emit("DEBUG CAPTURE FAILED — %s" % reason)
