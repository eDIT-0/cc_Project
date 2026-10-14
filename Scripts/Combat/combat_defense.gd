class_name CombatDefense
extends RefCounted
## Состояние одной мини-игры, без UI, урона или SceneTree. Контроллер
## тикает только её часы, пока остальной бой заморожен.

enum Kind { AUTO, NONE, STOP_BAR, MASH }
enum Grade { PENDING, FAIL, PARTIAL, PERFECT }

var kind: Kind = Kind.STOP_BAR
var grade: Grade = Grade.PENDING
var elapsed: float = 0.0
var lead_in: float = 0.35
var duration: float = 3.5
var cursor: float = 0.0
var center: float = 0.5
var perfect_width: float = 0.08
var partial_width: float = 0.32
var cycle_seconds: float = 2.4
var presses: int = 0
var goal: int = 12
var partial_goal: int = 8
var min_press_interval: float = 0.08
var _last_press_time: float = -100.0


func configure(game_kind: Kind, rules: CombatRules, dex: int, difficulty: float) -> void:
	kind = game_kind
	grade = Grade.PENDING
	elapsed = 0.0
	cursor = 0.0
	presses = 0
	_last_press_time = -100.0
	lead_in = maxf(0.0, rules.defense_lead_in_seconds)
	min_press_interval = maxf(0.0, rules.defense_min_press_interval)
	var dex_multiplier := clampf(1.0 + (dex - 5) * rules.defense_dex_per_point, 0.5, 2.0)
	var challenge := clampf(difficulty, 0.25, 4.0)
	if kind == Kind.MASH:
		duration = maxf(0.5, rules.defense_mash_seconds)
		goal = maxi(1, roundi(rules.defense_mash_goal * challenge / dex_multiplier))
		# Требование должно быть выполнимо при установленном ограничении ввода.
		if min_press_interval > 0.0:
			goal = mini(goal, maxi(1, ceili(duration / min_press_interval)))
		partial_goal = clampi(ceili(goal * rules.defense_mash_partial_fraction), 1, goal)
	else:
		kind = Kind.STOP_BAR
		duration = maxf(0.5, rules.defense_stop_seconds)
		cycle_seconds = maxf(0.4, rules.defense_stop_cycle_seconds / challenge)
		perfect_width = clampf(rules.defense_perfect_width * dex_multiplier / challenge, 0.02, 0.5)
		partial_width = clampf(maxf(perfect_width, rules.defense_partial_width * dex_multiplier / challenge), perfect_width, 0.8)
		# Все зоны целиком внутри полосы, положение слегка меняется между атаками.
		center = randf_range(partial_width / 2.0 + 0.05, 0.95 - partial_width / 2.0)


func is_finished() -> bool:
	return grade != Grade.PENDING


func is_armed() -> bool:
	return not is_finished() and elapsed >= lead_in


func get_time_left() -> float:
	return maxf(0.0, duration - maxf(0.0, elapsed - lead_in))


func advance(seconds: float) -> void:
	if is_finished():
		return
	elapsed += maxf(0.0, seconds)
	var playing_time := maxf(0.0, elapsed - lead_in)
	if kind == Kind.STOP_BAR:
		cursor = 1.0 - absf(fmod(playing_time * 2.0 / cycle_seconds, 2.0) - 1.0)
	if playing_time >= duration:
		grade = Grade.PARTIAL if kind == Kind.MASH and presses >= partial_goal else Grade.FAIL


func press() -> void:
	if not is_armed() or elapsed - _last_press_time < min_press_interval:
		return
	_last_press_time = elapsed
	if kind == Kind.MASH:
		presses += 1
		if presses >= goal:
			grade = Grade.PERFECT
	else:
		var distance := absf(cursor - center)
		if distance <= perfect_width / 2.0:
			grade = Grade.PERFECT
		elif distance <= partial_width / 2.0:
			grade = Grade.PARTIAL
		else:
			grade = Grade.FAIL


func fail() -> void:
	if not is_finished():
		grade = Grade.FAIL
