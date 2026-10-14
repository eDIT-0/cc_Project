class_name CombatRules
extends Resource
## Настройки первого боевого прототипа. Время — реальные секунды боя,
## не игровые минуты GameClock. Ресурс общий; состояние в нём не хранится.

@export_group("Зарядка")
@export_range(0.1, 120.0) var player_charge_seconds: float = 14.0
@export_range(0.01, 5.0) var player_speed_multiplier: float = 1.0
## Множитель ловкости: 1 + (DEX - 5) * dex_speed_per_point.
@export_range(0.0, 0.2) var dex_speed_per_point: float = 0.02
@export_range(0.01, 1.0) var exhausted_speed_multiplier: float = 0.75
## EASY, NORMAL, HARD, VERY_HARD, EXTREME — скорость врагов.
@export var enemy_difficulty_speed: PackedFloat32Array = PackedFloat32Array([0.9, 1.0, 1.1, 1.2, 1.3])

@export_group("Задержки")
@export_range(0.0, 120.0) var ambush_delay_seconds: float = 18.0
@export_range(0.0, 120.0) var peak_delay_seconds: float = 18.0
## Заглушка длительности анимации. Все остальные боевые часы стоят.
@export_range(0.05, 5.0) var action_seconds: float = 0.45

@export_group("Удар рукой")
@export_range(1.0, 100.0) var hand_energy: float = 30.0
@export_range(0, 100) var hand_base_damage: int = 2
@export_range(0.0, 10.0) var hand_damage_per_str: float = 1.0

@export_group("Удар ногой")
@export_range(1.0, 100.0) var kick_energy: float = 60.0
@export_range(0, 100) var kick_base_damage: int = 5
@export_range(0.0, 10.0) var kick_damage_per_str: float = 2.0
@export_range(0, 100) var kick_stamina: int = 2


@export_group("Боевые эффекты")
## Захват запрещает удар ногой, но оставляет удар рукой и зарядку.
@export_range(0.1, 1.0) var immobilized_speed_multiplier: float = 0.7
## Каждое повторное оглушение в пределах памяти сокращается этим множителем.
@export_range(0.1, 1.0) var repeated_stun_multiplier: float = 0.5
@export_range(1.0, 120.0) var stun_memory_seconds: float = 20.0
## Защита от нового оглушения во время текущего и после его окончания.
@export_range(0.0, 10.0) var stun_immunity_seconds: float = 2.0


@export_group("Боевые меню")
@export_range(1.0, 100.0) var item_energy: float = 60.0
@export_range(1.0, 100.0) var skill_energy: float = 45.0
@export var unique_attacks: Array[PlayerCombatAttack] = [preload("res://Data/Combat/PlayerAttacks/groin_strike.tres")]

@export_group("Побег — проверка DEX")
@export_range(0, 30) var escape_base_difficulty: int = 8
@export_range(0, 10) var escape_group_penalty: int = 1
@export_range(0, 10) var escape_stun_relief: int = 2
@export_range(0, 100) var escape_low_lust_threshold: int = 10
@export_range(0, 10) var escape_low_lust_relief: int = 1
@export_range(0, 10) var escape_grapple_penalty: int = 2

@export_group("Отвлечение — проверка CHA")
@export_range(0, 30) var charm_base_difficulty: int = 6
@export_range(0, 10) var charm_stun_relief: int = 2
@export_range(0.0, 100.0) var charm_aggression_reduction: float = 20.0
@export_range(0.0, 100.0) var charm_irritation_reduction: float = 25.0
@export_range(0.0, 100.0) var charm_lust_reduction: float = 15.0
@export_range(0.0, 100.0) var charm_failure_irritation: float = 8.0


@export_group("Защита — режим")
## false — полностью отключить защиту (отладка/особые режимы).
@export var defense_enabled: bool = true
## false — вместо мини-игр одна автоматическая проверка DEX.
@export var use_defense_minigames: bool = true
@export var default_defense_kind: CombatDefense.Kind = CombatDefense.Kind.STOP_BAR
@export_range(0.0, 2.0) var defense_lead_in_seconds: float = 0.35
@export_range(0.0, 0.2) var defense_dex_per_point: float = 0.04
@export_range(0.0, 0.5) var defense_min_press_interval: float = 0.08
@export_range(1.0, 2.0) var defense_joint_difficulty: float = 1.15

@export_group("Защита — стоп-полоса")
@export_range(0.5, 10.0) var defense_stop_seconds: float = 3.5
@export_range(0.4, 10.0) var defense_stop_cycle_seconds: float = 2.4
@export_range(0.02, 0.5) var defense_perfect_width: float = 0.08
@export_range(0.02, 0.8) var defense_partial_width: float = 0.32

@export_group("Защита — частое нажатие")
@export_range(0.5, 10.0) var defense_mash_seconds: float = 3.0
@export_range(1, 100) var defense_mash_goal: int = 12
@export_range(0.1, 1.0) var defense_mash_partial_fraction: float = 0.6

@export_group("Защита — исходы")
@export_range(0.0, 1.0) var defense_perfect_damage: float = 0.0
@export_range(0.0, 1.0) var defense_perfect_effects: float = 0.0
@export_range(0.0, 1.0) var defense_partial_damage: float = 0.5
@export_range(0.0, 1.0) var defense_partial_effects: float = 0.5

@export_group("Защита — автоматическая проверка DEX")
@export_range(0, 30) var defense_auto_difficulty: int = 6
## Доля оставшегося шанса провала, превращённая в частичный успех.
@export_range(0.0, 1.0) var defense_auto_partial_fraction: float = 0.25
