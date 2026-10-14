class_name BedSaveScreen
extends CanvasLayer
## Только загрузка. Сохранения в этом меню нет — оно выполняется сном.
var manager: BedSaveManager
var _shortcut: Button
var _root: Control
var _panel: PanelContainer
var _details: Label
var _confirm: Button
var _cancel: Button
var _open: bool = false
var _poll: float = 0.0


func _ready() -> void:
	layer = 70
	_shortcut = Button.new()
	_shortcut.text = "F9 · Загрузить"
	_shortcut.focus_mode = Control.FOCUS_NONE
	_shortcut.tooltip_text = "Вернуться к последнему сохранению после сна. Сохраниться можно только в кровати."
	_shortcut.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_shortcut.position = Vector2(-176, 8)
	_shortcut.size = Vector2(164, 36)
	_shortcut.pressed.connect(open)
	add_child(_shortcut)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("141e2b")
	style.border_color = Color("526c89")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20; style.content_margin_right = 20
	style.content_margin_top = 18; style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "Загрузка после сна"
	title.add_theme_font_size_override("font_size", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 17)
	column.add_child(_details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_confirm = Button.new(); _confirm.text = "Загрузить"
	_cancel = Button.new(); _cancel.text = "Отмена"
	for button in [_confirm, _cancel]:
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		buttons.add_child(button)
	_confirm.pressed.connect(_load)
	_cancel.pressed.connect(close)
	_root.visible = false
	_shortcut.visible = false


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.2:
		_poll = 0.0
		_shortcut.visible = manager.is_playable() and not _open
		_shortcut.disabled = manager.is_blocked()
	if _open:
		var viewport_size := get_viewport().get_visible_rect().size
		_panel.size.x = minf(520, maxf(240, viewport_size.x - 32))
		_panel.size.y = 0 # пересчитать высоту под перенос текста
		_panel.position = (viewport_size - _panel.size) / 2


func open() -> void:
	if _open or not manager.is_playable() or manager.is_blocked(): return
	_open = true
	add_to_group("save_load_menu")
	_root.visible = true
	_shortcut.visible = false
	var result := manager.inspect_slot()
	_confirm.disabled = not result.ok
	if not result.ok:
		_details.text = result.error + "\n\nСохранение создаётся только после сна в кровати квартиры."
	else:
		var day := int(result.state.minutes) / GameClock.MINUTES_PER_DAY + 1
		var hour := int(result.state.minutes) % GameClock.MINUTES_PER_DAY / 60
		var minute := int(result.state.minutes) % 60
		_details.text = "День %d · %02d:%02d\nУровень %d · Деньги %d\n\nТы окажешься в квартире после пробуждения. Весь несохранённый прогресс будет потерян.\n\nСохраниться можно только во время сна." % [day, hour, minute, result.state.stats.level, result.state.money]
		if result.recovered: _details.text += "\n\nДоступна восстановленная запись после прерванной записи файла."


func close() -> void:
	if manager.loading: return
	_open = false
	if is_in_group("save_load_menu"): remove_from_group("save_load_menu")
	_root.visible = false


func _load() -> void:
	if not _open or _confirm.disabled or manager.loading: return
	_confirm.disabled = true; _cancel.disabled = true
	var result := await manager.load_checkpoint()
	_cancel.disabled = false
	if result.ok:
		close()
	else:
		_details.text = result.error + "\n\nТекущий прогресс не изменён. Закрой окно и проверь сохранение."


func _input(event: InputEvent) -> void:
	if _open:
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
			if event.pressed and not event.echo:
				match event.keycode:
					KEY_ESCAPE, KEY_F9: close()
					KEY_ENTER, KEY_KP_ENTER: _load()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9 and manager.is_playable() and not manager.is_blocked():
		get_viewport().set_input_as_handled()
		open()
