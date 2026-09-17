extends Node

const ClipRecorderModule = preload("res://autoload/clip_recorder.gd")

var failures: Array[String] = []
var clip_failure_count := 0

func _ready() -> void:
	await _test_release_scope()
	await _test_pending_arm_lifecycle()
	await _test_session_respawn_reasons_gate_capture()
	await _test_state_reason_matrix()
	await _test_active_recording_summit_restart_saves_partial()
	await _test_teardown_during_recording()
	await _test_teardown_during_encoding()
	await _test_encode_thread_start_failure()
	await _test_backpressure_slots_still_encode()
	if not failures.is_empty():
		for failure in failures:
			push_error("CLIP_RECORDER_LIFECYCLE_FAIL: " + failure)
		get_tree().quit(1)
		return
	print("CLIP_RECORDER_LIFECYCLE_PASS: debug release scope, arm state, summit-restart capture gating, respawn state matrix, partial-save restart, worker teardown, encode teardown, start failure cleanup, and backpressure slot-duration encoding verified")
	get_tree().quit(0)

func _new_recorder() -> Node:
	var recorder: Node = ClipRecorderModule.new()
	add_child(recorder)
	return recorder

func _destroy_recorder(recorder: Node) -> void:
	if is_instance_valid(recorder):
		if recorder.has_method("_shutdown_capture_workers"):
			recorder.call("_shutdown_capture_workers")
		recorder.queue_free()
	await get_tree().process_frame

func _test_release_scope() -> void:
	if ClipRecorderModule.RELEASE_SCOPE != &"prototype_debug":
		failures.append("clip recorder release scope is no longer explicitly prototype_debug")
	var recorder := _new_recorder()
	var notices: Array[String] = []
	recorder.connect("clip_info", func(message: String) -> void: notices.append(message))
	recorder.call("arm")
	if notices.is_empty() or not notices[-1].begins_with("DEBUG CAPTURE"):
		failures.append("arming the prototype recorder did not identify debug capture in the user-facing notice")
	await _destroy_recorder(recorder)

func _test_pending_arm_lifecycle() -> void:
	var recorder := _new_recorder()
	recorder.call("arm")
	recorder.call("end_run_capture")
	if not bool(recorder.get("armed")):
		failures.append("pending arm was cleared when an unstarted run ended")

	_press_save_clip(recorder)
	if bool(recorder.get("armed")):
		failures.append("F9 did not cancel a pending arm")

	recorder.call("arm")
	recorder.call("begin_run_capture")
	if bool(recorder.get("armed")):
		failures.append("pending arm was not consumed at summit capture start")
	if not bool(recorder.get("_recording")):
		failures.append("summit capture did not start after consuming a pending arm")
	await _destroy_recorder(recorder)

func _test_session_respawn_reasons_gate_capture() -> void:
	var emitted_reasons: Array[StringName] = []
	var on_respawn := func(_transform: Transform3D, reason: StringName) -> void:
		emitted_reasons.append(reason)
	SessionManager.respawn_requested.connect(on_respawn)
	var previous_marker := SessionManager.has_marker
	var previous_marker_transform := SessionManager.marker
	var previous_spawn := SessionManager.default_spawn
	SessionManager.clear_marker()
	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 98.0, 138.0))
	var marker := Transform3D(Basis.IDENTITY, Vector3(4.0, 12.0, -8.0))
	SessionManager.set_default_spawn(spawn)
	SessionManager.request_new_run_from_marker()
	SessionManager.request_respawn()
	SessionManager.request_respawn_to(spawn)
	SessionManager.set_marker(marker)
	SessionManager.request_new_run_from_marker()
	SessionManager.request_summit_restart()
	if (
		emitted_reasons.size() != 4
		or emitted_reasons[0] != SessionManager.RESPAWN_SESSION
		or emitted_reasons[1] != SessionManager.RESPAWN_COURSE_RECOVERY
		or emitted_reasons[2] != SessionManager.RESPAWN_NEW_RUN_MARKER
		or emitted_reasons[3] != SessionManager.RESPAWN_SUMMIT_RESTART
	):
		failures.append("Session respawn reasons were not explicit: %s" % str(emitted_reasons))
	SessionManager.respawn_requested.disconnect(on_respawn)
	if previous_marker:
		SessionManager.set_marker(previous_marker_transform)
	else:
		SessionManager.clear_marker()
	SessionManager.set_default_spawn(previous_spawn)

	var recorder := _new_recorder()
	recorder.call("arm")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_COURSE_RECOVERY)
	if bool(recorder.get("_recording")):
		failures.append("course recovery started an armed capture")
	if not bool(recorder.get("armed")):
		failures.append("course recovery disarmed a pending summit arm")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_NEW_RUN_MARKER)
	if bool(recorder.get("_recording")):
		failures.append("new marker run started an armed capture")
	if not bool(recorder.get("armed")):
		failures.append("new marker run disarmed a pending summit arm")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_SESSION)
	if bool(recorder.get("_recording")):
		failures.append("session respawn started an armed capture")
	if not bool(recorder.get("armed")):
		failures.append("session respawn disarmed a pending summit arm")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_SUMMIT_RESTART)
	if not bool(recorder.get("_recording")):
		failures.append("summit restart did not consume a pending arm into capture")
	if bool(recorder.get("armed")):
		failures.append("summit restart left the recorder armed")
	await _destroy_recorder(recorder)

	recorder = _new_recorder()
	recorder.call("_start_recording")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_COURSE_RECOVERY)
	if bool(recorder.get("_recording")):
		failures.append("course recovery to default spawn did not interrupt an in-progress clip")
	_assert_clean(recorder, "course recovery interruption")
	await _destroy_recorder(recorder)

	recorder = _new_recorder()
	recorder.call("_start_recording")
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_NEW_RUN_MARKER)
	if bool(recorder.get("_recording")):
		failures.append("new marker run did not interrupt an in-progress clip")
	_assert_clean(recorder, "new marker run interruption")
	await _destroy_recorder(recorder)

func _test_teardown_during_recording() -> void:
	var recorder := _new_recorder()
	recorder.call("_start_recording")
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#d47a3d"))
	for capture_slot in range(4):
		recorder.call("_queue_jpeg_frame", image, capture_slot)
	recorder.call("_shutdown_capture_workers")
	recorder.call("_shutdown_capture_workers")
	_assert_clean(recorder, "recording teardown")
	await _destroy_recorder(recorder)

func _test_teardown_during_encoding() -> void:
	var recorder := _new_recorder()
	var saved_count := 0
	recorder.connect("clip_saved", func(_path: String) -> void: saved_count += 1)
	var frames := _make_valid_frames(recorder)
	recorder.set("_recording", true)
	recorder.set("_frames", frames)
	recorder.set("_capture_frame_count", frames.size())
	recorder.call("_stop_recording")
	var temporary_path := str(recorder.get("_encode_temporary_path"))
	if not bool(recorder.get("_encoding")):
		failures.append("encoding teardown fixture did not enter encoding state")
	recorder.call("_shutdown_capture_workers")
	if saved_count != 0:
		failures.append("teardown published a clip that was already being encoded")
	if not temporary_path.is_empty() and FileAccess.file_exists(temporary_path):
		failures.append("encoding teardown left a temporary MP4 behind")
	_assert_clean(recorder, "encoding teardown")
	await _destroy_recorder(recorder)

func _test_encode_thread_start_failure() -> void:
	var recorder := _new_recorder()
	clip_failure_count = 0
	recorder.connect("clip_failed", _on_clip_failed)
	var before_files := _temporary_encode_files()
	recorder.set("_encode_thread_start_override", func(_thread, _frames, _width, _height, _path): return ERR_CANT_CREATE)
	var frames := _make_valid_frames(recorder)
	recorder.set("_recording", true)
	recorder.set("_frames", frames)
	recorder.set("_capture_frame_count", frames.size())
	recorder.call("_stop_recording")
	if bool(recorder.get("_encoding")):
		failures.append("encode start failure left encoding active")
	if recorder.get("_encode_thread") != null:
		failures.append("encode start failure left a thread object behind")
	if not str(recorder.get("_encode_temporary_path")).is_empty():
		failures.append("encode start failure left the temporary path tracked")
	if clip_failure_count != 1:
		failures.append("encode start failure did not emit clip_failed exactly once")
	var after_files := _temporary_encode_files()
	for file_name in after_files:
		if not before_files.has(file_name):
			failures.append("encode start failure left temporary file %s" % file_name)
	_assert_clean(recorder, "encode start failure")
	await _destroy_recorder(recorder)

func _test_state_reason_matrix() -> void:
	var reasons: Array[StringName] = [
		SessionManager.RESPAWN_SESSION,
		SessionManager.RESPAWN_NEW_RUN_MARKER,
		SessionManager.RESPAWN_COURSE_RECOVERY,
		SessionManager.RESPAWN_SUMMIT_RESTART,
	]
	for state in ["idle", "armed", "recording"]:
		for reason: StringName in reasons:
			var recorder := _new_recorder()
			if state == "armed":
				recorder.call("arm")
			elif state == "recording":
				recorder.call("_start_recording")
				recorder.set("_frames", _short_frames(recorder))
			recorder.call("handle_session_respawn", reason)
			var label := "%s × %s" % [state, reason]
			if state == "armed" and reason == SessionManager.RESPAWN_SUMMIT_RESTART:
				if not bool(recorder.get("_recording")):
					failures.append("%s did not consume the arm into capture" % label)
				if bool(recorder.get("armed")):
					failures.append("%s left the recorder armed" % label)
			elif state == "recording":
				if bool(recorder.get("_recording")):
					failures.append("%s left the capture active" % label)
				if bool(recorder.get("armed")):
					failures.append("%s left the recorder armed" % label)
				if bool(recorder.get("_encoding")):
					failures.append("%s muxed a too-short capture" % label)
				_assert_clean(recorder, label)
			else:
				if bool(recorder.get("_recording")):
					failures.append("%s started a capture" % label)
				if bool(recorder.get("_encoding")):
					failures.append("%s started encoding" % label)
				if state == "idle" and bool(recorder.get("armed")):
					failures.append("%s armed an idle recorder" % label)
				if state == "armed" and reason != SessionManager.RESPAWN_SUMMIT_RESTART and not bool(recorder.get("armed")):
					failures.append("%s disarmed a pending summit arm" % label)
			await _destroy_recorder(recorder)

func _test_active_recording_summit_restart_saves_partial() -> void:
	# A long-enough partial capture closes into the mux pipeline; the new run
	# starts unrecorded because the arm was already consumed by the first
	# restart. Teardown before completion keeps the test from publishing a file.
	var recorder := _new_recorder()
	var frames := _make_valid_frames(recorder)
	recorder.set("_recording", true)
	recorder.set("_frames", frames)
	recorder.set("_capture_frame_count", frames.size())
	recorder.set("_capture_accum", 1.0 / 30.0)
	recorder.call("handle_session_respawn", SessionManager.RESPAWN_SUMMIT_RESTART)
	if bool(recorder.get("_recording")):
		failures.append("summit restart during recording left the capture active")
	if bool(recorder.get("armed")):
		failures.append("summit restart during recording armed a new capture")
	if not bool(recorder.get("_encoding")):
		failures.append("summit restart during recording did not queue the partial clip for saving")
	recorder.call("_shutdown_capture_workers")
	_assert_clean(recorder, "partial clip restart")
	await _destroy_recorder(recorder)

func _test_backpressure_slots_still_encode() -> void:
	# A capture that ran longer than the minimum duration must encode even when
	# JPEG-worker back-pressure left only a sparse subset of slots encoded.
	var recorder := _new_recorder()
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#4b91c9"))
	var encoded: PackedByteArray = recorder.call("_encode_jpeg_frame", image)
	var frames: Array[PackedByteArray] = [encoded, encoded]
	recorder.set("_recording", true)
	recorder.set("_frames", frames)
	recorder.set("_encoded_frames_by_slot", {0: encoded, 15: encoded})
	recorder.set("_capture_frame_count", 30)
	recorder.call("_stop_recording")
	if not bool(recorder.get("_encoding")):
		failures.append("long capture with sparse encoded slots was rejected as too short")
	recorder.call("_shutdown_capture_workers")
	_assert_clean(recorder, "backpressure slot expansion")
	await _destroy_recorder(recorder)

func _short_frames(recorder: Node) -> Array[PackedByteArray]:
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#8a2f4f"))
	var encoded: PackedByteArray = recorder.call("_encode_jpeg_frame", image)
	var frames: Array[PackedByteArray] = []
	for _index in range(4):
		frames.append(encoded)
	return frames

func _press_save_clip(recorder: Node) -> void:
	var event := InputEventAction.new()
	event.action = &"save_clip"
	event.pressed = true
	recorder.call("_unhandled_input", event)

func _make_valid_frames(recorder: Node) -> Array[PackedByteArray]:
	var image := Image.create(64, 48, false, Image.FORMAT_RGB8)
	image.fill(Color("#4b91c9"))
	var encoded: PackedByteArray = recorder.call("_encode_jpeg_frame", image)
	var frames: Array[PackedByteArray] = []
	for _index in range(18):
		frames.append(encoded)
	return frames

func _temporary_encode_files() -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open("user://")
	if directory == null:
		return result
	for file_name in directory.get_files():
		if file_name.begins_with(".clip_encode_") and file_name.ends_with(".mp4"):
			result[file_name] = true
	return result

func _assert_clean(recorder: Node, label: String) -> void:
	if bool(recorder.get("armed")):
		failures.append("%s left the recorder armed" % label)
	if bool(recorder.get("_recording")):
		failures.append("%s left recording active" % label)
	if bool(recorder.get("_encoding")):
		failures.append("%s left encoding active" % label)
	if recorder.get("_jpeg_thread") != null:
		failures.append("%s left a JPEG worker behind" % label)
	if recorder.get("_encode_thread") != null:
		failures.append("%s left an MP4 worker behind" % label)
	if not str(recorder.get("_encode_temporary_path")).is_empty():
		failures.append("%s left a tracked temporary path" % label)
	var jpeg_queue: Array = recorder.get("_jpeg_queue")
	if not jpeg_queue.is_empty():
		failures.append("%s left queued JPEG work" % label)
	var frames: Array = recorder.get("_frames")
	if not frames.is_empty():
		failures.append("%s left captured frames" % label)
	var slot_frames: Dictionary = recorder.get("_encoded_frames_by_slot")
	if not slot_frames.is_empty():
		failures.append("%s left slot-indexed frames" % label)

func _on_clip_failed(_reason: String) -> void:
	clip_failure_count += 1
