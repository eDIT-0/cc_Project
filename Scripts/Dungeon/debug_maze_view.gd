class_name DebugMazeView
extends Node2D
## ВРЕМЕННЫЙ отладочный рендер. Не финальная система показа сцены —
## та будет построена под макет (статичная картинка + миникарта, см.
## обсуждение VN-подхода). Этот скрипт — просто чтобы глазами увидеть,
## что генератор реально что-то строит, пока макет не готов.
##
## Теперь это ТОЛЬКО вид: рисует карту и переводит WASD в DungeonRun.try_step().
## Все правила и состояние забега (позиция игрока, ивенты, квесты, торговец,
## "дыра в стене", выход) живут в DungeonRun — новый экран вместо этого
## узла должен повторить только то, что есть здесь: подписаться на сигналы
## DungeonRun, рисовать и звать try_step().
## Фон от первого лица рисует отдельный узел — MazeBackground.
##
## Управление — относительно взгляда: W вперёд, A налево, D направо,
## S назад (каждое — шаг; после шага смотришь туда, куда шёл).
## На карте взгляд — тёмный треугольник на квадрате игрока.
## Tab — показать/скрыть расстояние от старта по коридорам в каждой комнате.

@export var generator: DungeonGenerator  ## Только для чтения тайлов при отрисовке
@export var run: DungeonRun
@export var tile_size: int = 24
## Отладка: числа поверх комнат — длина пути от старта (переключается Tab).
@export var show_room_distances: bool = false

@onready var _dialogue_box: DialogueBox = %DialogueBox


func _ready() -> void:
	if generator == null or run == null:
		push_error("DebugMazeView: поля Generator и/или Run не назначены в инспекторе!")
		return

	run.run_started.connect(queue_redraw)
	run.map_changed.connect(queue_redraw)
	run.player_moved.connect(func(_tile): queue_redraw())
	# Показ диалогов — забота вида: DungeonRun только просит, а какой
	# DialogueBox (или вообще другой UI) его покажет, решается здесь.
	run.dialogue_requested.connect(_dialogue_box.play)
	_dialogue_box.finished.connect(run.on_dialogue_finished)


func _draw() -> void:
	if generator == null or run == null or not generator.is_generated:
		return

	for x in range(generator.tile_count_x):
		for y in range(generator.tile_count_y):
			var tile := generator.get_tile(Vector2i(x, y))
			if tile == null:
				continue
			var rect := Rect2(x * tile_size, y * tile_size, tile_size - 1, tile_size - 1)
			draw_rect(rect, _color_for_tile(tile))

	if show_room_distances:
		_draw_room_distances()

	# Игрок — белый квадрат поверх текущего тайла
	var player_tile := run.get_player_tile()
	var player_rect := Rect2(
		player_tile.x * tile_size + 4, player_tile.y * tile_size + 4,
		tile_size - 8, tile_size - 8
	)
	draw_rect(player_rect, Color.WHITE)
	_draw_facing(player_rect)


## Треугольник-"нос" в сторону взгляда.
func _draw_facing(rect: Rect2) -> void:
	var c := rect.get_center()
	var r := rect.size.x * 0.45
	var forward: Vector2
	match run.get_facing():
		DungeonTypes.Direction.NORTH: forward = Vector2(0, -1)
		DungeonTypes.Direction.EAST: forward = Vector2(1, 0)
		DungeonTypes.Direction.SOUTH: forward = Vector2(0, 1)
		_: forward = Vector2(-1, 0)
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		c + forward * r, c - forward * r * 0.5 + side * r * 0.7, c - forward * r * 0.5 - side * r * 0.7,
	]), Color.BLACK)


func _draw_room_distances() -> void:
	var font := ThemeDB.fallback_font
	var font_size := int(tile_size * 0.5)
	for rx in range(generator.room_count_x):
		for ry in range(generator.room_count_y):
			var d := generator.get_room_distance(Vector2i(rx, ry))
			if d < 0:
				continue
			# Центр комнаты в тайлах — (r * 2 + 1), как DungeonGenerator._room_to_tile
			var tile_pos := Vector2(rx * 2 + 1, ry * 2 + 1) * tile_size
			var baseline := tile_pos + Vector2(0, tile_size * 0.7)
			draw_string(font, baseline, str(d), HORIZONTAL_ALIGNMENT_CENTER, tile_size, font_size, Color.BLACK)


func _color_for_tile(tile: DungeonTile) -> Color:
	if tile.type == DungeonTypes.TileType.WALL:
		return Color(0.12, 0.12, 0.12)

	match tile.event_type:
		DungeonTypes.EventType.ENEMY: return Color.CRIMSON
		DungeonTypes.EventType.REWARD: return Color.GOLD
		DungeonTypes.EventType.QUEST: return Color.MEDIUM_PURPLE
		DungeonTypes.EventType.MERCHANT: return Color.LIME_GREEN
		DungeonTypes.EventType.EXIT: return Color.DEEP_SKY_BLUE
		DungeonTypes.EventType.SIDE_QUEST: return Color.CYAN
		DungeonTypes.EventType.RANDOM_EVENT: return Color.ORANGE
		_: return Color(0.55, 0.55, 0.55)  # Empty и всё остальное


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Отладочный оверлей — работает и при открытом диалоге, ход не тратит
	if event.keycode == KEY_TAB:
		show_room_distances = not show_room_distances
		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if run == null or not run.is_running() or _dialogue_box.is_active() or run.is_in_encounter() or run.is_defeat_in_progress():
		return

	var step: DungeonRun.Step
	match event.keycode:
		KEY_W: step = DungeonRun.Step.FORWARD
		KEY_S: step = DungeonRun.Step.BACK
		KEY_A: step = DungeonRun.Step.LEFT
		KEY_D: step = DungeonRun.Step.RIGHT
		_: return

	run.try_step(step)
