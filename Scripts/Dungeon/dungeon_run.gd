class_name DungeonRun
extends Node
## Состояние и правила ОДНОГО забега по лабиринту: где стоит игрок, что
## происходит при заходе на клетку, какой случайный ивент выпадет, какой
## торговец встретился, куда ведёт "дыра в стене", когда предложить выход.
##
## Раньше всё это жило в DebugMazeView — временном отладочном рендере, —
## и при замене рендера на нормальный экран (картинка + миникарта) логику
## пришлось бы вырезать по живому. Теперь разделение такое:
##   DungeonGenerator — строит лабиринт и хранит тайлы (карта);
##   DungeonRun       — правила и состояние забега (этот файл);
##   любой вид        — только рисует и переводит ввод в вызовы try_move().
##
## DungeonRun ничего не знает ни про отрисовку, ни про конкретный DialogueBox:
## он лишь сообщает сигналами, что изменилось и какой диалог нужно показать.
## Кто именно покажет диалог — решает сцена/вид (см. DebugMazeView._ready).
##
## Всё состояние забега сбрасывается в _on_dungeon_generated(), то есть
## привязано к конкретной генерации, а не к времени жизни узла.

## Лабиринт сгенерирован, игрок поставлен на старт.
signal run_started
## Игрок переместился (обычный шаг или "дыра в стене").
signal player_moved(tile_pos: Vector2i)
## Изменилось содержимое клеток (событие погашено и т.п.) — повод перерисовать карту.
signal map_changed
## Шаг в стену — для вида (звук/тряска/сообщение), правилам он ничего не меняет.
signal move_blocked(direction: DungeonTypes.Direction)
## Нужно показать диалог. Аргументы — ровно как у DialogueBox.play().
signal dialogue_requested(resource: Resource, cue: String, extra_game_states: Array)

@export var generator: DungeonGenerator

## Заглушка проверки навыка для ивента "дыра в стене" — настоящего
## навыка/статов ещё нет, см. _on_random_event_tile(). Шанс УСПЕХА
## попытки протиснуться, а не шанс того, что сам ивент выпадет из пула
## (тот — обычный RandomEvent.weight, как у всех остальных).
@export_range(0.0, 1.0) var wall_hole_success_chance: float = 0.5

var _player_tile: Vector2i
var _is_running: bool = false

## Последний показанный случайный ивент этого забега — только для правила
## "не повторять только что показанный" (см. LocationData.pick_random_event).
var _last_random_event: RandomEvent = null

## Сколько раз каждое событие уже сработало в этом забеге — для
## RandomEvent.max_occurrences_per_run. Ключ — сам ресурс события, значение
## — счётчик. Живёт здесь, а не в LocationData: LocationData — общие данные
## локации, а счётчик — состояние конкретного забега.
var _random_event_occurrences: Dictionary = {}

## Торговец этого забега (см. _on_merchant_tile) — выбирается при первой встрече.
var _current_merchant: MerchantData = null

## Куда перенесёт "дыра в стене" при успехе — выставляется в
## _on_random_event_tile() и используется только в apply_wall_hole_success(),
## который вызывает мутация из wall_hole.dialogue (а не сразу: перемещать
## можно только ПОСЛЕ того, как диалог подтвердил и выбор "протиснуться",
## и успех попытки).
var _wall_hole_target: Vector2i


func _ready() -> void:
	if generator == null:
		push_error("DungeonRun: поле Generator не назначено в инспекторе!")
		return

	# Подписываемся ДО того, как генератор что-либо сгенерирует: генератор —
	# корень сцены, его _ready() (а значит и генерация) идёт ПОСЛЕ _ready()
	# дочерних узлов, включая этот.
	generator.dungeon_generated.connect(_on_dungeon_generated)


## Ушли со сцены лабиринта (возврат в хаб, смерть и т.п.) — снова в городе.
func _exit_tree() -> void:
	PlayerState.in_dungeon = false


# ====================== ПУБЛИЧНЫЙ ИНТЕРФЕЙС ДЛЯ ВИДА ======================

func is_running() -> bool:
	return _is_running


func get_player_tile() -> Vector2i:
	return _player_tile


## Попытка шага в абсолютном направлении. Возвращает true, если шаг сделан.
## Открыт ли сейчас диалог, DungeonRun не проверяет — это забота вида,
## который знает про DialogueBox (см. DebugMazeView._unhandled_input).
func try_move(direction: DungeonTypes.Direction) -> bool:
	if not _is_running:
		return false

	if not generator.can_move_from_tile(_player_tile, direction):
		print("🚧 Стена — туда не пройти")
		move_blocked.emit(direction)
		return false

	_player_tile = generator.get_neighbor_tile(_player_tile, direction)
	var tile := generator.get_tile(_player_tile)
	var event_type := tile.event_type if tile else DungeonTypes.EventType.EMPTY

	# Посещение и расход события — два разных действия. consume_event()
	# чистит одноразовые события в EMPTY, а QUEST/EXIT/MERCHANT не трогает:
	# EXIT должен остаться навсегда, к торговцу можно вернуться, а QUEST мы
	# гасим сами в _on_main_quest_tile(). Тип события запомнен выше, ДО
	# очистки, — по нему и решаем, что делать дальше.
	generator.mark_as_visited(_player_tile)
	generator.consume_event(_player_tile)
	player_moved.emit(_player_tile)
	map_changed.emit()

	match event_type:
		DungeonTypes.EventType.QUEST:
			_on_main_quest_tile(tile)
		DungeonTypes.EventType.SIDE_QUEST:
			_on_side_quest_tile(tile)
		DungeonTypes.EventType.RANDOM_EVENT:
			_on_random_event_tile()
		DungeonTypes.EventType.MERCHANT:
			_on_merchant_tile()
		DungeonTypes.EventType.EXIT:
			_start_return_choice("Станция метро. Вернуться в хаб?")

	return true


## Вызывается мутацией ($> run.apply_wall_hole_success()) из ветки успеха
## в wall_hole.dialogue — не раньше: переместить игрока можно только ПОСЛЕ
## того, как он И выбрал "протиснуться", И прошла проверка — а не сразу по
## заходу на тайл (игрок мог выбрать "пойти дальше" и остаться на месте).
## Обратно через ту же дыру дороги нет — стену мы нигде не трогаем, она
## остаётся обычной WALL: это часть замысла (игрок не должен знать,
## продвинулся он или нет).
func apply_wall_hole_success() -> void:
	_player_tile = _wall_hole_target
	generator.mark_as_visited(_player_tile)
	generator.consume_event(_player_tile)
	player_moved.emit(_player_tile)
	map_changed.emit()


# ====================== СТАРТ ЗАБЕГА ======================

func _on_dungeon_generated() -> void:
	_player_tile = generator.get_start_tile()
	generator.mark_as_visited(_player_tile)
	_last_random_event = null
	_random_event_occurrences.clear()
	_current_merchant = null
	_is_running = true
	PlayerState.in_dungeon = true
	TradeManager.on_run_started()  # торговцы лабиринта перебирают товар
	run_started.emit()


# ====================== РЕАКЦИИ НА КЛЕТКИ ======================

## Основной квест тухнет сразу по заходу на клетку (не по выбору игрока в
## диалоге) — иначе повторный заход на ту же клетку снова спрашивал бы
## "уйти/остаться", хотя квест уже засчитан.
func _on_main_quest_tile(tile: DungeonTile) -> void:
	tile.event_type = DungeonTypes.EventType.EMPTY
	map_changed.emit()

	# main_quest_data может быть пуст, если на LocationData ещё не назначили
	# MainQuestEvent (см. поле LocationData.main_quest) — тогда используем
	# id/имя самой локации как запасной вариант, чтобы журнал квестов не
	# получал пустой quest_id.
	var quest_id: String
	var quest_name: String
	if tile.main_quest_data:
		quest_id = tile.main_quest_data.quest_id
		quest_name = tile.main_quest_data.quest_name
	else:
		push_warning("У локации '%s' не назначен MainQuestEvent — использую location_id как запасной quest_id." % generator.location_data.location_name)
		quest_id = generator.location_data.location_id
		quest_name = generator.location_data.location_name

	QuestManager.complete_main_quest(quest_id, quest_name)
	_start_return_choice("Основной квест выполнен. Вернуться в хаб?")


## SIDE_QUEST тайл уже стёрт в EMPTY через consume_event() в try_move() —
## сам квест засчитывается всегда, а вот выбор "уйти/остаться" предлагаем
## только если основной квест уже найден (иначе игрок мог бы схлопнуть
## уровень сайд-квестом раньше, чем вообще наткнулся на основной).
func _on_side_quest_tile(tile: DungeonTile) -> void:
	var quest := tile.side_quest_data
	if quest:
		QuestManager.complete_side_quest(quest)
		# По умолчанию награда ждёт отдельного разговора-сдачи у NPC
		# (cue ~turn_in в .dialogue-файле квеста). instant_reward
		# пропускает этот шаг для квестов, которым сдача не нужна.
		if quest.instant_reward:
			QuestManager.grant_side_quest_reward(quest)

	if not QuestManager.is_main_quest_completed():
		return

	_start_return_choice("Побочный квест выполнен. Вернуться в хаб?")


## Тайл уже очищен в EMPTY через consume_event() (как и SIDE_QUEST),
## поэтому повторный заход ничего не вытянет снова. Какой именно ивент это
## будет, решаем здесь, а не при генерации — генератор решил только
## "тут RANDOM_EVENT", конкретный ресурс достаём в момент, когда игрок
## реально наступил на клетку.
##
## У некоторых событий есть спец-условие (RandomEvent.requires_wall_hole_geometry
## — нужна подходящая стена рядом, см. DungeonGenerator.try_get_secret_passage)
## и/или предел срабатываний за забег (RandomEvent.max_occurrences_per_run).
## Такие события отфильтровываются из розыгрыша заранее, если условие не
## выполнено — розыгрыш достаётся другому событию из пула, а не "выпадает
## и нечего показать".
func _on_random_event_tile() -> void:
	var location := generator.location_data
	if location == null:
		push_warning("DungeonRun: generator.location_data пуст — RANDOM_EVENT тайл ничего не даёт.")
		return

	var needs_passage_check := location.random_events.any(func(e): return e.requires_wall_hole_geometry)
	var passage: Dictionary = generator.try_get_secret_passage(_player_tile) if needs_passage_check else {}

	var chosen: RandomEvent = location.pick_random_event(
		_last_random_event,
		func(e):
			if e.requires_wall_hole_geometry and not passage.get("found", false):
				return false
			if e.max_occurrences_per_run > 0 and _random_event_occurrences.get(e, 0) >= e.max_occurrences_per_run:
				return false
			return true
	)
	if chosen == null:
		push_warning("У локации '%s' нет подходящих random_events прямо сейчас — RANDOM_EVENT тайл ничего не даёт." % location.location_name)
		return
	if chosen.dialogue == null:
		push_warning("У ивента '%s' не назначен dialogue — RANDOM_EVENT тайл ничего не даёт." % chosen.title)
		return

	_last_random_event = chosen
	_random_event_occurrences[chosen] = _random_event_occurrences.get(chosen, 0) + 1

	# Спец-условие несёт за собой и доп. контекст для диалога (куда
	# перенести, прошла ли заглушка-проверка навыка) — остальные события
	# играются как обычно, без этого.
	var extra_states: Array = []
	if chosen.requires_wall_hole_geometry:
		_wall_hole_target = passage["target_tile"]
		# Бросок — ДО открытия диалога, не внутри него: условия в .dialogue
		# резолвятся только против переданных extra_game_states/автозагрузок
		# по имени, глобальные функции (тот же randf()) им не видны.
		extra_states = [{"success": randf() < wall_hole_success_chance, "run": self}]

	dialogue_requested.emit(chosen.dialogue, "start", extra_states)


## Странствующий торговец. Какой именно — решаем при заходе (как у
## случайных ивентов), из LocationData.merchants. Тайл не стирается
## (см. DungeonGenerator.consume_event), поэтому конкретного торговца
## запоминаем на забег: иначе при возврате на тайл мог бы выпасть другой.
func _on_merchant_tile() -> void:
	if _current_merchant == null:
		var location := generator.location_data
		_current_merchant = location.pick_merchant() if location else null
	if _current_merchant == null:
		push_warning("У локации нет merchants — MERCHANT тайл ничего не даёт.")
		return
	if _current_merchant.dialogue == null:
		push_warning("У торговца '%s' не назначен dialogue." % _current_merchant.title)
		return
	dialogue_requested.emit(_current_merchant.dialogue, "start", [{"merchant": _current_merchant}])


## Диалог "уйти/остаться" собирается на лету через create_resource_from_text —
## prompt динамический (основной квест / сайд-квест / выход), поэтому
## отдельный .dialogue-файл под каждый вариант был бы избыточен.
func _start_return_choice(prompt: String) -> void:
	var source := "~ start\n%s\n- Остаться => END\n- Уйти\n\t$> GameManager.return_to_hub()\n\t=> END\n" % prompt
	dialogue_requested.emit(DialogueManager.create_resource_from_text(source), "start", [])
