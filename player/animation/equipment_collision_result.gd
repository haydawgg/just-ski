class_name EquipmentCollisionResult
extends RefCounted

var valid := true
var translations: Dictionary = {}
var directions: Dictionary = {}
var applied_contacts: Array[Dictionary] = []
var unresolved_contacts: Array[Dictionary] = []
var proxy_count := 0
var pair_count := 0
var iterations := 0
var max_penetration := 0.0

func snapshot() -> Dictionary:
	return {
		"valid": valid,
		"proxy_count": proxy_count,
		"pair_count": pair_count,
		"iterations": iterations,
		"applied_contact_count": applied_contacts.size(),
		"unresolved_count": unresolved_contacts.size(),
		"max_penetration_m": max_penetration,
		"unresolved": unresolved_contacts.duplicate(true),
	}
