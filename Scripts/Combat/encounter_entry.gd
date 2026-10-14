class_name EncounterEntry
extends Resource
## Строка таблицы встреч: какой противник и как часто.

@export var enemy: EnemyData
@export_range(1, 100) var weight: int = 30
## Ночью вес умножается на это (2 — вдвое чаще, 0 — ночью не встречается).
## Работает только на локациях с LocationData.time_of_day_matters.
@export_range(0.0, 10.0, 0.1) var night_weight_multiplier: float = 1.0


func get_weight(is_night: bool) -> float:
	return weight * (night_weight_multiplier if is_night else 1.0)
