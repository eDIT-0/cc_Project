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

@export var run: DungeonRun

var _rect: TextureRect
var _placeholder: ColorRect
var _label: Label


func _ready() -> void:
	layer = -1
	_build_ui()
	if run == null:
		push_error("MazeBackground: поле Run не назначено в инспекторе!")
		return
	run.run_started.connect(_refresh)
	run.player_moved.connect(func(_tile): _refresh())
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
