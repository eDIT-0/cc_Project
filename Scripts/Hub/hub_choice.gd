class_name HubChoice
extends Resource
## Один пункт выбора в диалоговом окне хаба (см. макет: "1. Dialouge or choice option")
##
## Только навигация по хабу: два взаимоисключающих варианта того, что
## делает выбор — обычный переход (target_location_id) или вход в опасную
## зону (enters_dangerous_zone + dungeon_location). Выдача сайд-квестов
## сюда НЕ входит — это отдельная система, завязанная на NPCData/NPC в
## хабе (см. Scripts/Hub/npc_data.gd), а не на пункты навигационного меню.
##
## Пока нет карты города — сложность выбирается тут же вручную. Как только
## появится QuestManager.resolve_difficulty_for_location() в рабочем виде —
## dungeon_difficulty на конкретных "боевых" точках входа станет не нужен.

@export var label: String = "Вариант"

@export_group("Обычный переход по хабу")
@export var target_location_id: String = ""

@export_group("Вход в опасную зону")
@export var enters_dangerous_zone: bool = false
@export var dungeon_location: LocationData
@export var dungeon_difficulty: Difficulty.Level = Difficulty.Level.NORMAL
