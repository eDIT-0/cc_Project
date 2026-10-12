class_name HubChoice
extends Resource
## Один пункт выбора в диалоговом окне хаба (см. макет: "1. Dialouge or choice option")
##
## Четыре взаимоисключающих варианта того, что делает выбор (проверяются в
## этом порядке): открыть экран (action_screen — шкаф-хранилище),
## действие-диалог с предметом обстановки (action_dialogue — кровать,
## терминал и т.п.), вход в опасную зону (enters_dangerous_zone +
## dungeon_location) или обычный переход (target_location_id).
##
## Переход на закрытую сейчас локацию (HubLocation.open_phases) не прячется:
## кнопка видна, но неактивна, с припиской "[HubLocation.closed_text]". Выдача сайд-квестов
## сюда НЕ входит — это отдельная система, завязанная на NPCData/NPC в
## хабе (см. Scripts/Hub/npc_data.gd), а не на пункты навигационного меню.
##
## Пока нет карты города — сложность выбирается тут же вручную. Как только
## появится QuestManager.resolve_difficulty_for_location() в рабочем виде —
## dungeon_difficulty на конкретных "боевых" точках входа станет не нужен.

@export var label: String = "Вариант"

enum ScreenAction { NONE, STASH }

@export_group("Действие (экран)")
## Сразу открыть экран, без диалога. STASH — хранилище в квартире.
@export var action_screen: ScreenAction = ScreenAction.NONE

@export_group("Действие (диалог)")
## Взаимодействие с обстановкой без перехода: открыть этот диалог.
## (Не NPC — люди живут в NPCData.) Пример: кровать -> bed.dialogue.
@export var action_dialogue: DialogueResource
## С какой секции начать. НЕ называть "*dialogue_cue*" — см. npc_data.gd.
@export var action_start: String = "start"

@export_group("Обычный переход по хабу")
@export var target_location_id: String = ""

@export_group("Вход в опасную зону")
@export var enters_dangerous_zone: bool = false
@export var dungeon_location: LocationData
@export var dungeon_difficulty: Difficulty.Level = Difficulty.Level.NORMAL
