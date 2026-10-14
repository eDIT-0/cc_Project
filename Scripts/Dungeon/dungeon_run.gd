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
##   любой вид        — только рисует и переводит ввод в вызовы try_step().
##
## Движение — как в Grimrock-подобных "от первого лица": у игрока есть
## взгляд (_facing). W — шаг вперёд, A/D — шаг сразу в боковую клетку,
## S — шаг назад; после любого шага игрок смотрит туда, куда шёл. Отдельного
## поворота на месте нет — каждый шаг тратит время и выносливость.
##
## DungeonRun ничего не знает ни про отрисовку, ни про конкретный DialogueBox:
## он лишь сообщает сигналами, что изменилось и какой диалог нужно показать.
## Кто именно покажет диалог — решает сцена/вид (см. DebugMazeView._ready).
##
## Всё состояние забега сбрасывается в _on_dungeon_generated(), то есть
## привязано к конкретной генерации, а не к времени жизни узла.

## Лабиринт сгенерирован, игрок поставлен на старт.
signal run_started
## Игрок переместился (обычный шаг или "дыра в стене"). Взгляд — get_facing().
signal player_moved(tile_pos: Vector2i)
## Изменилось содержимое клеток (событие погашено и т.п.) — повод перерисовать карту.
signal map_changed
## Шаг в стену — для вида (звук/тряска/сообщение), правилам он ничего не меняет.
## direction — абсолютная сторона света, куда пытались шагнуть.
signal move_blocked(direction: DungeonTypes.Direction)
## Встреча с противниками началась / закончилась — вид показывает и
## убирает их фигуры (MazeBackground).
signal encounter_started(encounter: Encounter)
signal encounter_ended(encounter: Encounter)
## Началось настоящее сражение (после диалогов встречи).
signal combat_started(combat: CombatController)
## Нужно показать диалог. Аргументы — ровно как у DialogueBox.play().
signal dialogue_requested(resource: Resource, cue: String, extra_game_states: Array)

@export var generator: DungeonGenerator

## Диалоги встречи (общие для всех локаций).
const ENCOUNTER_SPOTTED_DIALOGUE := "res://Dialogue/encounter_spotted.dialogue"
const ENEMY_TALK_DEFAULT_DIALOGUE := "res://Dialogue/enemy_talk_default.dialogue"
## Можно заменить ресурс настроек в инспекторе DungeonRun.
@export var combat_rules: CombatRules = preload("res://Data/Combat/test_combat_rules.tres")
var combat: CombatController

## Шаг относительно взгляда игрока.
enum Step { FORWARD, LEFT, RIGHT, BACK }

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
var _previous_tile: Vector2i
var _encounter_tile: Vector2i
var _encounter_entry_tile: Vector2i
## Конкретная группа на клетке сохраняется после побега, до конца забега.
var _stored_encounters: Dictionary = {}
## Куда игрок смотрит (абсолютная сторона света).
var _facing: DungeonTypes.Direction = DungeonTypes.Direction.NORTH
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
## В какую сторону лезем — после дыры игрок смотрит туда (даже если в стену).
var _wall_hole_direction: DungeonTypes.Direction

# --- противники ---
## Текущая встреча (null — нет). Шаги встречи идут через диалоги, следующий
## шаг — после конца диалога (on_dialogue_finished -> _continue_encounter).
var _encounter: Encounter = null

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
	# Никаких новых автозагрузок или ручных узлов в сцене.
	combat = CombatController.new()
	combat.name = "CombatController"
	add_child(combat)
	# Итог — после стека stats.damage(): защита от повторного поражения
	# и выдачи опыта посреди обработки атаки.
	combat.combat_finished.connect(_on_combat_finished, CONNECT_DEFERRED)
	combat.combat_escaped.connect(_on_combat_escaped, CONNECT_DEFERRED)
	var screen := CombatDebugScreen.new()
	screen.name = "CombatDebugScreen"
	screen.combat = combat
	add_child(screen)
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
	elif _encounter != null:
		_continue_encounter()


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


## Здоровье на нуле вне боя (события). В бою итог приходит от контроллера.
func _on_player_died() -> void:
	# FINISHED тоже учитываем: контроллер уже послал отложенный итог.
	if _encounter != null and combat != null and (combat.is_active() or combat.state == CombatController.State.FINISHED):
		return
	trigger_defeat()


func _start_defeat(scene: DialogueResource) -> void:
	_defeat_in_progress = true
	_end_encounter()  # поражение посреди встречи — встреча окончена
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
		_facing = _pick_open_facing(_player_tile)
	_previous_tile = _player_tile
	print("☠ Поражение: очнулся в %s." % str(_player_tile))
	player_moved.emit(_player_tile)
	map_changed.emit()


# ====================== ПУБЛИЧНЫЙ ИНТЕРФЕЙС ДЛЯ ВИДА ======================

func is_running() -> bool:
	return _is_running


func get_player_tile() -> Vector2i:
	return _player_tile


func get_facing() -> DungeonTypes.Direction:
	return _facing


## Что игрок видит перед собой — по этому вид выбирает фон (MazeViewSet).
func get_view_kind() -> DungeonTypes.ViewKind:
	return DungeonTypes.view_kind_for(
		generator.can_move_from_tile(_player_tile, _facing),
		generator.can_move_from_tile(_player_tile, generator.turn_left(_facing)),
		generator.can_move_from_tile(_player_tile, generator.turn_right(_facing)))


## Шаг относительно взгляда (W/A/S/D). Возвращает true, если шаг сделан.
## Открыт ли сейчас диалог, DungeonRun не проверяет — это забота вида,
## который знает про DialogueBox (см. DebugMazeView._unhandled_input).
func try_step(step: Step) -> bool:
	var direction := _facing
	match step:
		Step.LEFT:
			direction = generator.turn_left(_facing)
		Step.RIGHT:
			direction = generator.turn_right(_facing)
		Step.BACK:
			direction = generator.turn_back(_facing)
	return try_move(direction)


## Шаг в абсолютном направлении; после шага игрок смотрит туда же.
## Обычно вид зовёт try_step(), это — для особых случаев.
func try_move(direction: DungeonTypes.Direction) -> bool:
	if not _is_running or _encounter != null or is_defeat_in_progress() or _dialogue_open:
		return false
	return _move_to(direction)


## Один реальный шаг, общий для обычного движения и успешного побега.
func _move_to(direction: DungeonTypes.Direction) -> bool:
	if not generator.can_move_from_tile(_player_tile, direction):
		print("🚧 Стена — туда не пройти")
		move_blocked.emit(direction)
		return false

	_previous_tile = _player_tile
	_player_tile = generator.get_neighbor_tile(_player_tile, direction)
	_facing = direction
	PlayerState.on_maze_step()  # -выносливость, +10 игровых минут
	var tile := generator.get_tile(_player_tile)
	var event_type := tile.event_type if tile else DungeonTypes.EventType.EMPTY

	# Посещение и расход события — два разных действия. consume_event()
	# чистит одноразовые события в EMPTY, а QUEST/EXIT/MERCHANT/ENEMY не трогает:
	# EXIT должен остаться навсегда, к торговцу можно вернуться, а QUEST мы
	# гасим сами в _on_main_quest_tile(), ENEMY — после исхода встречи.
	# Тип события запомнен выше, ДО
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
		DungeonTypes.EventType.ENEMY:
			_on_enemy_tile()
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
	_previous_tile = _player_tile
	_player_tile = _wall_hole_target
	_facing = _wall_hole_direction
	PlayerState.on_maze_step()  # протиснуться — тоже шаг
	generator.mark_as_visited(_player_tile)
	generator.consume_event(_player_tile)
	player_moved.emit(_player_tile)
	map_changed.emit()


# ====================== СТАРТ ЗАБЕГА ======================

## Куда смотреть, появившись на клетке (старт, после поражения): в первый
## открытый проход, чтобы не начинать носом в стену.
func _pick_open_facing(tile_pos: Vector2i) -> DungeonTypes.Direction:
	for dir in [DungeonTypes.Direction.NORTH, DungeonTypes.Direction.EAST,
			DungeonTypes.Direction.SOUTH, DungeonTypes.Direction.WEST]:
		if generator.can_move_from_tile(tile_pos, dir):
			return dir
	return DungeonTypes.Direction.NORTH


func _on_dungeon_generated() -> void:
	_player_tile = generator.get_start_tile()
	_previous_tile = _player_tile
	_stored_encounters.clear()
	generator.mark_as_visited(_player_tile)
	_facing = _pick_open_facing(_player_tile)
	_last_random_event = null
	_random_event_occurrences.clear()
	_current_merchant = null
	if combat != null:
		combat.abort()
	_encounter = null
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
		_wall_hole_direction = passage["direction"]
		# Бросок — ДО открытия диалога, не внутри него: условия в .dialogue
		# резолвятся только против переданных extra_game_states/автозагрузок
		# по имени, глобальные функции (тот же randf()) им не видны.
		extra_states = [{"difficulty": wall_hole_difficulty, "fail_damage": wall_hole_fail_damage, "run": self}]
	extra_states.append({"pics": EventPictures.new(chosen.images, chosen.show_first_image)})

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


## ====================== ПРОТИВНИКИ ======================
## Клетка ENEMY остаётся до исхода встречи. После побега возвращаем
## ту же группу с сохранёнными HP/настроем. Состав новой группы —
## из таблицы локации; с шансом игрок замечает врага первым и выбирает
## (засада / проскользнуть / заговорить), иначе — сразу бой.

func _on_enemy_tile() -> void:
	_encounter_tile = _player_tile
	_encounter_entry_tile = _previous_tile
	if _stored_encounters.has(_player_tile):
		_encounter = _stored_encounters[_player_tile]
		_encounter.opening = Encounter.Opening.NORMAL
		_encounter.next_step = Encounter.Next.NONE
		encounter_started.emit(_encounter)
		_start_combat()
		return
	var location := generator.location_data
	var table: EncounterTable = location.get_encounter_table(GameManager.current_difficulty) if location != null else null
	if table == null:
		push_warning("DungeonRun: клетка врага — у локации нет таблицы встреч (LocationData.encounters_*).")
		_clear_enemy_tile()
		return
	var is_night := location.time_of_day_matters and PlayerState.clock.is_night()
	var enemies := table.roll_enemies(is_night)
	if enemies.is_empty():
		push_warning("DungeonRun: таблица встреч пуста — клетка врага ничего не даёт.")
		_clear_enemy_tile()
		return

	_encounter = Encounter.new(enemies, table)
	_stored_encounters[_player_tile] = _encounter
	encounter_started.emit(_encounter)
	var spot_chance := table.get_spot_chance(location.time_of_day_matters)
	var spotted := randf() < spot_chance
	print("⚔ Встреча: %s (заметить первым — %d%%: %s)" % [
		_encounter.get_names_text(), roundi(spot_chance * 100), "да" if spotted else "нет"])

	if spotted:
		_play_encounter_dialogue(load(ENCOUNTER_SPOTTED_DIALOGUE), "start")
	else:
		_encounter.fight()
		_continue_encounter()


## Следующий шаг встречи — по тому, что выбрал последний диалог.
func _continue_encounter() -> void:
	var enc := _encounter
	var step := enc.next_step
	enc.next_step = Encounter.Next.NONE
	match step:
		Encounter.Next.FIGHT:
			_start_combat()
		Encounter.Next.TALK:
			var leader := enc.get_leader()
			if leader.talk_dialogue != null:
				_play_encounter_dialogue(leader.talk_dialogue, leader.talk_start)
			else:
				_play_encounter_dialogue(load(ENEMY_TALK_DEFAULT_DIALOGUE), "start")
		Encounter.Next.AVOID:
			var xp := enc.get_avoid_xp(enc.avoid_xp_fraction)
			print("👣 Боя удалось избежать: опыт +%d" % xp)
			PlayerState.stats.add_xp(xp)
			_end_encounter()
		Encounter.Next.WIN:
			print("🏆 Победа: опыт +%d" % enc.get_total_xp())
			PlayerState.stats.add_xp(enc.get_total_xp())
			_end_encounter()
		Encounter.Next.LOSE:
			var scene := enc.get_leader().defeat_dialogue
			_end_encounter()
			trigger_defeat(scene)
		_:
			# Диалог закончился, ничего не выбрав (ошибка в .dialogue) — бой.
			push_warning("DungeonRun: диалог встречи не выбрал, что дальше — начинаю бой.")
			enc.fight()
			_start_combat()


## Настоящий бой. Начальное преимущество — задержка зарядки, не энергия.
func _start_combat() -> void:
	if _encounter == null or combat.is_active():
		return
	combat.escape_allowed = not _get_escape_directions().is_empty()
	combat.start(_encounter, combat_rules, GameManager.current_difficulty)
	combat_started.emit(combat)


func _on_combat_finished(won: bool) -> void:
	if _encounter == null or combat.state != CombatController.State.FINISHED or is_defeat_in_progress():
		return
	if won:
		_encounter.win()
	else:
		_encounter.lose()
	_continue_encounter()


## Случайный другой выход. Если других проходов нет — назад через вход.
func _get_escape_directions() -> Array[DungeonTypes.Direction]:
	var other: Array[DungeonTypes.Direction] = []
	var back: Array[DungeonTypes.Direction] = []
	for direction in [DungeonTypes.Direction.NORTH, DungeonTypes.Direction.EAST, DungeonTypes.Direction.SOUTH, DungeonTypes.Direction.WEST]:
		if not generator.can_move_from_tile(_player_tile, direction):
			continue
		if generator.get_neighbor_tile(_player_tile, direction) == _encounter_entry_tile:
			back.append(direction)
		else:
			other.append(direction)
	return other if not other.is_empty() else back


func _on_combat_escaped() -> void:
	if _encounter == null or combat.state != CombatController.State.FINISHED or is_defeat_in_progress():
		return
	var directions := _get_escape_directions()
	if directions.is_empty():
		push_warning("DungeonRun: выходов не осталось — возобновляю встречу.")
		_start_combat()
		return
	var direction := directions[randi() % directions.size()]
	_stored_encounters[_encounter_tile] = _encounter
	_end_encounter(true)
	_move_to(direction)


func _clear_enemy_tile() -> void:
	var tile := generator.get_tile(_encounter_tile)
	if tile != null and tile.event_type == DungeonTypes.EventType.ENEMY:
		tile.event_type = DungeonTypes.EventType.EMPTY
	_stored_encounters.erase(_encounter_tile)
	map_changed.emit()


func _play_encounter_dialogue(resource: DialogueResource, cue: String) -> void:
	dialogue_requested.emit(resource, cue, [{"enc": _encounter, "run": self}])


func _end_encounter(keep_tile: bool = false) -> void:
	if _encounter == null:
		return
	if not keep_tile:
		_clear_enemy_tile()
	var enc := _encounter
	_encounter = null
	if combat != null:
		combat.abort()
	encounter_ended.emit(enc)


func is_in_encounter() -> bool:
	return _encounter != null


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
