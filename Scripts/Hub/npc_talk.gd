class_name NPCTalk
extends RefCounted
## Контекст одного разговора с NPC — передаётся в его dialogue как "talk".
## Нужен, чтобы обычный разговор мог предложить пункт про задание
## (NPCData.quest_mode = TALK_FIRST). В .dialogue:
##
##   - Насчёт задания... [if talk.has_quest_topic() and not talk.can_turn_in_quest() /] => quest
##   - Я сделал, что ты просил. [if talk.can_turn_in_quest() /] => quest
##   ...
##   ~ quest
##   do talk.ask_about_quest()
##   => END
##
## Сам квестовый диалог (SideQuestEvent.dialogue) HubUI откроет сразу после
## того, как этот разговор закончится.

var npc: NPCData
var quest: SideQuestEvent
var quest_requested: bool = false
var _has_topic: bool = false


func _init(p_npc: NPCData, has_topic: bool) -> void:
	npc = p_npc
	quest = p_npc.offered_quest
	_has_topic = has_topic and quest != null


## Есть ли о чём говорить по заданию: квест открыт и ещё не сдан
## (не взят / взят / выполнен — всё равно).
func has_quest_topic() -> bool:
	return _has_topic


## Задание взято и ещё не выполнено.
func is_quest_taken() -> bool:
	return _has_topic and QuestManager.is_side_quest_active(quest) \
		and not QuestManager.is_quest_completed(quest.quest_id)


## Задание выполнено — можно сдавать.
func can_turn_in_quest() -> bool:
	return _has_topic and QuestManager.is_quest_completed(quest.quest_id)


## Игрок выбрал пункт про задание — после разговора откроется квест.
func ask_about_quest() -> void:
	quest_requested = true
