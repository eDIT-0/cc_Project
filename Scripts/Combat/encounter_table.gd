class_name EncounterTable
extends Resource
## Встречи с противниками для одной локации и одной сложности
## (LocationData.encounters_easy ... encounters_extreme; нет своей —
## берётся ближайшая более лёгкая, как с добычей).

@export var entries: Array[EncounterEntry] = []

@export_group("Группы")
## Шансы на дополнительных противников по очереди: [0.25, 0.1] — второй
## с шансом 25%, третий (только если выпал второй) — 10%. Пусто — всегда один.
## Каждый противник разыгрывается отдельно: группа может быть смешанной.
@export var extra_enemy_chances: Array[float] = [0.25, 0.1]

@export_group("Заметил первым")
## Шанс, что игрок заметит врага раньше (тогда — выбор: засада, проскользнуть,
## заговорить). Итог = база + ночь + ловкость/интеллект + опьянение
## + PlayerState.get_stealth_bonus() (одежда, навыки — потом).
@export_range(0.0, 1.0, 0.01) var spot_base: float = 0.1
## Ночью (только локации с time_of_day_matters).
@export_range(0.0, 1.0, 0.01) var spot_night_bonus: float = 0.15
## За каждое очко выше 5 (ниже 5 — минус).
@export_range(0.0, 0.2, 0.005) var spot_per_dex: float = 0.02
@export_range(0.0, 0.2, 0.005) var spot_per_int: float = 0.01
## За стадию опьянения (отрицательное — пьяный замечает хуже).
@export_range(-0.5, 0.0, 0.01) var spot_per_drunk_stage: float = -0.05
@export_range(0.0, 1.0, 0.01) var spot_max: float = 0.9

@export_group("Проверки")
@export_range(0, 20) var ambush_difficulty: int = 6   ## сила
@export_range(0, 20) var sneak_difficulty: int = 6    ## ловкость
@export_range(0, 20) var talk_difficulty: int = 6     ## харизма
## Каждый противник сверх первого добавляет к сложности.
@export_range(0, 5) var group_check_penalty: int = 1

@export_group("Опыт за обход")
## Проскользнул — эта доля от опыта за бой.
@export_range(0.0, 1.0, 0.05) var sneak_xp_fraction: float = 0.5
## Обошёл группу — бонус за каждого противника сверх первого (0.25 = +25%).
@export_range(0.0, 1.0, 0.05) var avoid_group_xp_bonus: float = 0.25


## Разыграть состав встречи.
func roll_enemies(is_night: bool) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	var first := _pick(is_night)
	if first == null:
		return result
	result.append(first)
	for chance in extra_enemy_chances:
		if randf() >= chance:
			break
		var extra := _pick(is_night)
		if extra != null:
			result.append(extra)
	return result


## Шанс заметить первым прямо сейчас.
func get_spot_chance(time_matters: bool) -> float:
	var st: CharacterStats = PlayerState.stats
	var chance := spot_base
	if time_matters and PlayerState.clock.is_night():
		chance += spot_night_bonus
	chance += (st.get_stat("DEX") - 5) * spot_per_dex
	chance += (st.get_stat("INT") - 5) * spot_per_int
	chance += st.get_group_stage("drunk") * spot_per_drunk_stage
	chance += PlayerState.get_stealth_bonus()
	return clampf(chance, 0.0, spot_max)


func _pick(is_night: bool) -> EnemyData:
	var total := 0.0
	for e in entries:
		if e != null and e.enemy != null:
			total += e.get_weight(is_night)
	if total <= 0.0:
		return null
	var roll := randf() * total
	for e in entries:
		if e == null or e.enemy == null:
			continue
		roll -= e.get_weight(is_night)
		if roll < 0.0:
			return e.enemy
	return null
