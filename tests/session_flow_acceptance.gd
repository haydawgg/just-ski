extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var ui: GameUI
var finish_trigger: Area3D
var frame := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_personal_best_persistence()
	skier = resort.get_node("Skier") as SkierController
	ui = resort.get_node("GameUI") as GameUI
	finish_trigger = resort.get_node("FinishTrigger") as Area3D
	if finish_trigger == null:
		failures.append("Finish trigger was not created")
		_finish()
	if resort.get_node_or_null("ParkContentTracker") == null:
		failures.append("Resort did not create the content observer")
	if ui.find_child("ChallengesButton", true, false) == null or ui.find_child("SpotChallengePanel", true, false) == null:
		failures.append("Pause UI did not expose spot challenges")

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 30:
		skier.scoring.accept_trick("Test 360", 1200, 0.8, LandingSolver.Outcome.CLEAN)
		skier.velocity = Vector3.ZERO
		skier.global_position = finish_trigger.global_position
	elif frame == 60:
		var snapshot := skier.scoring.snapshot()
		if not bool(snapshot.finished):
			failures.append("Crossing the finish did not finish the scoring run")
		if not get_tree().paused or not ui.results_panel.visible:
			failures.append("Crossing the finish did not open the paused results flow")
		if int(snapshot.total_score) < 1200 or str(snapshot.best_trick_name) != "Test 360":
			failures.append("Run results lost the scored trick summary")
		ui._results_continue()
		if get_tree().paused or bool(skier.scoring.snapshot().finished):
			failures.append("Keep Riding did not resume with a fresh scoring run")
		_finish()
	elif frame > 90:
		failures.append("Finish trigger did not respond in time")
		_finish()

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SESSION_FLOW_PASS: finish trigger, results summary, and continue flow passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("SESSION_FLOW_FAIL: " + failure)
		get_tree().quit(1)

func _test_personal_best_persistence() -> void:
	var path := "user://session_score_acceptance.cfg"
	var seed_config := ConfigFile.new()
	seed_config.set_value("records", "best_score", 10)
	seed_config.set_value("other_progress", "keep_me", "untouched")
	if seed_config.save(path) != OK:
		failures.append("Could not create isolated personal-best fixture")
		return
	var previous_best := SessionManager.best_score
	SessionManager.best_score = 10
	if not SessionManager.submit_score(25, path):
		failures.append("Personal-best save unexpectedly failed")
	else:
		var saved := ConfigFile.new()
		if saved.load(path) != OK:
			failures.append("Personal-best fixture could not be reloaded")
		elif str(saved.get_value("other_progress", "keep_me", "")) != "untouched":
			failures.append("Personal-best save discarded unrelated progress sections")
		if SessionManager.best_score != 25:
			failures.append("Successful personal-best save did not update in-memory score")
	var failed_before := SessionManager.best_score
	if SessionManager.submit_score(50, "user://missing-score-directory/score.cfg"):
		failures.append("Failed personal-best save reported success")
	if SessionManager.best_score != failed_before:
		failures.append("Failed personal-best save changed in-memory score")
	SessionManager.best_score = previous_best
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
