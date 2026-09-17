class_name RunScoring
extends Node

signal score_awarded(text: String, awarded_points: int, quality: float, outcome: int, snapshot: Dictionary)
signal score_changed(snapshot: Dictionary)
signal run_finished(snapshot: Dictionary)

const MAX_TOTAL_SCORE := 999999
const MIN_COMBO_POINTS := 80

@export var line_link_window := 4.5
@export var combo_window := 9.0
@export var maximum_multiplier := 4.0
@export var multiplier_step := 0.25
@export var line_bonus_points := 200

var total_score := 0
var combo_count := 0
var combo_multiplier := 1.0
var combo_remaining := 0.0
var link_remaining := 0.0
var last_feature_kind := ""
var pending_feature_kind := ""
var best_trick_name := ""
var best_trick_points := 0
var last_awarded_points := 0
var retry_count := 0
var landed_trick_count := 0
var clean_trick_count := 0
var bail_count := 0
var finished := false
var last_combo_break_reason := ""

func step(delta: float, speed: float) -> void:
	if combo_count > 0:
		combo_remaining = maxf(0.0, combo_remaining - delta)
		if combo_remaining <= 0.0:
			break_combo("timeout")
	if not last_feature_kind.is_empty():
		link_remaining = maxf(0.0, link_remaining - delta)
		if link_remaining <= 0.0 or speed < 2.5:
			reset_link()

func begin_feature(kind: String) -> void:
	pending_feature_kind = kind

func accept_trick(text: String, base_points: int, quality: float, outcome: int) -> void:
	if finished:
		return
	if base_points <= 0:
		pending_feature_kind = ""
		return
	var linked := (
		link_remaining > 0.0
		and not last_feature_kind.is_empty()
		and not pending_feature_kind.is_empty()
		and last_feature_kind != pending_feature_kind
	)
	var scored_text := text
	var adjusted_points := base_points
	if linked:
		scored_text = "Line Link + " + text
		adjusted_points += line_bonus_points
	var combo_eligible := adjusted_points >= MIN_COMBO_POINTS
	if combo_eligible:
		combo_count += 1
		combo_multiplier = minf(maximum_multiplier, 1.0 + float(combo_count - 1) * multiplier_step)
		combo_remaining = combo_window
	var awarded := adjusted_points if not combo_eligible else int(round(float(adjusted_points) * combo_multiplier))
	last_awarded_points = awarded
	total_score = mini(MAX_TOTAL_SCORE, total_score + awarded)
	landed_trick_count += 1
	if outcome == LandingSolver.Outcome.CLEAN:
		clean_trick_count += 1
	if base_points > best_trick_points:
		best_trick_points = base_points
		best_trick_name = text
	if not pending_feature_kind.is_empty():
		last_feature_kind = pending_feature_kind
		link_remaining = line_link_window
	pending_feature_kind = ""
	var current := snapshot()
	score_awarded.emit(scored_text, awarded, quality, outcome, current)
	score_changed.emit(current)

func bail() -> void:
	bail_count += 1
	reset_link()
	break_combo("bail")

func finish_run() -> void:
	if finished:
		return
	finished = true
	reset_link()
	var current := snapshot()
	score_changed.emit(current)
	run_finished.emit(current)

func reset_link() -> void:
	link_remaining = 0.0
	last_feature_kind = ""
	pending_feature_kind = ""

func reset_combo() -> void:
	combo_count = 0
	combo_multiplier = 1.0
	combo_remaining = 0.0
	score_changed.emit(snapshot())

func break_combo(reason: String = "manual") -> void:
	last_combo_break_reason = reason
	reset_combo()

func apply_retry_cost() -> void:
	var percent_cost := int(round(float(total_score) * 0.15))
	var cost := maxi(last_awarded_points, percent_cost)
	if cost <= 0 and total_score > 0:
		cost = mini(200, total_score)
	total_score = maxi(0, total_score - cost)
	retry_count += 1
	reset_link()
	break_combo("marker_retry")

func reset_run() -> void:
	total_score = 0
	best_trick_name = ""
	best_trick_points = 0
	last_awarded_points = 0
	retry_count = 0
	landed_trick_count = 0
	clean_trick_count = 0
	bail_count = 0
	finished = false
	last_combo_break_reason = "run_reset"
	reset_link()
	reset_combo()

func snapshot() -> Dictionary:
	return {
		"total_score": total_score,
		"combo_count": combo_count,
		"combo_multiplier": combo_multiplier,
		"combo_remaining": combo_remaining,
		"combo_window": combo_window,
		"link_remaining": link_remaining,
		"line_link_window": line_link_window,
		"last_feature_kind": last_feature_kind,
		"best_trick_name": best_trick_name,
		"best_trick_points": best_trick_points,
		"retry_count": retry_count,
		"landed_trick_count": landed_trick_count,
		"clean_trick_count": clean_trick_count,
		"bail_count": bail_count,
		"last_combo_break_reason": last_combo_break_reason,
		"finished": finished,
	}
