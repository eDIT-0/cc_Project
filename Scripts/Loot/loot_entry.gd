class_name LootEntry
extends Resource
## Одна строка таблицы добычи: что может выпасть, как часто и сколько.

@export var item: ItemData
## ОТНОСИТЕЛЬНЫЙ вес (важна пропорция между строками таблицы).
@export_range(0.0, 100.0, 0.05, "or_greater") var weight: float = 1.0
@export_range(1, 999) var min_count: int = 1
@export_range(1, 999) var max_count: int = 1
