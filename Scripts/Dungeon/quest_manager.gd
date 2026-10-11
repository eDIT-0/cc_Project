extends Node
## Автозагружаемый синглтон (Project Settings -> Autoload -> имя "QuestManager").

## Взятые, но ещё не завершённые сайд-квесты — ТОЛЬКО quest_id, а не сами
## ресурсы SideQuestEvent, разложенные по "слотам" (локация, сложность):
##   { location_id (String): { difficulty (int): quest_id (String) } }
## Правило дизайна "на одну локацию и сложность — не больше одного активного
## сайд-квеста" так выполняется самой структурой: в слоте просто нет места
## для второго. Хранение строками/числами — задел под будущие сохранения:
## состояние не зависит от путей к .tres и от правок ресурса после сохранения.
var _active_side_quests: Dictionary = {}

## Пройден ли основной квест ТЕКУЩЕГО забега (сбрасывается в prepare_run()).
## Отдельно от журнала ниже — это transient-флаг только для гейта "можно ли
## предлагать выход при сайд-квесте" (см. DungeonRun._on_side_quest_tile),
## а журнал ниже — постоянная история на всю игру.
var _main_quest_completed: bool = false

## Журнал завершённых квестов (и основных, и побочных) — id -> название.
## Постоянный на всю игру, НЕ сбрасывается между забегами (в отличие от
## _main_quest_completed выше). Нужен, чтобы будущие квесты могли проверять
## "пройден ли квест X" и строить цепочки друг на друге.
var _completed_quests: Dictionary = {}  # quest_id (String) -> quest_name (String)

## Награда за сайд-квест выдана (id -> true). Отдельно от _completed_quests
## намеренно: "пройден тайл в лабиринте" и "забрал награду у квестодателя" —
## разные моменты, между ними игрок может ещё не успеть дойти обратно до NPC.
## Диалог сдачи (см. side_quest_offer.dialogue, cue ~turn_in) проверяет
## именно это поле, а не _completed_quests, чтобы не повторяться при
## следующих разговорах с тем же NPC.
var _rewarded_side_quests: Dictionary = {}  # quest_id (String) -> true

## Активирует сайд-квест (вызывается из диалога квестодателя при согласии).
## Если слот (локация, сложность) уже занят — квест не берётся. Хаб не
## должен до этого доводить (см. HubUI._start_side_quest_offer), так что
## срабатывание варнинга здесь — признак ошибки в вызывающем коде.
func activate_side_quest(quest: SideQuestEvent) -> void:
	if quest == null:
		return
	if quest.quest_id.is_empty():
		push_warning("QuestManager: у сайд-квеста пустой quest_id — активировать нельзя.")
		return

	var occupied := get_active_side_quest_id(quest.location_id, quest.difficulty)
	if not occupied.is_empty():
		push_warning("Слот %s / %s уже занят квестом %s — %s не взят." % [
			quest.location_id, Difficulty.Level.keys()[quest.difficulty], occupied, quest.quest_id
		])
		return

	if not _active_side_quests.has(quest.location_id):
		_active_side_quests[quest.location_id] = {}
	_active_side_quests[quest.location_id][int(quest.difficulty)] = quest.quest_id
	print("Сайд-квест активирован: %s" % quest.quest_id)

## id активного сайд-квеста в слоте (локация, сложность) или "" если слот пуст.
func get_active_side_quest_id(location_id: String, difficulty: Difficulty.Level) -> String:
	var by_difficulty: Dictionary = _active_side_quests.get(location_id, {})
	return by_difficulty.get(int(difficulty), "")

## Занят ли слот (локация, сложность) ЛЮБЫМ активным сайд-квестом —
## для правила "один на слот" (хаб: можно ли предлагать новый квест).
func has_active_side_quest(location_id: String, difficulty: Difficulty.Level) -> bool:
	return not get_active_side_quest_id(location_id, difficulty).is_empty()

## Взят ли именно ЭТОТ квест — для "уже взял это задание" в хабе и для
## генератора (requires_acceptance: тайл появляется, только если взят он сам).
func is_side_quest_active(quest: SideQuestEvent) -> bool:
	if quest == null or quest.quest_id.is_empty():
		return false
	return get_active_side_quest_id(quest.location_id, quest.difficulty) == quest.quest_id


## Определяет, с какой сложностью игрок попадёт в район, если выберет его
## на карте города (терминал станции метро вызовет это перед prepare_run()).
##
## TODO: сейчас это ЗАГЛУШКА. Нужная логика:
##   1. Если у location_id есть активный сайд-квест (любой сложности) —
##      использовать сложность ИМЕННО этого квеста (реализовано: это просто
##      занятый слот этой локации).
##   2. Если квеста нет — случайный уровень с весом по уровню игрока,
##      закешированный и обновляемый раз в игровую неделю.
## Пункт 2 сознательно не реализован: нет ни системы уровня игрока,
## ни игрового календаря. Возвращаемся к этому, когда они появятся.
func resolve_difficulty_for_location(location_id: String) -> Difficulty.Level:
	var by_difficulty: Dictionary = _active_side_quests.get(location_id, {})
	for difficulty in by_difficulty:
		return difficulty as Difficulty.Level

	push_warning("QuestManager.resolve_difficulty_for_location: недостроенная логика — возвращён NORMAL по умолчанию для '%s'." % location_id)
	return Difficulty.Level.NORMAL

## Завершает сайд-квест (вызывается после прохождения события). Не требует,
## чтобы квест был активен — requires_acceptance == false квесты могут
## завершиться, даже если игрок никогда не брал их у NPC (тогда слот
## просто не трогаем).
func complete_side_quest(quest: SideQuestEvent) -> void:
	if quest == null:
		return

	# Освобождаем слот, только если в нём лежит именно этот квест.
	if is_side_quest_active(quest):
		var by_difficulty: Dictionary = _active_side_quests[quest.location_id]
		by_difficulty.erase(int(quest.difficulty))
		if by_difficulty.is_empty():
			_active_side_quests.erase(quest.location_id)
	_log_quest_completed(quest.quest_id, quest.quest_name)
	print("Сайд-квест завершён: %s" % quest.quest_id)

## Для дебага
func get_active_side_quest_ids() -> Array[String]:
	var ids: Array[String] = []
	for location_id in _active_side_quests:
		var by_difficulty: Dictionary = _active_side_quests[location_id]
		for difficulty in by_difficulty:
			ids.append(by_difficulty[difficulty])
	return ids

## Отмечает основной квест текущего забега пройденным (вызывается при
## заходе на тайл EventType.QUEST в лабиринте). quest_id/quest_name приходят
## из MainQuestEvent, назначенного на LocationData — см. DungeonRun.
## xp_reward выдаётся только за ПЕРВОЕ прохождение (по журналу) — иначе
## опыт фармился бы повторными забегами в ту же локацию.
func complete_main_quest(quest_id: String, quest_name: String, xp_reward: int = 0) -> void:
	_main_quest_completed = true
	var first_time := not is_quest_completed(quest_id)
	_log_quest_completed(quest_id, quest_name)
	if first_time:
		PlayerState.stats.add_xp(xp_reward)
	print("Основной квест завершён: %s" % quest_id)

func is_main_quest_completed() -> bool:
	return _main_quest_completed

## Сбрасывает флаг основного квеста — вызывать при старте нового забега
## (см. GameManager.prepare_run()), иначе завершение в одном заходе в
## лабиринт будет неправильно засчитываться и во всех последующих.
## Журнал завершённых квестов (_completed_quests) этим НЕ затрагивается —
## он про историю на всю игру, а не про текущий забег.
func reset_main_quest_completion() -> void:
	_main_quest_completed = false


# ====================== ЖУРНАЛ ЗАВЕРШЁННЫХ КВЕСТОВ ======================

func _log_quest_completed(quest_id: String, quest_name: String) -> void:
	if quest_id.is_empty():
		push_warning("QuestManager: попытка записать в журнал квест без quest_id — пропущено.")
		return
	_completed_quests[quest_id] = quest_name

## Пройден ли когда-либо (за всю игру) квест с таким id — основа для
## будущих цепочек ("квест B доступен только если пройден квест A").
func is_quest_completed(quest_id: String) -> bool:
	return _completed_quests.has(quest_id)

## Для дебага/будущего UI журнала
func get_completed_quests() -> Dictionary:
	return _completed_quests.duplicate()

## Проверка предпосылок (SideQuestEvent.prerequisite_quest_ids) — логика "И":
## true, только если ВСЕ id из списка есть в журнале. Пустой список считается
## выполненным (нет предпосылок — нечего проверять). Не важно, main это был
## квест или сайд — журнал общий, is_quest_completed не различает их.
func are_prerequisites_completed(quest_ids: Array) -> bool:
	for id in quest_ids:
		if not is_quest_completed(id):
			return false
	return true


# ====================== НАГРАДА ЗА СДАЧУ СAЙД-КВЕСТА ======================

## Вызывается из диалога сдачи квеста ($> QuestManager.grant_side_quest_reward(quest)
## в side_quest_offer.dialogue, cue ~turn_in). Пока НОМИНАЛЬНО — просто лог,
## без реального предмета/денег: инвентаря и экономики ещё нет (сознательно
## отложены, см. обсуждение квестового цикла). Когда появятся — это
## единственное место, которое допишем, сам диалог трогать не придётся.
func grant_side_quest_reward(quest: SideQuestEvent) -> void:
	if quest == null:
		return
	if _rewarded_side_quests.has(quest.quest_id):
		return  # дважды не награждаем
	_rewarded_side_quests[quest.quest_id] = true
	PlayerState.stats.add_xp(quest.xp_reward)
	print("Награда за квест: %s (+%d опыта; предметы/деньги — позже)" % [quest.quest_id, quest.xp_reward])

func is_side_quest_rewarded(quest_id: String) -> bool:
	return _rewarded_side_quests.has(quest_id)
