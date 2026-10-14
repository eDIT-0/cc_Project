class_name MazeBackground
extends CanvasLayer
## Фон лабиринта "от первого лица": картинка на весь экран, которая
## меняется в зависимости от того, что перед игроком (DungeonRun.get_view_kind)
## и от времени суток (LocationData.get_view_set). Сам UI строит из кода.
##
## В сцене: узел CanvasLayer с этим скриптом, поле Run -> DungeonRun.
## Слой -1 — под картой-миникартой и диалогами.
##
## Нет картинки для этого вида — серый фон и подпись с названием вида
## (удобно, пока арт не нарисован).
##
## Во время встречи на фоне стоят фигуры противников в полный рост
## (EnemyData.figure) — отдельно от вставок событий (pics). Нет картинки —
## силуэт-заглушка с именем.

@export var run: DungeonRun

var _rect: TextureRect
var _placeholder: ColorRect
var _label: Label
var _figures: HBoxContainer


func _ready() -> void:
	layer = -1
	_build_ui()
	if run == null:
		push_error("MazeBackground: поле Run не назначено в инспекторе!")
		return
	run.run_started.connect(_refresh)
	run.player_moved.connect(func(_tile): _refresh())
	run.encounter_started.connect(_show_figures)
	# Временный боевой экран рисует кликабельные копии фигур сам.
	run.combat_started.connect(func(_combat): _figures.hide())
	run.encounter_ended.connect(func(_enc): _clear_figures())
	PlayerState.clock.phase_changed.connect(_on_phase_changed)


func _exit_tree() -> void:
	if PlayerState.clock.phase_changed.is_connected(_on_phase_changed):
		PlayerState.clock.phase_changed.disconnect(_on_phase_changed)


func _on_phase_changed(_phase: GameClock.Phase) -> void:
	_refresh()


func _refresh() -> void:
	if run == null or not run.is_running():
		return
	var kind := run.get_view_kind()
	var location: LocationData = run.generator.location_data
	var view_set: MazeViewSet = location.get_view_set(PlayerState.clock.phase) if location != null else null
	var view: Dictionary = view_set.get_view(kind) if view_set != null else { "texture": null, "flip": false }

	_rect.texture = view.texture
	_rect.flip_h = view.flip
	var missing: bool = view.texture == null
	_placeholder.visible = missing
	_label.visible = missing
	if missing:
		_label.text = "[нет фона] %s · %s" % [DungeonTypes.VIEW_KIND_NAMES[kind], PlayerState.clock.get_phase_name()]


# ====================== ФИГУРЫ ПРОТИВНИКОВ ======================

func _show_figures(encounter: Encounter) -> void:
	_clear_figures()
	_figures.show()
	for enemy in encounter.enemies:
		_figures.add_child(_make_figure(enemy))


func _clear_figures() -> void:
	for child in _figures.get_children():
		child.queue_free()


func _make_figure(enemy: EnemyData) -> Control:
	if enemy.figure != null:
		var rect := TextureRect.new()
		rect.texture = enemy.figure
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rect.custom_minimum_size = Vector2(160, 0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	# Заглушка: тёмный силуэт с именем.
	var box := ColorRect.new()
	box.color = Color(0.08, 0.05, 0.05, 0.85)
	box.custom_minimum_size = Vector2(160, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = enemy.display_name
	label.set_anchors_preset(Control.PRESET_CENTER)
	box.add_child(label)
	return box


func _build_ui() -> void:
	_placeholder = ColorRect.new()
	_placeholder.color = Color(0.2, 0.2, 0.22)
	_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placeholder)

	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 16
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# Фигуры: снизу по центру, в полный рост (до ~85% высоты экрана),
	# стоят "чуть подальше" — не во весь экран.
	_figures = HBoxContainer.new()
	_figures.anchor_left = 0.2
	_figures.anchor_right = 0.85
	_figures.anchor_top = 0.15
	_figures.anchor_bottom = 1.0
	_figures.alignment = BoxContainer.ALIGNMENT_CENTER
	_figures.add_theme_constant_override("separation", 24)
	_figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_figures)
