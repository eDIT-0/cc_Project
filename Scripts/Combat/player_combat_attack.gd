class_name PlayerCombatAttack
extends Resource
## Активная уникальная атака. Пока доступ задаётся простыми требованиями;
## полноценное получение навыков будет отдельным этапом после боёвки.

@export var attack_id: String = "groin_strike"
@export var display_name: String = "Удар в пах"
@export_multiline var description: String = "Мощный удар, который срывает подготовку противника оглушением."
@export var tags: PackedStringArray = PackedStringArray(["strike", "stun", "groin", "unique"])
@export_range(1.0, 100.0) var energy_cost: float = 100.0
@export_range(0, 1000) var base_damage: int = 8
@export_range(0.0, 10.0) var damage_per_str: float = 2.0
@export_range(0.0, 30.0) var stun_seconds: float = 4.0
@export_range(0, 100) var stamina_cost: int = 4
@export_range(1, 20) var min_level: int = 1
@export_range(0, 20) var min_dex: int = 0
@export var requires_free_legs: bool = true
