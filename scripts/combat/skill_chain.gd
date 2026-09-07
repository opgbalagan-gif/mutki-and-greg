class_name SkillChain
extends RefCounted

const BANK_DELAY := 3.2
const HIT_POINTS := 100
const MAX_MULTIPLIER := 5.0

var points := 0
var hits := 0
var remaining := 0.0
var multiplier: float:
	get:
		return minf(MAX_MULTIPLIER, 1.0 + floorf(float(hits) / 2.0) * 0.2)


func hit() -> void:
	hits += 1
	points += HIT_POINTS
	remaining = BANK_DELAY


func add_bonus(value: int) -> void:
	points += maxi(0, value)
	remaining = BANK_DELAY


func advance(delta: float) -> int:
	if points == 0:
		return 0
	remaining = maxf(0.0, remaining - delta)
	return bank() if remaining == 0.0 else 0


func bank() -> int:
	var result := roundi(points * multiplier)
	clear()
	return result


func clear() -> void:
	points = 0
	hits = 0
	remaining = 0.0
