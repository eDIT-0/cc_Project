class_name DifficultyTuning
extends Resource
## Ручная балансировка одного уровня сложности. Значения — ДОБАВКИ поверх
## базовых чисел из LocationData, а не абсолютные значения — так одна и та же
## локация (тема/арт/ивенты) переиспользуется на всех 5 уровнях, а сложность
## просто усиливает или ослабляет её.

@export var level: Difficulty.Level = Difficulty.Level.NORMAL

@export_group("Размер лабиринта")
@export var room_count_bonus: int = 0        # добавляется к room_count_x и room_count_y
@export var min_quest_distance_bonus: int = 0

@export_group("Веса событий (добавка к весу, может быть отрицательной)")
@export_range(-10.0, 10.0, 0.05, "or_greater", "or_less") var enemy_weight_delta: float = 0.0
@export_range(-10.0, 10.0, 0.05, "or_greater", "or_less") var reward_weight_delta: float = 0.0
@export_range(-10.0, 10.0, 0.05, "or_greater", "or_less") var random_event_weight_delta: float = 0.0

@export_group("Награды и торговец")
@export var min_reward_count_bonus: int = 0
@export_range(-1.0, 1.0) var merchant_chance_delta: float = 0.0
