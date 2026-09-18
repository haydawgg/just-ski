class_name EquipmentCollisionContext
extends RefCounted

## State needed by the presentation-only self-collision pass. Gameplay
## transforms and world collision are intentionally absent from this interface.

var locomotion_state := 0
var skis_locked := false
var clearance := 0.015
var tolerance := 0.001
var iterations := 6
var max_step := 0.06
var grab_targets: Dictionary = {}
