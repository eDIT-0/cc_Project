class_name NPCData
extends Resource
## Персонаж, которого можно встретить в хабе. Намеренно НИКАК не связан с
## HubChoice/навигацией — присутствие NPC на локации будет позже управляться
## отдельной логикой (расписание, уход/приход, способ получения квеста №2
## из четырёх обсуждённых), и эта логика не должна лезть в HubChoice ради
## этого. Пока присутствие статично: просто лежит в HubLocation.npcs.
##
## Что происходит по клику (HubUI._on_npc_pressed), если квест актуален
## (открыт и ещё не сдан):
##   QUEST_FIRST — сразу квестовый диалог (SideQuestEvent.dialogue);
##   TALK_FIRST  — обычный dialogue, а задание — один из пунктов в нём
##                 (см. NPCTalk: talk.has_quest_topic(), talk.ask_about_quest()).
## Квест не актуален -> обычный dialogue. Нет dialogue -> квест / заглушки / "...".

enum QuestMode { QUEST_FIRST, TALK_FIRST }

@export var npc_id: String = ""
@export var display_name: String = ""
@export var portrait: Texture2D

@export_group("Диалог")
## Обычный разговор. В диалог передаются {"npc": этот ресурс,
## "merchant": merchant, "talk": NPCTalk} — можно писать {{npc.display_name}},
## do TradeManager.open(merchant) и пункт про задание через talk.
@export var dialogue: DialogueResource
## С какой секции начинать dialogue.
## НЕ называть "dialogue_cue": Dialogue Manager вешает на такие имена свой
## редактор, рассчитанный только на ноды, и инспектор ресурса падает.
@export var start_cue: String = "start"
## Квест, который NPC предлагает. Когда появится что-то сложнее одного
## сценария — вырастет в отдельный ресурс диалогового дерева.
@export var offered_quest: SideQuestEvent
## Как подавать квест, если есть и dialogue, и актуальный квест.
## Без dialogue всегда как QUEST_FIRST.
@export var quest_mode: QuestMode = QuestMode.TALK_FIRST

@export_group("Торговля")
## Если NPC — продавец. Сама торговля открывается из его dialogue.
@export var merchant: MerchantData
