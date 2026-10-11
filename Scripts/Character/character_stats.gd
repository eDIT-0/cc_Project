class_name CharacterStats
extends RefCounted
## Состояние персонажа: характеристики, здоровье, выносливость, возбуждение
## и эффекты состояния. Чистая логика без UI (как Inventory); владелец —
## PlayerState.stats.
##
## Итоговая характеристика = база + модификаторы всех активных эффектов
## (не ниже 0, LEW — ещё и не выше 100). Вся логика и диалоги смотрят ТОЛЬКО
## на итоговое значение (get_stat): "пьяный" и "прокачанный" проверяются
## одинаково.
##
## Активные эффекты — это:
##   1) наложенные (предметы, события) — с таймером в игровых минутах;
##   2) системные, включаются сами по состоянию:
##      - стадия возбуждения (пороги AROUSAL_STAGES);
##      - "Изнурение", пока выносливость на нуле.
##
## Из диалога: PlayerState.stats.get_stat("DEX"), PlayerState.stats.add_arousal(10)

signal changed
## Возбуждение дошло до 100 и сбросилось в 0. Последствия — TODO.
signal arousal_peaked
## Здоровье упало до 0. Обработку смерти подключит бой/забег — TODO.
signal died
## Новый уровень (может прийти несколько раз подряд за одну большую награду).
signal leveled_up(new_level: int)

const STATS: PackedStringArray = ["STR", "DEX", "CON", "INT", "CHA", "LEW"]
const STAT_NAMES := {
	"STR": "Сила", "DEX": "Ловкость", "CON": "Телосложение",
	"INT": "Интеллект", "CHA": "Харизма", "LEW": "Похоть",
}
const START_STATS := { "STR": 4, "DEX": 6, "CON": 5, "INT": 3, "CHA": 4, "LEW": 0 }
const LEW_MAX := 100

## Здоровье / выносливость от телосложения.
const HP_BASE := 20
const HP_PER_CON := 4
const STAMINA_BASE := 50
const STAMINA_PER_CON := 10

const AROUSAL_MAX := 100
## Пороги возбуждения -> эффект штрафа (по убыванию порога).
const AROUSAL_STAGES := [
	[75, "res://Data/Status/arousal_3.tres"],
	[50, "res://Data/Status/arousal_2.tres"],
	[25, "res://Data/Status/arousal_1.tres"],
]
const EXHAUSTED_PATH := "res://Data/Status/exhausted.tres"

## Проверки характеристик (скиллчеки). Сложность — в тех же единицах, что и
## характеристика: характеристика == сложности -> 50%, каждое очко +-10%.
## Шанс игроку не показывается; но если он <= CHECK_HOPELESS_CHANCE —
## честно предупреждаем ("даже пытаться не стоит"), как мастер в D&D.
## Опыт и уровни. Сколько опыта нужно с уровня L на L+1:
##   XP_BASE * L^XP_EXPONENT (округлено до 10)
##   1->2: 100, 2->3: 280, 3->4: 520, 5->6: 1120, 10->11: 3160, 19->20: 8280
## "Степенная" кривая (как в большинстве классических RPG): первые уровни
## быстрые, дальше всё медленнее, но без взрывного роста экспоненты.
## Ориентир наград (поле xp_reward у квестов): сайд-квест по сложности
## 30 / 50 / 80 / 120 / 180, основной квест локации — 100 (только за первое
## прохождение). Бой добавит свой опыт позже.
const MAX_LEVEL := 20
const XP_BASE := 100.0
const XP_EXPONENT := 1.5
## Очков характеристик за уровень. Одно очко = +10% к проверкам — это много,
## поэтому по одному. LEW очками не поднимается.
const STAT_POINTS_PER_LEVEL := 1
## Потолок БАЗОВОГО значения при прокачке (эффекты могут поднять выше).
const BASE_STAT_MAX := 20

const CHECK_BASE_CHANCE := 0.5
const CHECK_STEP := 0.1
const CHECK_MIN_CHANCE := 0.05
const CHECK_MAX_CHANCE := 0.95
const CHECK_HOPELESS_CHANCE := 0.1

var hp: int = 0
var stamina: int = 0
var arousal: int = 0

var level: int = 1
## Опыт, набранный на текущем уровне (обнуляется при повышении).
var xp: int = 0
var stat_points: int = 0

var _base: Dictionary = {}
## Наложенные эффекты: { "effect": StatusEffect, "remaining": int } (-1 — бессрочно).
var _effects: Array[Dictionary] = []
var _arousal_effects: Array = []   # [[порог, StatusEffect], ...]
var _exhausted_effect: StatusEffect


func _init() -> void:
	_base = START_STATS.duplicate()
	for entry in AROUSAL_STAGES:
		var effect := load(entry[1]) as StatusEffect
		if effect == null:
			push_error("CharacterStats: не найден %s" % entry[1])
		_arousal_effects.append([entry[0], effect])
	_exhausted_effect = load(EXHAUSTED_PATH) as StatusEffect
	if _exhausted_effect == null:
		push_error("CharacterStats: не найден %s" % EXHAUSTED_PATH)
	hp = get_max_hp()
	stamina = get_max_stamina()


# ====================== ХАРАКТЕРИСТИКИ ======================

func get_base(stat: String) -> int:
	return _base.get(stat, 0)


## Прокачка (уровни — позже) и события. LEW так тоже можно, но для неё
## есть add_lewdness().
func add_base(stat: String, amount: int) -> void:
	if not _base.has(stat):
		push_error("CharacterStats: неизвестная характеристика '%s'." % stat)
		return
	_base[stat] = maxi(0, _base[stat] + amount)
	if stat == "LEW":
		_base[stat] = mini(_base[stat], LEW_MAX)
	_on_stats_changed()


## Похоть растёт (и изредка падает) только от событий и решений.
func add_lewdness(amount: int) -> void:
	add_base("LEW", amount)


func get_modifier(stat: String) -> int:
	var total := 0
	for effect in get_active_effects():
		total += effect.get_modifier(stat)
	return total


## Итоговое значение — именно его используют проверки, диалоги, бой.
func get_stat(stat: String) -> int:
	var value := maxi(0, get_base(stat) + get_modifier(stat))
	return mini(value, LEW_MAX) if stat == "LEW" else value


# ====================== ОПЫТ И УРОВНИ ======================

## Сколько опыта нужно, чтобы перейти с уровня from_level на следующий.
static func xp_to_next(from_level: int) -> int:
	return roundi(XP_BASE * pow(from_level, XP_EXPONENT) / 10.0) * 10


func add_xp(amount: int) -> void:
	if amount <= 0 or level >= MAX_LEVEL:
		return
	xp += amount
	print("⭐ +%d опыта" % amount)
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		stat_points += STAT_POINTS_PER_LEVEL
		print("⭐ Новый уровень: %d (очков характеристик: %d)" % [level, stat_points])
		leveled_up.emit(level)
	if level >= MAX_LEVEL:
		xp = 0
	changed.emit()


func can_raise_stat(stat: String) -> bool:
	return stat != "LEW" and _base.has(stat) and stat_points > 0 and _base[stat] < BASE_STAT_MAX


## Потратить очко на характеристику. CON сразу добавляет и текущие
## здоровье/выносливость (а не только максимум) — прокачка ощущается сразу.
func raise_stat(stat: String) -> bool:
	if not can_raise_stat(stat):
		return false
	stat_points -= 1
	_base[stat] += 1
	if stat == "CON":
		hp += HP_PER_CON
		stamina += STAMINA_PER_CON
	_on_stats_changed()
	return true


# ====================== ПРОВЕРКИ ======================

## Шанс успеха проверки (0..1) по ИТОГОВОМУ значению характеристики.
func get_check_chance(stat: String, difficulty: int) -> float:
	var chance := CHECK_BASE_CHANCE + (get_stat(stat) - difficulty) * CHECK_STEP
	return clampf(chance, CHECK_MIN_CHANCE, CHECK_MAX_CHANCE)


## Шанс настолько мал, что игрока стоит предупредить.
func is_check_hopeless(stat: String, difficulty: int) -> bool:
	return get_check_chance(stat, difficulty) <= CHECK_HOPELESS_CHANCE + 0.0001


## Бросок проверки. Шанс пишется только в консоль (для отладки).
func roll_check(stat: String, difficulty: int) -> bool:
	var chance := get_check_chance(stat, difficulty)
	var success := randf() < chance
	print("🎲 Проверка %s (%d) против сложности %d: шанс %d%% — %s" % [
		stat, get_stat(stat), difficulty, roundi(chance * 100), "успех" if success else "провал"])
	return success


# ====================== ЗДОРОВЬЕ / ВЫНОСЛИВОСТЬ / ВОЗБУЖДЕНИЕ ======================

func get_max_hp() -> int:
	return HP_BASE + get_stat("CON") * HP_PER_CON


func get_max_stamina() -> int:
	return STAMINA_BASE + get_stat("CON") * STAMINA_PER_CON


## Возвращает, сколько реально вылечено (0 — здоровье и так полное).
func heal(amount: int) -> int:
	var healed := clampi(amount, 0, get_max_hp() - hp)
	if healed > 0:
		hp += healed
		changed.emit()
	return healed


func damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = maxi(0, hp - amount)
	changed.emit()
	if hp == 0:
		died.emit()


func restore_stamina(amount: int) -> int:
	var restored := clampi(amount, 0, get_max_stamina() - stamina)
	if restored > 0:
		stamina += restored
		_on_stats_changed()  # могло снять "Изнурение"
	return restored


## Тратит сколько есть (не ниже 0). На нуле включается "Изнурение".
func spend_stamina(amount: int) -> void:
	if amount <= 0:
		return
	stamina = maxi(0, stamina - amount)
	_on_stats_changed()


## Возбуждение. Дошло до AROUSAL_MAX — сброс в 0 и сигнал arousal_peaked.
func add_arousal(amount: int) -> void:
	arousal = maxi(0, arousal + amount)
	if arousal >= AROUSAL_MAX:
		arousal = 0
		_on_stats_changed()
		arousal_peaked.emit()
		return
	_on_stats_changed()


## После поражения: здоровье и выносливость — не меньше доли от максимума
## (то, что выше, не срезаем).
func restore_to_fraction(fraction: float) -> void:
	hp = maxi(hp, maxi(1, ceili(get_max_hp() * fraction)))
	stamina = maxi(stamina, ceili(get_max_stamina() * fraction))
	_on_stats_changed()


## Сон / полный отдых.
func restore_all() -> void:
	hp = get_max_hp()
	stamina = get_max_stamina()
	_on_stats_changed()


# ====================== ЭФФЕКТЫ ======================

## Наложить эффект. stack_stages — на сколько стадий поднять уже висящий
## эффект той же группы (пиво — 1, самогон — 2). Правила:
##   - группы на персонаже нет -> вешаем effect как есть;
##   - группа есть -> стадия = max(текущая + stack_stages, effect.stage),
##     дальше последней стадии не растёт; таймер — заново от новой стадии
##     (если стадия не сменилась — продлевается, но не укорачивается);
##   - без группы: тот же effect_id уже висит -> просто продлеваем.
func apply_effect(effect: StatusEffect, stack_stages: int = 0) -> void:
	if effect == null:
		return
	var index := _find_effect_index(effect)
	if index < 0:
		_effects.append({ "effect": effect, "remaining": _duration_of(effect) })
		print("✨ Эффект: %s" % effect.display_name)
		_on_stats_changed()
		return

	var current: StatusEffect = _effects[index].effect
	var target := current
	if not effect.group.is_empty():
		for i in range(stack_stages):
			if target.next_stage == null:
				break
			target = target.next_stage
		if effect.stage > target.stage:
			target = effect

	if target == current:
		var remaining: int = _effects[index].remaining
		if remaining >= 0:
			_effects[index].remaining = maxi(remaining, _duration_of(target))
	else:
		_effects[index] = { "effect": target, "remaining": _duration_of(target) }
	print("✨ Эффект: %s" % target.display_name)
	_on_stats_changed()


func remove_effect(effect_id: String) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		if _effects[i].effect.effect_id == effect_id:
			_effects.remove_at(i)
	_on_stats_changed()


func remove_group(group: String) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		if _effects[i].effect.group == group:
			_effects.remove_at(i)
	_on_stats_changed()


func has_effect(effect_id: String) -> bool:
	for effect in get_active_effects():
		if effect.effect_id == effect_id:
			return true
	return false


func has_group(group: String) -> bool:
	for effect in get_active_effects():
		if effect.group == group:
			return true
	return false


## Все действующие эффекты: наложенные + системные (возбуждение, изнурение).
func get_active_effects() -> Array[StatusEffect]:
	var result: Array[StatusEffect] = []
	for entry in _effects:
		result.append(entry.effect)
	var arousal_effect := _get_arousal_effect()
	if arousal_effect != null:
		result.append(arousal_effect)
	if stamina <= 0 and _exhausted_effect != null:
		result.append(_exhausted_effect)
	return result


## Для экрана: [{ "effect", "remaining" }] — remaining -1 у бессрочных и системных.
func get_effects_for_display() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _effects:
		result.append(entry.duplicate())
	var arousal_effect := _get_arousal_effect()
	if arousal_effect != null:
		result.append({ "effect": arousal_effect, "remaining": -1, "system": true })
	if stamina <= 0 and _exhausted_effect != null:
		result.append({ "effect": _exhausted_effect, "remaining": -1, "system": true })
	return result


## Прошло игровое время: тикают таймеры эффектов.
func advance_time(minutes: int) -> void:
	if minutes <= 0:
		return
	var expired := false
	for i in range(_effects.size() - 1, -1, -1):
		var entry: Dictionary = _effects[i]
		if entry.remaining < 0:
			continue
		entry.remaining -= minutes
		if entry.remaining <= 0:
			print("⌛ Эффект закончился: %s" % entry.effect.display_name)
			_effects.remove_at(i)
			expired = true
	if expired:
		_on_stats_changed()
	else:
		changed.emit()


# ====================== ВНУТРЕННЕЕ ======================

func _find_effect_index(effect: StatusEffect) -> int:
	for i in range(_effects.size()):
		var other: StatusEffect = _effects[i].effect
		if not effect.group.is_empty():
			if other.group == effect.group:
				return i
		elif other.effect_id == effect.effect_id:
			return i
	return -1


func _duration_of(effect: StatusEffect) -> int:
	return effect.duration_minutes if effect.duration_minutes > 0 else -1


func _get_arousal_effect() -> StatusEffect:
	for entry in _arousal_effects:
		if arousal >= entry[0]:
			return entry[1]
	return null


## Характеристики могли измениться (CON -> максимумы) — подрезаем
## текущие значения под новые максимумы.
func _on_stats_changed() -> void:
	hp = mini(hp, get_max_hp())
	stamina = mini(stamina, get_max_stamina())
	changed.emit()
