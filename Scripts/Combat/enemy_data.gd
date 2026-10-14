class_name EnemyData
extends Resource
## Тип противника. Какие встречаются на локации и как часто — EncounterTable
## (LocationData.encounters_*). Ресурс общий: текущие HP/энергия — в CombatController.

@export var enemy_id: String = ""
@export var display_name: String = "Противник"

@export_group("Внешность")
## Фигура в полный рост — стоит на фоне лабиринта во время встречи (как
## персонаж в визуальной новелле). Это НЕ вставка события (pics).
@export var figure: Texture2D

@export_group("Бой — ядро")
@export_range(1, 10000) var max_hp: int = 28
@export_range(1, 1000) var attack_damage: int = 5
## Базовое время полной зарядки, до множителей.
@export_range(0.1, 120.0) var charge_seconds: float = 14.0
@export_range(0.01, 5.0) var speed_multiplier: float = 1.0

@export_group("ИИ — атаки")
## Пустой массив сохраняет простую атаку из этапа 1.
@export var attacks: Array[EnemyAttack] = []
## Можно ли выбрать этого врага помощником совместной атаки.
@export var can_assist_joint: bool = true
## Низкая похоть облегчает побег только у врагов с такой мотивацией.
@export var lust_affects_escape: bool = true

@export_group("ИИ — скрытые шкалы")
@export_range(0.0, 100.0) var base_aggression: float = 35.0
@export_range(0.0, 100.0) var base_irritation: float = 0.0
@export_range(0.0, 100.0) var base_lust: float = 10.0
@export_range(0.0, 100.0) var aggression_on_hit: float = 3.0
@export_range(0.0, 100.0) var irritation_on_hit: float = 12.0
@export_range(0.0, 10.0) var irritation_decay_per_second: float = 0.5
@export_range(0.0, 10.0) var passive_lust_per_second: float = 0.0
@export_range(0.0, 1.0) var lust_per_attractiveness: float = 0.02

@export_group("Награда")
## Опыт за победу. За группу — сумма по всем противникам.
@export var xp_reward: int = 20

@export_group("Сцены")
## Сцена поражения от этого противника (в группе — от первого).
## Пусто — общая сцена локации (LocationData.defeat_dialogue).
@export var defeat_dialogue: DialogueResource
## Разговор, если игрок заметил первым и решил заговорить. Пусто — общий
## Dialogue/enemy_talk_default.dialogue. В диалог передаются
## {"enc": Encounter, "run": DungeonRun}; концовка — do enc.avoid(...)
## или do enc.fight() (см. Encounter).
@export var talk_dialogue: DialogueResource
@export var talk_start: String = "start"

## Следующие этапы: дополнительные реакции и добыча.


@export_group("Защита игрока")
## Значение по умолчанию для атак с AUTO. Теги grapple/joint выбирают MASH;
## явная настройка атаки имеет приоритет. NONE отключает защиту по умолчанию.
@export var defense_kind: CombatDefense.Kind = CombatDefense.Kind.AUTO
@export_range(0.25, 4.0) var defense_difficulty: float = 1.0
