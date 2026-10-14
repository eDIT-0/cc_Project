class_name DungeonGenerator
extends Node
## Порт DungeonGenerator.cs.
## Логика 1-в-1 с оригиналом, за двумя осознанными исключениями:
## 1) в _assign_events_to_rooms() добавлена проверка, которой не было в
##    Unity-версии и из-за которой тайл сайд-квеста затирался случайным
##    ивентом (см. пометку FIX ниже).
## 2) сложность больше не поле на самой LocationData — она приходит из
##    GameManager.current_difficulty (выбирается в хабе перед сменой сцены)
##    и применяется поверх базовых чисел локации через DifficultyTuning.

signal dungeon_generated

## true только после того, как generate_dungeon() реально отработал —
## до этого тайлов нет, рисовать и ходить нечего.
var is_generated: bool = false

## Необязательная ручная подстановка локации — для запуска сцены лабиринта
## напрямую из редактора (F6), минуя хаб. В обычной игре пусто, локация
## приходит из GameManager.current_location.
@export var location_data: LocationData

@export_group("Балансировка по сложности")
@export var difficulty_tunings: Array[DifficultyTuning] = []

# ---- Рабочие параметры ТЕКУЩЕЙ генерации ----
# Не @export: раньше они висели в инспекторе, но при генерации молча
# перезаписывались значениями из LocationData (+ поправки сложности),
# так что правка в инспекторе ни на что не влияла. Настраивать —
# в LocationData / DifficultyTuning.
var room_count_x: int = 0
var room_count_y: int = 0
var min_quest_distance: int = 0
var min_reward_count: int = 0
## Вероятность появления торговца за забег (0-1) — отдельный бросок.
var merchant_chance: float = 0.0
## ОТНОСИТЕЛЬНЫЕ веса событий на клетках (см. _roll_tile_event).
var empty_weight: float = 0.0
var enemy_weight: float = 0.0
var random_event_weight: float = 0.0
var reward_weight: float = 0.0

var _tiles: Array = []  # плоский массив DungeonTile, индекс = x * tile_count_y + y
var _current_difficulty: Difficulty.Level = Difficulty.Level.NORMAL

## Длина пути (в комнатах) от стартовой комнаты по коридорам лабиринта:
## Vector2i комнаты -> int. Считается BFS один раз после прорубки проходов
## (см. _compute_room_distances) и дальше только читается.
var _room_distances: Dictionary = {}

var tile_count_x: int:
	get: return room_count_x * 2 + 1
var tile_count_y: int:
	get: return room_count_y * 2 + 1


func _ready() -> void:
	if GameManager:
		GameManager.register_dungeon_generator(self)


func generate_dungeon() -> void:
	# Если LocationData не назначена вручную — берём из GameManager
	if location_data == null:
		if GameManager and GameManager.current_location:
			location_data = GameManager.current_location
		else:
			push_error("DungeonGenerator: ни LocationData, ни GameManager не найдены!")
			return

	_current_difficulty = GameManager.current_difficulty if GameManager else Difficulty.Level.NORMAL

	# Применяем базовые настройки локации
	room_count_x = location_data.room_count_x
	room_count_y = location_data.room_count_y
	min_quest_distance = location_data.min_quest_distance

	empty_weight = location_data.empty_weight
	enemy_weight = location_data.enemy_weight
	random_event_weight = location_data.random_event_weight
	reward_weight = location_data.reward_weight
	merchant_chance = location_data.merchant_chance
	min_reward_count = location_data.min_reward_count

	# ...и поверх — добавки от текущей сложности (если для неё есть тюнинг)
	var tuning := _get_tuning(_current_difficulty)
	if tuning:
		room_count_x += tuning.room_count_bonus
		room_count_y += tuning.room_count_bonus
		min_quest_distance += tuning.min_quest_distance_bonus
		# Веса не обязаны укладываться в 0-1 — только не уходить в минус
		enemy_weight = maxf(0.0, enemy_weight + tuning.enemy_weight_delta)
		reward_weight = maxf(0.0, reward_weight + tuning.reward_weight_delta)
		random_event_weight = maxf(0.0, random_event_weight + tuning.random_event_weight_delta)
		merchant_chance = clampf(merchant_chance + tuning.merchant_chance_delta, 0.0, 1.0)
		min_reward_count += tuning.min_reward_count_bonus
	else:
		push_warning("DungeonGenerator: нет DifficultyTuning для уровня %s — используются базовые значения локации без поправок." % Difficulty.Level.keys()[_current_difficulty])

	_validate_location_data()
	_initialize_tiles()
	_carve_rooms_and_passages()
	_compute_room_distances()
	_assign_events_to_rooms()

	print("✅ Лабиринт сгенерирован: %s | Сложность: %s | %dx%d комнат" % [
		location_data.location_name, Difficulty.Level.keys()[_current_difficulty], room_count_x, room_count_y
	])

	is_generated = true
	dungeon_generated.emit()


## Проверки данных локации, которые нельзя выразить типами в инспекторе.
## Только предупреждения — генерация продолжается как есть.
func _validate_location_data() -> void:
	for quest in location_data.side_quests:
		if quest != null and quest.location_id != location_data.location_id:
			push_warning("Сайд-квест '%s' лежит в локации '%s', но у него location_id = '%s' — слот квеста в QuestManager будет не тот." % [
				quest.quest_id, location_data.location_id, quest.location_id
			])


## Взвешенный выбор события для обычной клетки. Раньше это была цепочка
## порогов (roll < empty, < empty+enemy, ...): при сумме шансов > 1 последние
## в цепочке (награды) молча выпадали, а при сумме < 1 остаток уходил в EMPTY.
## Теперь значения — относительные веса: важна только пропорция между ними,
## сумма может быть любой.
func _roll_tile_event() -> DungeonTypes.EventType:
	var table := [
		[DungeonTypes.EventType.EMPTY, empty_weight],
		[DungeonTypes.EventType.ENEMY, enemy_weight],
		[DungeonTypes.EventType.RANDOM_EVENT, random_event_weight],
		[DungeonTypes.EventType.REWARD, reward_weight],
	]
	var total := 0.0
	for entry in table:
		total += entry[1]
	if total <= 0.0:
		return DungeonTypes.EventType.EMPTY

	var roll := randf() * total
	for entry in table:
		roll -= entry[1]
		if roll < 0.0:
			return entry[0]
	return DungeonTypes.EventType.EMPTY  # запасной вариант на случай ошибки округления


func _get_tuning(level: Difficulty.Level) -> DifficultyTuning:
	for t in difficulty_tunings:
		if t.level == level:
			return t
	return null


# ==================== ГЕНЕРАЦИЯ ЛАБИРИНТА ====================

func _carve_rooms_and_passages() -> void:
	var stack: Array[Vector2i] = []
	var start_room := Vector2i.ZERO
	var start_tile := _room_to_tile(start_room)

	_set_tile_type(start_tile, DungeonTypes.TileType.FLOOR)
	stack.append(start_room)

	while not stack.is_empty():
		var current_room: Vector2i = stack[-1]
		var neighbors := _get_unvisited_room_neighbors(current_room)

		if not neighbors.is_empty():
			var chosen_room: Vector2i = neighbors[randi() % neighbors.size()]

			# Прорубаем проход между комнатами
			_carve_passage(current_room, chosen_room)

			var chosen_tile := _room_to_tile(chosen_room)
			_set_tile_type(chosen_tile, DungeonTypes.TileType.FLOOR)
			stack.append(chosen_room)
		else:
			stack.pop_back()


func _room_to_tile(room: Vector2i) -> Vector2i:
	return Vector2i(room.x * 2 + 1, room.y * 2 + 1)


func _get_unvisited_room_neighbors(room: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]

	for dir in dirs:
		var neighbor_room: Vector2i = room + dir
		if neighbor_room.x >= 0 and neighbor_room.x < room_count_x \
				and neighbor_room.y >= 0 and neighbor_room.y < room_count_y:
			var neighbor_tile := _room_to_tile(neighbor_room)
			if _get_tile(neighbor_tile).type == DungeonTypes.TileType.WALL:
				neighbors.append(neighbor_room)

	return neighbors


func _carve_passage(room_a: Vector2i, room_b: Vector2i) -> void:
	var tile_a := _room_to_tile(room_a)
	var tile_b := _room_to_tile(room_b)
	var mid := (tile_a + tile_b) / 2
	_set_tile_type(mid, DungeonTypes.TileType.FLOOR)


func _initialize_tiles() -> void:
	_tiles.resize(tile_count_x * tile_count_y)
	for x in range(tile_count_x):
		for y in range(tile_count_y):
			var tile := DungeonTile.new(Vector2i(x, y))
			tile.type = DungeonTypes.TileType.WALL
			_tiles[_index(x, y)] = tile


## Пытается разместить тайл сайд-квеста ДО случайного назначения обычных событий.
## Ищет в LocationData.side_quests подходящий под текущую сложность квест —
## каталог, а не список активных квестов QuestManager, чтобы requires_acceptance
## == false квесты могли появиться, даже если их никто не брал у NPC.
## Уже пройденные (см. QuestManager.is_quest_completed) не показываем
## повторно; квесты с requires_acceptance == true по-прежнему требуют,
## чтобы игрок сначала взял их через диалог.
func _find_side_quest_for_current_difficulty() -> SideQuestEvent:
	for quest in location_data.side_quests:
		if quest == null or quest.difficulty != _current_difficulty:
			continue
		if QuestManager.is_quest_completed(quest.quest_id):
			continue
		if not QuestManager.are_prerequisites_completed(quest.prerequisite_quest_ids):
			continue
		if quest.requires_acceptance and not QuestManager.is_side_quest_active(quest):
			continue
		return quest
	return null


func _try_place_side_quest_tile() -> void:
	if not QuestManager or location_data == null:
		return

	if location_data.location_id.is_empty():
		return

	var side_quest := _find_side_quest_for_current_difficulty()
	if side_quest == null:
		return

	var target_distance: int = maxi(1, min_quest_distance - 2)

	var side_quest_room := _pick_room_at_distance(target_distance, "сайд-квест")
	if side_quest_room == NO_ROOM:
		return

	var tile_pos := _room_to_tile(side_quest_room)

	if is_passable_tile(tile_pos):
		var tile := _get_tile(tile_pos)

		if tile.event_type == DungeonTypes.EventType.EMPTY \
				or tile.event_type == DungeonTypes.EventType.RANDOM_EVENT:
			tile.event_type = DungeonTypes.EventType.SIDE_QUEST
			tile.side_quest_data = side_quest
			print("[SideQuest] Размещён: %s в тайле %s" % [side_quest.quest_id, tile_pos])


func _assign_events_to_rooms() -> void:
	_try_place_side_quest_tile()

	# 1. Случайное назначение ивентов на все Floor-тайлы
	for x in range(tile_count_x):
		for y in range(tile_count_y):
			var tile := _get_tile(Vector2i(x, y))
			if tile.type != DungeonTypes.TileType.FLOOR:
				continue

			# FIX: в оригинальной Unity-версии этой проверки не было —
			# тайл сайд-квеста, размещённый выше, тут же перезаписывался
			# случайным броском. Пропускаем такие тайлы.
			if tile.event_type == DungeonTypes.EventType.SIDE_QUEST:
				continue

			tile.event_type = _roll_tile_event()

	# 2. Стартовая зона всегда пустая
	var start_room_tile := _room_to_tile(Vector2i.ZERO)
	_get_tile(start_room_tile).event_type = DungeonTypes.EventType.EMPTY

	var around_start := [
		start_room_tile + Vector2i(0, 1),
		start_room_tile + Vector2i(0, -1),
		start_room_tile + Vector2i(-1, 0),
		start_room_tile + Vector2i(1, 0),
	]
	for pos in around_start:
		if is_passable_tile(pos):
			_get_tile(pos).event_type = DungeonTypes.EventType.EMPTY

	# 3. Путь отхода — ВСЕГДА на стартовой клетке
	_get_tile(start_room_tile).event_type = DungeonTypes.EventType.EXIT

	# 4. Комната с основным квестом — не ближе min_quest_distance от старта.
	# Ставится ДО наград и торговца (раньше была последним шагом и могла
	# затереть их): так шаги 5-6 видят квест как занятую клетку и обходят
	# его, а гарантия минимума наград не ломается задним числом.
	# _pick_room_at_distance() сам пропускает старт и занятые комнаты.
	var quest_room := _pick_room_at_distance(min_quest_distance, "основной квест")
	var distance := -1
	if quest_room == NO_ROOM:
		push_error("DungeonGenerator: основной квест не размещён — в лабиринте нет свободных комнат, кроме стартовой.")
	else:
		distance = _room_distance_from_start(quest_room)
		var quest_tile := _get_tile(_room_to_tile(quest_room))
		quest_tile.event_type = DungeonTypes.EventType.QUEST
		quest_tile.main_quest_data = location_data.main_quest

	# 5. Гарантируем минимум наград — только на "расходных" клетках:
	# занятые (сайд-квест, основной квест, выход) не трогаем.
	var reward_candidates: Array[Vector2i] = []
	var current_rewards := 0

	for x in range(tile_count_x):
		for y in range(tile_count_y):
			var pos := Vector2i(x, y)
			var tile := _get_tile(pos)
			if tile.type != DungeonTypes.TileType.FLOOR or _is_tile_reserved(pos):
				continue

			if tile.event_type == DungeonTypes.EventType.REWARD:
				current_rewards += 1
			else:
				reward_candidates.append(pos)

	while current_rewards < min_reward_count and not reward_candidates.is_empty():
		var index := randi() % reward_candidates.size()
		var pos: Vector2i = reward_candidates[index]
		_get_tile(pos).event_type = DungeonTypes.EventType.REWARD
		reward_candidates.remove_at(index)
		current_rewards += 1

	# 6. Торговец (ровно один, с шансом merchant_chance). Не встаёт ни на
	# занятые клетки, ни на награды — иначе он съедал бы награду и гарантия
	# минимума из шага 5 тихо нарушалась.
	if randf() < merchant_chance:
		var merchant_candidates: Array[Vector2i] = []

		for x in range(tile_count_x):
			for y in range(tile_count_y):
				var pos := Vector2i(x, y)
				var tile := _get_tile(pos)
				if tile.type == DungeonTypes.TileType.FLOOR \
						and not _is_tile_reserved(pos) \
						and tile.event_type != DungeonTypes.EventType.REWARD:
					merchant_candidates.append(pos)

		if merchant_candidates.is_empty():
			push_warning("DungeonGenerator: торговцу не нашлось свободной клетки — в этом забеге его не будет.")
		else:
			var chosen: Vector2i = merchant_candidates[randi() % merchant_candidates.size()]
			_get_tile(chosen).event_type = DungeonTypes.EventType.MERCHANT
			print("🛒 Торговец появился в тайле %s" % chosen)

	print("🎯 Квест в комнате %s | Расстояние: %d | Наград: %d" % [quest_room, distance, current_rewards])


# ==================== ВЫБОР КОМНАТЫ ПО РАССТОЯНИЮ ====================

## Возвращается _pick_room_at_distance(), если выбрать нечего (лабиринт 1x1).
const NO_ROOM := Vector2i(-1, -1)


## Случайная комната не ближе min_distance от старта (равновероятно среди
## подходящих — так же, как вёл себя старый цикл с повторными бросками).
## Стартовая комната (0,0) не возвращается НИКОГДА — на ней лежит EXIT.
## Комнаты, где уже лежит важное событие (сайд-квест, торговец, выход —
## см. _is_room_reserved), тоже пропускаются, чтобы не затереть их.
## Если на нужном расстоянии свободных комнат нет (лабиринт мал для
## заданного min_distance), берётся одна из самых дальних СВОБОДНЫХ комнат
## и пишется предупреждение, а не тихий откат на старт.
func _pick_room_at_distance(min_distance: int, purpose: String) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var farthest: Array[Vector2i] = []
	var max_distance := -1

	for x in range(room_count_x):
		for y in range(room_count_y):
			var room := Vector2i(x, y)
			if room == Vector2i.ZERO or _is_room_reserved(room):
				continue

			var d := _room_distance_from_start(room)
			if d < 0:
				continue  # недостижима — не кандидат ни при каких условиях
			if d >= min_distance:
				candidates.append(room)

			if d > max_distance:
				max_distance = d
				farthest.clear()
				farthest.append(room)
			elif d == max_distance:
				farthest.append(room)

	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]

	if farthest.is_empty():
		return NO_ROOM

	push_warning("DungeonGenerator: нет свободных комнат на расстоянии >= %d для '%s' — взята одна из самых дальних (%d)." % [
		min_distance, purpose, max_distance
	])
	return farthest[randi() % farthest.size()]


## Занята ли комната событием, которое нельзя затирать (см. _is_tile_reserved).
func _is_room_reserved(room: Vector2i) -> bool:
	return _is_tile_reserved(_room_to_tile(room))


## Занята ли клетка событием, которое нельзя затирать при расстановке:
## сайд-квест, основной квест, торговец, выход. Обычные ивенты (враг,
## награда, случайный ивент) — расходный материал, их перезаписывать можно.
## Единый список для всех шагов _assign_events_to_rooms() — новое "важное"
## событие достаточно добавить сюда.
func _is_tile_reserved(tile_pos: Vector2i) -> bool:
	var tile := _get_tile(tile_pos)
	if tile == null:
		return false
	return tile.event_type in [
		DungeonTypes.EventType.SIDE_QUEST,
		DungeonTypes.EventType.MERCHANT,
		DungeonTypes.EventType.EXIT,
		DungeonTypes.EventType.QUEST,
	]


## Расстояние комнаты от старта — РЕАЛЬНАЯ длина пути по коридорам в
## комнатах (сколько комнат пройти от старта), а не манхэттенское
## расстояние по прямой: в лабиринте комната "через стенку" от старта может
## оказаться в самом конце пути. -1 — комната недостижима (в идеальном
## лабиринте recursive backtracker такого не бывает, но проверка дешёвая).
## Секретные проходы ("дыра в стене") тут намеренно не учитываются — это
## расстояние "честным" путём.
func _room_distance_from_start(room: Vector2i) -> int:
	return _room_distances.get(room, -1)


## BFS по графу комнат от стартовой (0,0). Две соседние комнаты связаны,
## если тайл-проход между ними — пол. Вызывается один раз за генерацию,
## сразу после _carve_rooms_and_passages().
func _compute_room_distances() -> void:
	_room_distances.clear()
	_room_distances[Vector2i.ZERO] = 0

	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var head := 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while head < queue.size():
		var room: Vector2i = queue[head]
		head += 1

		for dir in dirs:
			var next_room: Vector2i = room + dir
			if next_room.x < 0 or next_room.x >= room_count_x \
					or next_room.y < 0 or next_room.y >= room_count_y:
				continue
			if _room_distances.has(next_room):
				continue
			# Тайл между центрами двух соседних комнат — это и есть проход
			if not is_passable_tile(_room_to_tile(room) + dir):
				continue

			_room_distances[next_room] = _room_distances[room] + 1
			queue.append(next_room)


# ==================== ПОЛЕЗНЫЕ МЕТОДЫ ДЛЯ ДРУГИХ СКРИПТОВ ====================

func get_tile(tile_pos: Vector2i) -> DungeonTile:
	return _get_tile(tile_pos)


## Длина пути от старта до комнаты по коридорам (в комнатах), -1 если
## недостижима. Для отладочного вида и будущих систем (баланс, миникарта).
func get_room_distance(room_pos: Vector2i) -> int:
	return _room_distance_from_start(room_pos)


## Тайл, с которого игрок стартует (комната (0,0) в тайловых координатах)
func get_start_tile() -> Vector2i:
	return _room_to_tile(Vector2i.ZERO)


## Клетки-комнаты без события (EMPTY) — куда можно "выбросить" игрока
## после поражения. Коридоры не берём: очнуться посреди прохода странно.
func get_empty_room_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(room_count_x):
		for y in range(room_count_y):
			var tile_pos := _room_to_tile(Vector2i(x, y))
			var tile := _get_tile(tile_pos)
			if tile != null and tile.type == DungeonTypes.TileType.FLOOR \
					and tile.event_type == DungeonTypes.EventType.EMPTY:
				result.append(tile_pos)
	return result


func get_event_at_room(room_pos: Vector2i) -> DungeonTypes.EventType:
	var tile_pos := _room_to_tile(room_pos)
	var tile := _get_tile(tile_pos)
	return tile.event_type if tile else DungeonTypes.EventType.EMPTY


func is_passable_tile(tile_pos: Vector2i) -> bool:
	var tile := _get_tile(tile_pos)
	return tile != null and tile.type == DungeonTypes.TileType.FLOOR


## Игрок побывал на клетке. ТОЛЬКО флаг посещения (для тумана войны,
## миникарты, секретных проходов) — событие клетки не трогает.
## Раньше visited ставился лишь при стирании события, и клетки со
## "стойкими" событиями (старт, торговец, квест) формально никогда не
## считались посещёнными.
func mark_as_visited(tile_pos: Vector2i) -> void:
	var tile := _get_tile(tile_pos)
	if tile == null or tile.type != DungeonTypes.TileType.FLOOR:
		return
	tile.visited = true


## Событие клетки израсходовано: одноразовые (награда, случайный
## ивент, сайд-квест) превращаются в EMPTY. ENEMY теперь гасит DungeonRun
## после исхода встречи; при побеге клетка сохраняется. Стойкие — нет: EXIT должен
## остаться навсегда, к торговцу можно вернуться (и не потерять его после
## первого "не сейчас"), а QUEST гасит сам DungeonRun, когда засчитывает.
func consume_event(tile_pos: Vector2i) -> void:
	var tile := _get_tile(tile_pos)
	if tile == null or tile.type != DungeonTypes.TileType.FLOOR:
		return
	if tile.event_type in [
		DungeonTypes.EventType.QUEST,
		DungeonTypes.EventType.EXIT,
		DungeonTypes.EventType.MERCHANT,
		DungeonTypes.EventType.ENEMY,
	]:
		return
	tile.event_type = DungeonTypes.EventType.EMPTY


func is_visited(tile_pos: Vector2i) -> bool:
	var tile := _get_tile(tile_pos)
	return tile != null and tile.visited


# ====================== ОТНОСИТЕЛЬНОЕ ДВИЖЕНИЕ ======================

func can_move_from_tile(tile_pos: Vector2i, direction: DungeonTypes.Direction) -> bool:
	var neighbor := get_neighbor_tile(tile_pos, direction)
	return is_passable_tile(neighbor)


## Система координат Godot 2D: ось Y направлена ВНИЗ, поэтому север — это
## y - 1, а юг — y + 1. (В Unity-версии Y смотрела вверх, отсюда была
## инверсия: W визуально двигало игрока вниз.) Это единственное место,
## где направление превращается в смещение — всё остальное (повороты,
## секретные проходы, движение) опирается на него.
func get_neighbor_tile(tile_pos: Vector2i, direction: DungeonTypes.Direction) -> Vector2i:
	match direction:
		DungeonTypes.Direction.NORTH: return tile_pos + Vector2i(0, -1)
		DungeonTypes.Direction.EAST: return tile_pos + Vector2i(1, 0)
		DungeonTypes.Direction.SOUTH: return tile_pos + Vector2i(0, 1)
		DungeonTypes.Direction.WEST: return tile_pos + Vector2i(-1, 0)
		_: return tile_pos


func turn_left(current: DungeonTypes.Direction) -> DungeonTypes.Direction:
	match current:
		DungeonTypes.Direction.NORTH: return DungeonTypes.Direction.WEST
		DungeonTypes.Direction.EAST: return DungeonTypes.Direction.NORTH
		DungeonTypes.Direction.SOUTH: return DungeonTypes.Direction.EAST
		DungeonTypes.Direction.WEST: return DungeonTypes.Direction.SOUTH
		_: return current


func turn_right(current: DungeonTypes.Direction) -> DungeonTypes.Direction:
	match current:
		DungeonTypes.Direction.NORTH: return DungeonTypes.Direction.EAST
		DungeonTypes.Direction.EAST: return DungeonTypes.Direction.SOUTH
		DungeonTypes.Direction.SOUTH: return DungeonTypes.Direction.WEST
		DungeonTypes.Direction.WEST: return DungeonTypes.Direction.NORTH
		_: return current


func turn_back(current: DungeonTypes.Direction) -> DungeonTypes.Direction:
	match current:
		DungeonTypes.Direction.NORTH: return DungeonTypes.Direction.SOUTH
		DungeonTypes.Direction.EAST: return DungeonTypes.Direction.WEST
		DungeonTypes.Direction.SOUTH: return DungeonTypes.Direction.NORTH
		DungeonTypes.Direction.WEST: return DungeonTypes.Direction.EAST
		_: return current


## Проверяет наличие секретного прохода ТОЛЬКО в непосещённую клетку
func try_get_secret_passage(from_tile: Vector2i) -> Dictionary:
	# Возвращает { "found": bool, "direction": Direction, "target_tile": Vector2i }
	# (в GDScript нет out-параметров, поэтому результат — словарь)
	var dirs := [
		DungeonTypes.Direction.NORTH, DungeonTypes.Direction.EAST,
		DungeonTypes.Direction.SOUTH, DungeonTypes.Direction.WEST,
	]

	for dir in dirs:
		var step1 := get_neighbor_tile(from_tile, dir)    # должен быть Wall
		var step2 := get_neighbor_tile(step1, dir)         # должен быть Floor + Empty + непосещён

		var tile1 := _get_tile(step1)
		var tile2 := _get_tile(step2)

		var is_valid := tile1 != null and tile1.type == DungeonTypes.TileType.WALL \
			and tile2 != null and tile2.type == DungeonTypes.TileType.FLOOR \
			and tile2.event_type == DungeonTypes.EventType.EMPTY \
			and not tile2.visited

		if is_valid:
			return { "found": true, "direction": dir, "target_tile": step2 }

	return { "found": false, "direction": DungeonTypes.Direction.NORTH, "target_tile": from_tile }


# ==================== ВНУТРЕННИЕ УТИЛИТЫ ====================

func _index(x: int, y: int) -> int:
	return x * tile_count_y + y


func _get_tile(tile_pos: Vector2i) -> DungeonTile:
	if tile_pos.x >= 0 and tile_pos.x < tile_count_x and tile_pos.y >= 0 and tile_pos.y < tile_count_y:
		return _tiles[_index(tile_pos.x, tile_pos.y)]
	return null


func _set_tile_type(tile_pos: Vector2i, type: DungeonTypes.TileType) -> void:
	_get_tile(tile_pos).type = type
