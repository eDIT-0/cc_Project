class_name CombatDefenseScreen
extends CanvasLayer
## Отдельный модальный экран защиты. Не портрет/анимационный обработчик.
## Создаётся CombatController автоматически, без новых сцен и автозагрузок.

var combat
var _root: Control
var _panel: PanelContainer
var _title: Label
var _hint: Label
var _timer: Label
var _track: Control
var _partial: ColorRect
var _perfect: ColorRect
var _cursor: ColorRect
var _mash_bar: ProgressBar
var _action: Button


func _ready() -> void:
	layer = 40
	_build_ui()
	combat.changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if combat == null or not combat.is_defending() or not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_SPACE:
		combat.defense_press()
	elif key == KEY_ESCAPE:
		# Не бесплатная отмена атаки: отказаться от защиты = полный провал.
		combat.defense_fail()


func _refresh() -> void:
	if _root == null or combat == null:
		return
	var game: CombatDefense = combat.defense
	var feedback: bool = combat.has_defense_feedback()
	_root.visible = game != null and (combat.is_defending() or feedback)
	if not _root.visible:
		return
	_panel.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x - 32.0, 260.0, 480.0)
	_title.text = combat.defense_title
	_timer.text = "Осталось %.1f с" % game.get_time_left()
	_action.disabled = not game.is_armed()
	_track.visible = game.kind == CombatDefense.Kind.STOP_BAR
	_mash_bar.visible = game.kind == CombatDefense.Kind.MASH
	if game.kind == CombatDefense.Kind.STOP_BAR:
		_hint.text = "Останови полосу пробелом, кликом или касанием.\nЗелёная зона — идеально, жёлтая — частично."
		_action.text = "Остановить · пробел / тап"
		_partial.anchor_left = game.center - game.partial_width / 2.0
		_partial.anchor_right = game.center + game.partial_width / 2.0
		_perfect.anchor_left = game.center - game.perfect_width / 2.0
		_perfect.anchor_right = game.center + game.perfect_width / 2.0
		_cursor.anchor_left = game.cursor
		_cursor.anchor_right = game.cursor
	else:
		_hint.text = "Нажимай пробел или кнопку отдельными нажатиями.\nУдержание клавиши не считается; Esc — принять атаку."
		_action.text = "Нажимай — %d / %d" % [game.presses, game.goal]
		_mash_bar.max_value = game.goal
		_mash_bar.value = game.presses
		_timer.text += " · частично от %d нажатий" % game.partial_goal
	if feedback:
		_hint.text = combat.last_defense_text
		_timer.text = "Бой продолжится после исполнения действия."
		_action.text = "Защита завершена"
		_action.disabled = true
	elif not game.is_armed():
		_timer.text = "Приготовься…"


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = _label("")
	column.add_child(_title)
	_hint = _label("")
	column.add_child(_hint)
	_track = Control.new()
	_track.custom_minimum_size = Vector2(0, 42)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_track)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.16, 0.18, 0.22)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(background)
	_partial = _zone(Color(0.9, 0.65, 0.18))
	_perfect = _zone(Color(0.25, 0.8, 0.35))
	_cursor = _zone(Color.WHITE)
	_cursor.offset_left = -2
	_cursor.offset_right = 2
	_mash_bar = ProgressBar.new()
	_mash_bar.custom_minimum_size = Vector2(0, 32)
	_mash_bar.show_percentage = false
	_mash_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_mash_bar)
	_timer = _label("")
	column.add_child(_timer)
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_action.custom_minimum_size.y = 48
	_action.pressed.connect(func(): combat.defense_press())
	_action.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			combat.defense_press()
			_action.accept_event()
	)
	column.add_child(_action)


func _zone(color: Color) -> ColorRect:
	var zone := ColorRect.new()
	zone.color = color
	zone.anchor_bottom = 1.0
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(zone)
	return zone


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
