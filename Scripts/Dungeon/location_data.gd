class_name LocationData
extends Resource
## Аналог LocationDataSO. В Godot ScriptableObject -> обычный Resource,
## создаётся так же через "New Resource" в инспекторе и сохраняется как .tres

@export_group("Общая информация")
@export var location_name: String = "Новая локация"
@export_multiline var description: String = "Описание локации"

@export_group("Идентификатор локации")
@export var location_id: String = ""  # например: "slums", "factory", "dungeon"

@export_group("Генерация лабиринта (база)")
@export var room_count_x: int = 8
@export var room_count_y: int = 8
@export var min_quest_distance: int = 5

@export_group("Основной квест")
## Один основной квест на локацию — генератор всегда кладёт для него тайл
## EventType.QUEST (см. DungeonGenerator._assign_events_to_rooms, п.4),
## это поле только даёт ему id/имя для журнала. Может быть пустым, пока
## не назначили — тогда журнал квестов получит запасной id (см.
## DungeonRun._on_main_quest_tile).
@export var main_quest: MainQuestEvent

@export_group("Сайд-квесты")
## Пул сайд-квестов, которые МОГУТ появиться на этой локации — по одному на
## сложность, выбирается совпадением SideQuestEvent.difficulty с текущей
## сложностью забега. Раньше единственным источником правды было
## список активных квестов QuestManager, из-за чего тайл появлялся только для
## уже взятых у NPC квестов — а квест с requires_acceptance == false должен
## уметь появиться и без этого (см. DungeonGenerator._try_place_side_quest_tile).
@export var side_quests: Array[SideQuestEvent] = []

@export_group("Веса событий на клетках")
## ОТНОСИТЕЛЬНЫЕ веса, а не вероятности: важна только пропорция. Например,
## 4 / 2 / 2 / 1 — пустых клеток вдвое больше, чем врагов. Сумма может быть
## любой (см. DungeonGenerator._roll_tile_event).
@export_range(0.0, 10.0, 0.05, "or_greater") var empty_weight: float = 0.4
@export_range(0.0, 10.0, 0.05, "or_greater") var enemy_weight: float = 0.25
@export_range(0.0, 10.0, 0.05, "or_greater") var random_event_weight: float = 0.2
@export_range(0.0, 10.0, 0.05, "or_greater") var reward_weight: float = 0.1

@export_group("Случайные ивенты")
## Локация под открытым небом / живёт по часам: ивенты фильтруются по
## времени суток (RandomEvent.phases), фоны берутся по фазе (views_*).
## Выключено (подземелье, бункер) — фазы игнорируются: доступны все ивенты,
## фон всегда views_day.
@export var time_of_day_matters: bool = false
## Единый пул для этой локации — просто докидываешь подготовленные
## RandomEvent в инспекторе, без кода. Раньше тут было два массива
## (standard/unique — "общие" и "только для этой локации"), но при
## текущем масштабе это лишнее разделение: то же самое достигается
## вручную — просто не класть один и тот же ресурс в две локации,
## если он должен быть уникальным. Один массив проще и не даёт
## запутаться, откуда на самом деле взялся конкретный ивент.
@export var random_events: Array[RandomEvent] = []

@export_group("Странствующий торговец")
## Кто может встретиться на тайле MERCHANT в этой локации (сам тайл ставит
## генератор — ровно один за забег, с шансом merchant_chance). Разные
## локации — разные торговцы и реплики: просто положи нужные MerchantData.
@export var merchants: Array[MerchantData] = []
## Вероятность (0-1), что торговец вообще появится в забеге. Это НЕ вес
## среди событий клеток — отдельный бросок на весь забег.
@export_range(0.0, 1.0) var merchant_chance: float = 0.15

@export_group("Добыча (по сложности)")
## Таблица добычи на каждую сложность (клетки REWARD, ивенты, позже враги).
## Если для сложности таблица не назначена — берётся ближайшая ЛЁГКАЯ
## (никогда не более щедрая), см. get_loot_table().
@export var loot_easy: LootTable
@export var loot_normal: LootTable
@export var loot_hard: LootTable
@export var loot_very_hard: LootTable
@export var loot_extreme: LootTable
## Атмосферные фразы для клетки REWARD ("В ржавом шкафчике ты находишь...").
## Пусто — общие фразы из DungeonRun. Без двоеточий (иначе Dialogue Manager
## сочтёт начало фразы именем говорящего).
@export var loot_find_texts: Array[String] = []

@export_group("Вид от первого лица")
## Фоны лабиринта по времени суток. Обязателен только views_day — его же
## берём, если для текущей фазы набора нет, и всегда, если у локации
## выключен time_of_day_matters (подземелье: время суток не видно).
@export var views_day: MazeViewSet
@export var views_dawn: MazeViewSet
@export var views_dusk: MazeViewSet
@export var views_night: MazeViewSet

@export_group("Противники (по сложности)")
## Кто встречается на клетках ENEMY, группы, шанс заметить первым — см.
## EncounterTable. Нет таблицы для сложности — ближайшая более лёгкая.
@export var encounters_easy: EncounterTable
@export var encounters_normal: EncounterTable
@export var encounters_hard: EncounterTable
@export var encounters_very_hard: EncounterTable
@export var encounters_extreme: EncounterTable

@export_group("Поражение")
## Общая сцена поражения ВНЕ боя для этой локации (урон от событий и т.п.).
## В бою будет своя — у конкретного врага. Нужна секция ~ start; в диалог
## передаётся {"run": DungeonRun}. Последствия сцены (похоть, возбуждение,
## флаги) — мутациями прямо в ней; штрафы и перенос делает DungeonRun ПОСЛЕ.
@export var defeat_dialogue: DialogueResource

@export_group("Дополнительно")
@export var min_reward_count: int = 2


## Таблица встреч для сложности; нет своей — ближайшая более лёгкая.
func get_encounter_table(difficulty: Difficulty.Level) -> EncounterTable:
	var tables := [encounters_easy, encounters_normal, encounters_hard, encounters_very_hard, encounters_extreme]
	for level in range(int(difficulty), -1, -1):
		if tables[level] != null:
			return tables[level]
	return null


## Таблица добычи для сложности; нет своей — ближайшая более лёгкая.
func get_loot_table(difficulty: Difficulty.Level) -> LootTable:
	var tables := [loot_easy, loot_normal, loot_hard, loot_very_hard, loot_extreme]
	for level in range(int(difficulty), -1, -1):
		if tables[level] != null:
			return tables[level]
	return null


## Взвешенный случайный выбор из random_events, с двумя правилами: не
## повторять exclude (последний показанный ивент), если в пуле есть что-то
## ещё, и (опционально) пропускать события, для которых is_eligible
## возвращает false — так события со спец-условиями (например, "дыра в
## стене" нуждается в подходящей геометрии рядом, см.
## RandomEvent.requires_wall_hole_geometry и DungeonRun._on_random_event_tile)
## просто не участвуют в розыгрыше, когда условие не выполнено, а не
## "выпадают и ничего не показывают". История показов не хранится здесь —
## это дело вызывающей стороны (см. DungeonRun._last_random_event),
## LocationData — просто данные.
func pick_random_event(exclude: RandomEvent = null, is_eligible: Callable = Callable()) -> RandomEvent:
	var pool := random_events
	if is_eligible.is_valid():
		pool = pool.filter(is_eligible)
	if exclude != null and pool.size() > 1:
		pool = pool.filter(func(e): return e != exclude)
	return _weighted_pick(pool)


## Торговец на забег один, поэтому "не повторять предыдущего" не нужно —
## просто взвешенный выбор из merchants этой локации.
func pick_merchant() -> MerchantData:
	return _weighted_pick(merchants)


## Общий взвешенный выбор для любых записей с полем weight (RandomEvent,
## MerchantData). Пустой пул — null.
func _weighted_pick(pool: Array):
	if pool.is_empty():
		return null

	var total_weight := 0
	for e in pool:
		total_weight += e.weight
	if total_weight <= 0:
		return pool[randi() % pool.size()]

	var roll := randi() % total_weight
	for e in pool:
		roll -= e.weight
		if roll < 0:
			return e
	return pool[pool.size() - 1]  # запасной вариант на случай ошибки округления


## Набор фонов для текущего времени суток (см. группу "Вид от первого лица").
func get_view_set(phase: GameClock.Phase) -> MazeViewSet:
	var by_phase: MazeViewSet = null
	if time_of_day_matters:
		match phase:
			GameClock.Phase.DAWN:
				by_phase = views_dawn
			GameClock.Phase.DUSK:
				by_phase = views_dusk
			GameClock.Phase.NIGHT:
				by_phase = views_night
	return by_phase if by_phase != null else views_day
