class_name SideQuestEvent
extends Resource

@export_group("Основная информация")
@export var quest_id: String = ""       # side-slums-normal-01
@export var quest_name: String = ""     # для журнала завершённых квестов и будущего UI
@export var location_id: String = ""    # к какой локации привязан
@export var difficulty: Difficulty.Level = Difficulty.Level.NORMAL

@export_group("Нарратив")
## Собственный .dialogue-файл этого квеста — у каждого квеста свой, а не
## один общий на всех квестодателей (как у RandomEvent.dialogue). Обязательные
## секции: ~ start (предложение квеста; в ветке согласия — мутация
## $> QuestManager.activate_side_quest(quest)) и ~ turn_in (сдача; внутри —
## $> QuestManager.grant_side_quest_reward(quest)). Остальное (подробности,
## повторы, ветки) — на усмотрение автора диалога. В диалог передаётся
## extra_game_state {"quest": <этот ресурс>}. КОГДА какую секцию открыть
## (предпосылки не выполнены / награда уже выдана / квест уже взят) решает
## код, а не сам файл — см. HubUI._start_side_quest_offer: это чистая
## механика, одинаковая для всех квестов, дублировать её в каждом файле незачем.
@export var dialogue: DialogueResource

@export_group("Событие")
## Внутренняя заметка для дизайнера — игроку больше нигде не показывается
## (раньше подставлялась в общий диалог через {{quest.description}}).
@export_multiline var description: String = ""

@export_group("Гибкость этапов")
## Если выключено — квест можно завершить в лабиринте (тайл появится и
## сработает), даже если игрок никогда не брал его у NPC через диалог.
## По умолчанию включено — сохраняет текущее поведение для уже настроенных
## квестов (взять -> пройти -> сдать).
@export var requires_acceptance: bool = true
## Если включено — награда выдаётся сразу при завершении в лабиринте
## (см. DungeonRun._on_side_quest_tile), без отдельного разговора-сдачи
## у NPC. По умолчанию выключено — награда только через диалог сдачи.
@export var instant_reward: bool = false

@export_group("Предпосылки")
## Список quest_id, которые должны быть завершены (логика "И" — нужны ВСЕ),
## прежде чем этот квест станет доступен у NPC. Пусто = без предпосылок.
## Работает и с основными, и с сайд-квестами одинаково — оба типа пишутся
## в один журнал QuestManager._completed_quests, гейту всё равно, какой
## это был квест (см. QuestManager.is_quest_completed).
@export var prerequisite_quest_ids: Array[String] = []
