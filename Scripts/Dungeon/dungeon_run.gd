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

## Фразы находки по умолчанию (если у локации нет своих loot_find_texts).
const DEFAULT_FIND_TEXTS: Array[String] = [
	"Среди мусора что-то поблёскивает.",
	"В углу валяется брошенная кем-то сумка.",
	"Под обломками обнаруживается тайник.",
]

## Сложность проверки ЛОВКОСТИ для ивента "дыра в стене" (см.
## CharacterStats.get_check_chance: DEX == сложности -> 50%). Сам бросок —
## в wall_hole.dialogue (PlayerState.check), сюда передаётся как "difficulty".
@export_range(0, 20) var wall_hole_difficulty: int = 6
## Урон, если застрял.
@export_range(0, 100) var wall_hole_fail_damage: int = 5

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

# --- добыча ---
## Последний бросок добычи (roll_loot) — ждёт collect_loot().
var _pending_loot: Dictionary = {}

# --- поражение ---
## Открыт ли сейчас диалог, который мы попросили показать (вид сообщает о
## конце через on_dialogue_finished). Поражение посреди диалога ждёт его конца.
var _dialogue_open: bool = false
var _defeat_pending: bool = false
var _defeat_pending_scene: DialogueResource = null
var _defeat_in_progress: bool = false


func _ready() -> void:
	if generator == null:
		push_error("DungeonRun: поле Generator не назначено в инспекторе!")
		return

	# Подписываемся ДО того, как генератор что-либо сгенерирует: генератор —
	# корень сцены, его _ready() (а значит и генерация) идёт ПОСЛЕ _ready()
	# дочерних узлов, включая этот.
	generator.dungeon_generated.connect(_on_dungeon_generated)
	dialogue_requested.connect(func(_r, _c, _s): _dialogue_open = true)
	PlayerState.stats.died.connect(_on_player_died)


## Ушли со сцены лабиринта (возврат в хаб, смерть и т.п.) — снова в городе.
func _exit_tree() -> void:
	PlayerState.in_dungeon = false
	if PlayerState.stats.died.is_connected(_on_player_died):
		PlayerState.stats.died.disconnect(_on_player_died)


## Вид сообщает: диалог дочитан (DialogueBox.finished). Тут продолжается
## отложенное поражение.
func on_dialogue_finished() -> void:
	_dialogue_open = false
	if _defeat_in_progress:
		_finish_defeat()
	elif _defeat_pending:
		_defeat_pending = false
		_start_defeat(_defeat_pending_scene)


# ====================== ПОРАЖЕНИЕ ======================
## Смерти нет: поражение — часть игры. Сцена поражения -> штрафы
## (PlayerState.apply_defeat) -> игрока "выбрасывает" на случайную пустую
## комнату. Забег продолжается: выход на месте, выполненные квесты засчитаны.

## Запустить поражение. scene — своя сцена (бой: сцена конкретного врага);
## null — общая сцена локации (LocationData.defeat_dialogue). Если сейчас
## открыт диалог — начнётся, когда он закончится.
func trigger_defeat(scene: DialogueResource = null) -> void:
	if not _is_running or _defeat_in_progress or _defeat_pending:
		return
	if _dialogue_open:
		_defeat_pending = true
		_defeat_pending_scene = scene
		return
	_start_defeat(scene)


func is_defeat_in_progress() -> bool:
	return _defeat_in_progress or _defeat_pending


## Здоровье на нуле вне боя (события). Бой позже будет звать
## trigger_defeat(сцена_врага) сам.
func _on_player_died() -> void:
	trigger_defeat()


func _start_defeat(scene: DialogueResource) -> void:
	_defeat_in_progress = true
	if scene == null and generator.location_data != null:
		scene = generator.location_data.defeat_dialogue
	if scene == null:
		push_warning("DungeonRun: у локации нет defeat_dialogue — поражение без сцены.")
		_finish_defeat()
		return
	dialogue_requested.emit(scene, "start", [{"run": self}])


func _finish_defeat() -> void:
	_defeat_in_progress = false
	PlayerState.apply_defeat()

	var candidates := generator.get_empty_room_tiles()
	candidates.erase(_player_tile)
	if candidates.is_empty():
		push_warning("DungeonRun: нет пустых комнат для переноса — остаёмся на месте.")
	else:
		_player_tile = candidates[randi() % candidates.size()]
		generator.mark_as_visited(_player_tile)
	print("☠ Поражение: очнулся в %s." % str(_player_tile))
	player_moved.emit(_player_tile)
	map_changed.emit()


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
	PlayerState.on_maze_step()  # -выносливость, +10 игровых минут
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
		DungeonTypes.EventType.REWARD:
			_on_reward_tile()
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
	PlayerState.on_maze_step()  # протиснуться — тоже шаг
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
	var xp_reward := 0
	if tile.main_quest_data:
		quest_id = tile.main_quest_data.quest_id
		quest_name = tile.main_quest_data.quest_name
		xp_reward = tile.main_quest_data.xp_reward
	else:
		push_warning("У локации '%s' не назначен MainQuestEvent — использую location_id как запасной quest_id." % generator.location_data.location_name)
		quest_id = generator.location_data.location_id
		quest_name = generator.location_data.location_name

	QuestManager.complete_main_quest(quest_id, quest_name, xp_reward)
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
			if location.time_of_day_matters and (e.phases & PlayerState.clock.phase_bit()) == 0:
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
		extra_states = [{"difficulty": wall_hole_difficulty, "fail_damage": wall_hole_fail_damage, "run": self}]

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


## Клетка награды: атмосферная фраза + что найдено, затем выдача (через
## обычный give_item — при полном рюкзаке сработает экран переполнения).
## Диалог собирается на лету, как у _start_return_choice.
func _on_reward_tile() -> void:
	roll_loot()
	if not has_pending_loot():
		push_warning("DungeonRun: клетка награды — у локации нет таблицы добычи (LocationData.loot_*).")
		return
	# Без двоеточий в тексте: "Слово: текст" Dialogue Manager читает как реплику персонажа.
	var source := "~ start\n%s\nТы подбираешь — %s.\ndo run.collect_loot()\n=> END\n" % [_pick_find_text(), get_loot_text()]
	dialogue_requested.emit(DialogueManager.create_resource_from_text(source), "start", [{"run": self}])


func _pick_find_text() -> String:
	var texts: Array[String] = []
	if generator.location_data != null:
		texts = generator.location_data.loot_find_texts
	if texts.is_empty():
		texts = DEFAULT_FIND_TEXTS
	return texts[randi() % texts.size()]


# ====================== ДОБЫЧА ======================
## Для клеток REWARD и для ивентов. В .dialogue ивента:
##   do run.roll_loot()
##   Ты находишь — {{run.get_loot_text()}}.
## (без двоеточия: "Слово: текст" Dialogue Manager считает репликой персонажа)
##   do run.collect_loot()

## Бросить таблицу добычи локации для текущей сложности (или свою).
func roll_loot(table: LootTable = null) -> void:
	if table == null and generator.location_data != null:
		table = generator.location_data.get_loot_table(GameManager.current_difficulty)
	_pending_loot = table.roll() if table != null else {}


func has_pending_loot() -> bool:
	return not _pending_loot.is_empty() and (not _pending_loot.items.is_empty() or _pending_loot.money > 0)


## "Порох x2, Ткань, 12 денег"
func get_loot_text() -> String:
	if not has_pending_loot():
		return "ничего"
	var parts: PackedStringArray = []
	for item_id in _pending_loot.items:
		var item := PlayerState.catalog.get_item(item_id)
		var count: int = _pending_loot.items[item_id]
		var item_name: String = item.display_name if item else item_id
		parts.append(item_name if count == 1 else "%s x%d" % [item_name, count])
	if _pending_loot.money > 0:
		parts.append("%d денег" % _pending_loot.money)
	return ", ".join(parts)


## Выдать брошенное. Корутина: диалог (do) ждёт экраны переполнения.
func collect_loot() -> void:
	var loot := _pending_loot
	_pending_loot = {}
	if loot.is_empty():
		return
	for item_id in loot.items:
		await PlayerState.give_item(item_id, loot.items[item_id])
	if loot.money > 0:
		PlayerState.add_money(loot.money)


## Диалог "уйти/остаться" собирается на лету через create_resource_from_text —
## prompt динамический (основной квест / сайд-квест / выход), поэтому
## отдельный .dialogue-файл под каждый вариант был бы избыточен.
func _start_return_choice(prompt: String) -> void:
	var source := "~ start\n%s\n- Остаться => END\n- Уйти\n\t$> GameManager.return_to_hub()\n\t=> END\n" % prompt
	dialogue_requested.emit(DialogueManager.create_resource_from_text(source), "start", [])
