class_name Encounter
extends RefCounted
## Одна встреча с противниками в лабиринте (живёт, пока она не закончится).
## Создаёт DungeonRun на клетке ENEMY. Диалоги встречи только ВЫБИРАЮТ, что
## дальше (методы ниже), а делает это DungeonRun после конца диалога —
## так диалоги не запускают друг друга изнутри.
##
## В .dialogue (передаётся как "enc"):
##   {{enc.get_names_text()}}   кто перед тобой
##   enc.ambush_difficulty / sneak_difficulty / talk_difficulty  — уже с поправкой на группу
##   do enc.fight()              обычный бой
##   do enc.ambush_success()     бой, игрок бьёт первым (враг пропускает ход)
##   do enc.fight_enemy_first()  бой, враг бьёт первым (провал скрытности)
##   do enc.sneak_past()         обойти: доля опыта (sneak_xp_fraction)
##   do enc.avoid(0.5)           обойти иначе (уговорил) — своя доля опыта
##   do enc.talk()               перейти к разговору (диалог противника)
##   do enc.win() / enc.lose()   итог боя

## С чего начинается бой.
enum Opening { NORMAL, PLAYER_FIRST, ENEMY_FIRST }
## Что сделать после конца текущего диалога.
enum Next { NONE, FIGHT, TALK, AVOID, WIN, LOSE }

## HP и скрытые шкалы сохраняются после побега до конца забега.
## Новый бой заряжается с нуля; временные боевые эффекты не переносятся.
var saved_enemy_state: Array[Dictionary] = []
var enemies: Array[EnemyData] = []
var table: EncounterTable
var opening: Opening = Opening.NORMAL
var next_step: Next = Next.NONE
var avoid_xp_fraction: float = 0.0

var ambush_difficulty: int
var sneak_difficulty: int
var talk_difficulty: int


func _init(encounter_enemies: Array[EnemyData], encounter_table: EncounterTable) -> void:
	enemies = encounter_enemies
	table = encounter_table
	var penalty := (get_count() - 1) * table.group_check_penalty
	ambush_difficulty = table.ambush_difficulty + penalty
	sneak_difficulty = table.sneak_difficulty + penalty
	talk_difficulty = table.talk_difficulty + penalty


# ====================== ЧТЕНИЕ ======================

func get_count() -> int:
	return enemies.size()


## Главный в группе (первый) — его разговор и сцена поражения.
func get_leader() -> EnemyData:
	return enemies[0]


## "Бандит ×2, Бродячий пёс"
func get_names_text() -> String:
	var counts := {}
	var order: Array[String] = []
	for e in enemies:
		if not counts.has(e.display_name):
			counts[e.display_name] = 0
			order.append(e.display_name)
		counts[e.display_name] += 1
	var parts: PackedStringArray = []
	for enemy_name in order:
		parts.append(enemy_name if counts[enemy_name] == 1 else "%s ×%d" % [enemy_name, counts[enemy_name]])
	return ", ".join(parts)


## Опыт за победу — сумма по группе.
func get_total_xp() -> int:
	var total := 0
	for e in enemies:
		total += e.xp_reward
	return total


## Опыт за обход с долей fraction, с бонусом за размер группы.
func get_avoid_xp(fraction: float) -> int:
	var group_bonus := 1.0 + table.avoid_group_xp_bonus * (get_count() - 1)
	return roundi(get_total_xp() * fraction * group_bonus)


func get_sneak_xp() -> int:
	return get_avoid_xp(table.sneak_xp_fraction)


func get_opening_text() -> String:
	match opening:
		Opening.PLAYER_FIRST:
			return "Засада удалась — зарядка врагов временно заблокирована."
		Opening.ENEMY_FIRST:
			return "Тебя застали врасплох — твоя зарядка временно заблокирована."
	return "Обычное начало боя."


# ====================== ВЫБОР (из диалогов) ======================

func fight() -> void:
	opening = Opening.NORMAL
	next_step = Next.FIGHT


func ambush_success() -> void:
	opening = Opening.PLAYER_FIRST
	next_step = Next.FIGHT


func fight_enemy_first() -> void:
	opening = Opening.ENEMY_FIRST
	next_step = Next.FIGHT


func sneak_past() -> void:
	avoid(table.sneak_xp_fraction)


func avoid(xp_fraction: float = 0.0) -> void:
	avoid_xp_fraction = xp_fraction
	next_step = Next.AVOID


func talk() -> void:
	next_step = Next.TALK


func win() -> void:
	next_step = Next.WIN


func lose() -> void:
	next_step = Next.LOSE
