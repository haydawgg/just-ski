class_name ClipTimeline
extends RefCounted

## Reconstructs a constant-rate presentation timeline from asynchronously
## encoded capture slots. A missing slot repeats the nearest known frame so
## encoder back-pressure does not shorten the recorded run.

static func expand(slotted_frames: Dictionary, slot_count: int) -> Array[PackedByteArray]:
	var timeline: Array[PackedByteArray] = []
	if slot_count <= 0 or slotted_frames.is_empty():
		return timeline

	var first_slot := -1
	for raw_slot in slotted_frames.keys():
		var slot := int(raw_slot)
		if slot < 0 or slot >= slot_count:
			continue
		var frame: Variant = slotted_frames[raw_slot]
		if frame is PackedByteArray and not (frame as PackedByteArray).is_empty():
			if first_slot < 0 or slot < first_slot:
				first_slot = slot
	if first_slot < 0:
		return timeline

	var current: PackedByteArray = slotted_frames[first_slot]
	for slot: int in slot_count:
		var candidate: Variant = slotted_frames.get(slot, PackedByteArray())
		if candidate is PackedByteArray and not (candidate as PackedByteArray).is_empty():
			current = candidate
		timeline.append(current)
	return timeline
