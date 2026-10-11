class_name StatusEffect
extends Resource
## Эффект состояния на персонаже: бафф/дебафф к характеристикам с
## длительностью в ИГРОВЫХ МИНУТАХ (шаг в лабиринте — 10 мин, переход в
## хабе — 5, см. PlayerState). Позже на этом же механизме встанут пассивные
## навыки (бессрочный эффект).
##
## Группа — для эффектов-"лестниц": в одной группе на персонаже висит только
## одна стадия (опьянение: слабое -> среднее -> сильное). Новая стадия
## СМЕНЯЕТ старую, а не складывается с ней. См. CharacterStats.apply_effect.

@export var effect_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Скрытый от игрока (не показывается на экране персонажа в обычной игре).
@export var hidden: bool = false

@export_group("Модификаторы характеристик")
@export var str_mod: int = 0
@export var dex_mod: int = 0
@export var con_mod: int = 0
@export var int_mod: int = 0
@export var cha_mod: int = 0
@export var lew_mod: int = 0

@export_group("Длительность")
## В игровых минутах. 0 — бессрочно (пока не снимут кодом/событием).
## Для эффектов, которые включает сама система (пороги возбуждения,
## изнурение), не используется.
@export_range(0, 100000) var duration_minutes: int = 60

@export_group("Группа / стадии")
## Пусто — эффект сам по себе (повторное наложение просто продлевает его).
@export var group: String = ""
## Номер стадии в группе (1 — самая слабая).
@export_range(1, 10) var stage: int = 1
## Следующая стадия — куда эффект растёт при повторном наложении.
@export var next_stage: StatusEffect


func get_modifier(stat: String) -> int:
	match stat:
		"STR": return str_mod
		"DEX": return dex_mod
		"CON": return con_mod
		"INT": return int_mod
		"CHA": return cha_mod
		"LEW": return lew_mod
	return 0


## "STR +1, DEX -1" — для отладочных экранов.
func describe_modifiers() -> String:
	var parts: PackedStringArray = []
	for stat in CharacterStats.STATS:
		var value := get_modifier(stat)
		if value != 0:
			parts.append("%s %+d" % [stat, value])
	return ", ".join(parts)
