extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_grab_contact_contracts()
	AudioManager.shutdown_audio()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SOLVER_GRAB_CONTRACT_PASS: grab acquire and maintenance envelopes passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_GRAB_CONTRACT_FAIL: " + failure)
	get_tree().quit(1)

func _test_grab_contact_contracts() -> void:
	var grab := GrabPoseLayer.new()
	var definition := GrabAnimationDefinition.new()
	if GrabPoseLayer.CONTACT_ACQUIRE_CAP > 0.141:
		failures.append("Grab acquire cap %.3f m still permits proximity awards" % GrabPoseLayer.CONTACT_ACQUIRE_CAP)
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, false, 0.16):
		failures.append("Grab latched at 0.16 m without convincing hand-to-ski contact")
	if not grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, false, 0.10):
		failures.append("Grab refused a convincing 0.10 m hand-to-ski contact")
	if not grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, true, 0.11):
		failures.append("Held grab dropped inside its 0.12 m maintenance envelope")
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.5, 0.08, true, 0.13):
		failures.append("Held grab survived outside its maintenance envelope")
	if grab.should_latch_contact(definition, 1.0, true, 0.9, 0.03, 0.08, false, 0.05):
		failures.append("Grab latched before the minimum air time")
