class_name HubUI
extends Control
## Слушает HubManager, перерисовывает экран. Сам диалог больше не ведёт —
## это теперь дело общего DialogueBox (res://Scripts/UI/dialogue_box.gd,
## та же нода, что и в сцене лабиринта, см. DebugMazeView) — HubUI только
## просит его сыграть нужный .dialogue-ресурс.
##
## ChoicesContainer (навигация по хабу) и NpcContainer (кто есть на
## локации) живут отдельно и видны всегда, независимо от диалога.

@export var hub_manager: HubManager

# "%Имя" — это Scene Unique Name. В редакторе: ПКМ по узлу -> "Access as Unique Name".
@onready var _background_rect: TextureRect = %Background
@onready var _choices_container: VBoxContainer = %ChoicesContainer
@onready var _npc_container: VBoxContainer = %NpcContainer
@onready var _dialogue_box: DialogueBox = %DialogueBox

## Текущий разговор с NPC (TALK_FIRST) — ждём его конца, чтобы открыть квест.
var _pending_talk: NPCTalk = null

func _ready() -> void:
	if hub_manager == null:
		push_error("HubUI: поле Hub Manager не назначено в инспекторе!")
		return

	hub_manager.location_changed.connect(_on_location_changed)
	_dialogue_box.finished.connect(_on_dialogue_finished)

	# Стартовую локацию запускаем отсюда, а не из HubManager._ready() —
	# так гарантированно подписываемся на сигналы ДО первой эмиссии.
	hub_manager.go_to(hub_manager.start_location_id)


## Цифровой выбор для навигации по хабу — тот же принцип, что в DialogueBox
## (нажатие N эмулирует клик по N-й кнопке), но отдельно: ChoicesContainer —
## это не диалог, DialogueBox про него ничего не знает и не должен.
## Пока диалог открыт — цифры разбирает он (см. DialogueBox._unhandled_input),
## здесь просто выходим, чтобы не было двойной реакции на одну и ту же клавишу.
func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_box.is_active() or not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var index: int = event.keycode - KEY_1
	if index < 0 or index >= _choices_container.get_child_count():
		return

	(_choices_container.get_child(index) as Button).pressed.emit()


func _on_location_changed(location: HubLocation) -> void:
	_background_rect.texture = location.background
	_rebuild_choices(location.choices)
	_rebuild_npcs(location.npcs)

	# Если диалог с прошлой локации не был дочитан до конца — закрываем
	# его принудительно, иначе панель "уедет" вместе с новой сценой.
	_dialogue_box.cancel()
	_pending_talk = null

	# intro_text — переходный рудимент, теперь просто открывает диалог
	# через create_resource_from_text вместо собственной логики показа.
	if not location.intro_text.is_empty():
		_dialogue_box.play(DialogueManager.create_resource_from_text("~ start\n%s" % location.intro_text))


## ====================== Навигация по хабу ======================

func _rebuild_choices(choices: Array[HubChoice]) -> void:
	for child in _choices_container.get_children():
		child.queue_free()

	for i in range(choices.size()):
		var choice: HubChoice = choices[i]
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE  # см. комментарий в dialogue_box.gd — та же причина
		button.text = "%d. %s" % [i + 1, choice.label]
		button.pressed.connect(_on_choice_pressed.bind(choice))
		_choices_container.add_child(button)


func _on_choice_pressed(choice: HubChoice) -> void:
	if choice.enters_dangerous_zone:
		if choice.dungeon_location == null:
			push_error("HubChoice '%s': enters_dangerous_zone включён, но dungeon_location пуст!" % choice.label)
			return
		GameManager.enter_dungeon(choice.dungeon_location, choice.dungeon_difficulty)
	else:
		hub_manager.go_to(choice.target_location_id)


## ====================== NPC (отдельно от навигации хаба) ======================

func _rebuild_npcs(npcs: Array[NPCData]) -> void:
	for child in _npc_container.get_children():
		child.queue_free()

	for npc in npcs:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE  # см. комментарий в dialogue_box.gd — та же причина
		button.text = npc.display_name
		button.pressed.connect(_on_npc_pressed.bind(npc))
		_npc_container.add_child(button)


func _on_npc_pressed(npc: NPCData) -> void:
	_pending_talk = null
	var quest := npc.offered_quest
	var relevant := quest != null and _is_quest_relevant(quest)

	if relevant and (npc.dialogue == null or npc.quest_mode == NPCData.QuestMode.QUEST_FIRST):
		_start_side_quest_offer(quest, npc.display_name)
	elif npc.dialogue != null:
		var talk := NPCTalk.new(npc, relevant)
		_pending_talk = talk
		_dialogue_box.play(npc.dialogue, npc.start_cue, [{"npc": npc, "merchant": npc.merchant, "talk": talk}])
	elif quest != null:
		_start_side_quest_offer(quest, npc.display_name)  # общие заглушки "закрыто / сдано"
	else:
		_say_generic(npc.display_name, "...")


## Разговор с NPC дочитан: если игрок выбрал пункт про задание
## (talk.ask_about_quest()) — открываем квестовый диалог.
func _on_dialogue_finished() -> void:
	var talk := _pending_talk
	_pending_talk = null
	if talk != null and talk.quest_requested:
		_start_side_quest_offer(talk.quest, talk.npc.display_name)


## Квест сейчас "про что поговорить": уже открыт и ещё не сдан. Иначе NPC
## с собственным dialogue просто разговаривает о своём.
func _is_quest_relevant(quest: SideQuestEvent) -> bool:
	return QuestManager.are_prerequisites_completed(quest.prerequisite_quest_ids) \
		and not QuestManager.is_side_quest_rewarded(quest.quest_id)


## Открывает диалог с NPC-квестодателем. Сам текст — в собственном
## .dialogue-файле квеста (SideQuestEvent.dialogue, у каждого квеста свой),
## а вот КАКУЮ секцию открыть, решаем здесь, в коде: это чистая механика
## состояния квеста, одинаковая для всех, и дублировать её в каждом
## диалоговом файле значило бы чинить одну и ту же логику в N местах.
## Порядок проверок тот же, что был в старом общем side_quest_offer.dialogue.
## Заглушки для "ещё закрыто / уже сдано / уже взято" — намеренно общие
## однострочные: нарративной ценности в них мало, писать под каждый квест
## отдельно пока не нужно. Содержательные моменты — предложение и сдача —
## целиком авторские, в файле квеста.
func _start_side_quest_offer(quest: SideQuestEvent, speaker_name: String) -> void:
	if not QuestManager.are_prerequisites_completed(quest.prerequisite_quest_ids):
		_say_generic(speaker_name, "[TODO: заглушка — задания пока нет]")
		return
	if QuestManager.is_side_quest_rewarded(quest.quest_id):
		_say_generic(speaker_name, "[TODO: реплика после сдачи квеста — новых дел пока нет]")
		return

	if quest.dialogue == null:
		push_warning("У квеста '%s' не назначен dialogue — диалог с NPC не откроется." % quest.quest_id)
		_say_generic(speaker_name, "...")
		return

	var extra_states: Array = [{"quest": quest}]
	if QuestManager.is_quest_completed(quest.quest_id):
		_dialogue_box.play(quest.dialogue, "turn_in", extra_states)
	elif QuestManager.is_side_quest_active(quest):
		_say_generic(speaker_name, "Ты уже взял это задание. Пока не выполнишь — новых у меня нет.")
	elif QuestManager.has_active_side_quest(quest.location_id, quest.difficulty):
		# Правило "один активный сайд-квест на локацию и сложность": слот
		# занят ДРУГИМ квестом — не предлагаем, иначе игрок согласился бы,
		# а activate_side_quest() молча отказал бы.
		_say_generic(speaker_name, "[TODO: заглушка — у тебя уже есть задание в этом районе такой сложности]")
	else:
		_dialogue_box.play(quest.dialogue, "start", extra_states)


func _say_generic(speaker_name: String, text: String) -> void:
	_dialogue_box.play(DialogueManager.create_resource_from_text("~ start\n%s: %s" % [speaker_name, text]))
