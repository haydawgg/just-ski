extends Node

## Builds the deterministic resort once and writes a static editor-inspection
## scene. The preview deliberately strips runtime scripts so opening it in the
## editor cannot reconstruct or duplicate the playable world.

const RESORT_SCENE := preload("res://world/resort.tscn")
const DEFAULT_OUTPUT := "res://world/generated/resort_preview.tscn"

var _active_source: Node3D
var _active_preview: Node3D

func _init() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var source := RESORT_SCENE.instantiate() as Node3D
	if source == null:
		_fail("Could not instantiate the resort source scene")
		return
	_active_source = source
	# Build without entering the tree first so Resort._ready() does not add the
	# player, camera, UI, or recorder. The static environment/course methods are
	# then allowed to enter the tree so rail and feature _ready() hooks finish
	# their authored visual/collision construction before duplication.
	source.call("_build_environment")
	source.call("_build_resort")
	source.set_script(null)
	get_tree().root.add_child(source)
	await get_tree().process_frame
	_mark_static_geometry(source)

	var preview := Node3D.new()
	_active_preview = preview
	preview.name = "ResortPreview"
	preview.set_meta("generated_from", "res://world/resort.tscn")
	preview.set_meta("generated_by", "res://tools/world/bake_resort_preview.gd")
	for child: Node in source.get_children():
		var copy := child.duplicate()
		_strip_runtime_scripts(copy)
		preview.add_child(copy)
		_set_owner_recursive(copy, preview)

	var packed := PackedScene.new()
	var pack_error := packed.pack(preview)
	if pack_error != OK:
		_fail("PackedScene.pack failed with error %d" % pack_error)
		return
	var output_path := _requested_output()
	var output_absolute := ProjectSettings.globalize_path(output_path)
	var output_directory := DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	if output_directory != OK and output_directory != ERR_ALREADY_EXISTS:
		_fail("Could not create preview output directory: %s" % output_absolute.get_base_dir())
		return
	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		_fail("Could not save preview scene %s (error %d)" % [output_path, save_error])
		return
	print("RESORT_PREVIEW_BAKE_PASS: output=%s children=%d static_geometry=%d" % [output_path, preview.get_child_count(), _count_static_geometry(preview)])
	_cleanup()
	get_tree().quit(0)

func _requested_output() -> String:
	var args := OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		var argument := str(args[index])
		if argument.begins_with("--output="):
			var value := argument.trim_prefix("--output=")
			if not value.is_empty():
				return value
		if argument == "--output" and index + 1 < args.size():
			var next_value := str(args[index + 1])
			if not next_value.is_empty():
				return next_value
	return DEFAULT_OUTPUT

func _mark_static_geometry(source: Node) -> void:
	for node: Node in source.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null and not bool(geometry.get_meta("gi_exclude", false)):
			geometry.gi_mode = GeometryInstance3D.GI_MODE_STATIC

func _strip_runtime_scripts(node: Node) -> void:
	for child: Node in node.get_children():
		_strip_runtime_scripts(child)
	node.set_script(null)

func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)

func _count_static_geometry(root_node: Node) -> int:
	return root_node.find_children("*", "GeometryInstance3D", true, false).size()

func _fail(message: String) -> void:
	push_error("RESORT_PREVIEW_BAKE_FAIL: " + message)
	_cleanup()
	get_tree().quit(1)

func _cleanup() -> void:
	if is_instance_valid(_active_preview):
		_active_preview.free()
	if is_instance_valid(_active_source):
		_active_source.free()
	_active_preview = null
	_active_source = null
