class_name EnemyAttack
extends Resource
## Описание атаки. Ресурс общий и неизменяемый в бою: кулдауны и намерения
## принадлежат отдельным экземплярам EnemyBrain/CombatController.

@export var attack_id: String = "basic"
@export var display_name: String = "Простая атака"
@export var tags: PackedStringArray = PackedStringArray(["strike"])

@export_group("Намерение — внешний вид")
## Необязательно: без текстуры экран выбирает символ по тегам атаки.
@export var intent_icon: Texture2D

@export_group("Результат")
## -1 — взять attack_damage из EnemyData; 0 — атака без урона HP.
@export_range(-1, 1000) var damage: int = -1
@export_range(0, 100) var arousal: int = 0
@export_range(0.0, 30.0) var stun_seconds: float = 0.0
## Старое имя сохранено для .tres: 0 — нет захвата, >0 — постоянный захват.
## Это больше не длительность; снимается освобождением/поражением владельца.
@export_range(0.0, 30.0) var immobilize_seconds: float = 0.0
@export_range(0.0, 120.0) var cooldown_seconds: float = 0.0

@export_group("Выбор ИИ")
@export_range(0.0, 100.0) var base_weight: float = 5.0
@export_range(-1.0, 1.0) var aggression_weight: float = 0.0
@export_range(-1.0, 1.0) var irritation_weight: float = 0.0
@export_range(-1.0, 1.0) var lust_weight: float = 0.0
@export_range(0.0, 100.0) var min_aggression: float = 0.0
@export_range(0.0, 100.0) var min_irritation: float = 0.0
@export_range(0.0, 100.0) var min_lust: float = 0.0
@export var requires_immobilized: bool = false

@export_group("Совместная атака")
@export var joint: bool = false
## Лидер тратит 100%, союзник — это количество. Энергия резервируется
## намерением, но списывается только при исполнении.
@export_range(1.0, 100.0) var partner_energy: float = 60.0


@export_group("Защита игрока")
## AUTO у атаки: grapple/joint -> MASH, иначе настройка врага/CombatRules.
## NONE: эту атаку нельзя защитить мини-игрой или автоматическим броском.
@export var defense_kind: CombatDefense.Kind = CombatDefense.Kind.AUTO
@export_range(0.25, 4.0) var defense_difficulty: float = 1.0
