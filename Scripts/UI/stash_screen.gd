class_name StashScreen
extends CanvasLayer
## ОТЛАДОЧНЫЙ экран хранилища в квартире: слева рюкзак, справа хранилище,
## вещи перекладываются в обе стороны по 1 шт. или всей ячейкой (сколько
## влезет; прочность сохраняется, стаки докладываются). Создаётся InventoryScreen'ом, открывается
## из диалога шкафа:  do InventoryScreen.open_stash()  (диалог ждёт закрытия).
## Логика — Inventory.transfer_slot / discard_slot, здесь только показ и ввод.
## Esc — закрыть. Пока открыт, забирает всю клавиатуру.

signal closed

const COLOR_SELECTED := Color(1.0, 0.85, 0.3)

var _is_open: bool = false
## Что выбрано: в каком инвентаре и какая ячейка.
var _sel_in_stash: bool = false
var _sel_index: int = -1

var _root: Control
var _title: Label
var _backpack_grid: GridContainer
var _stash_grid: GridContainer
var _description: Label
var _status: Label
var _btn_move_one: Button
var _btn_move_all: Button
var _btn_discard: Button


func _ready() -> void:
	layer = 11
	_build_ui()
	_root.visible = false
	PlayerState.backpack.changed.connect(_refresh)
	PlayerState.stash.changed.connect(_refresh)


func is_open() -> bool:
	return _is_open


func open() -> void:
	_is_open = true
	_sel_index = -1
	_status.text = ""
	_root.visible = true
	_refresh()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		close()


# ====================== ДЕЙСТВИЯ ======================

func _on_slot_pressed(in_stash: bool, index: int) -> void:
	var inv := _inv(in_stash)
	if inv.is_slot_empty(index):
		_sel_index = -1
	else:
		_sel_in_stash = in_stash
		_sel_index = index
	_status.text = ""
	_refresh()


func _on_move_pressed(all: bool) -> void:
	var from := _inv(_sel_in_stash)
	var to := _inv(not _sel_in_stash)
	var item := from.get_slot_item(_sel_index)
	if item == null:
		return
	var moved := from.transfer_amount(_sel_index, to, 9999 if all else 1)
	if moved > 0:
		_status.text = "%s: %s x%d" % ["Взято в рюкзак" if _sel_in_stash else "Убрано в хранилище", item.display_name, moved]
	else:
		_status.text = "Не помещается: %s." % ("рюкзак полон" if _sel_in_stash else "хранилище полно")
	_refresh()


func _on_discard_pressed() -> void:
	var inv := _inv(_sel_in_stash)
	var item := inv.get_slot_item(_sel_index)
	if item == null:
		return
	if inv.discard_slot(_sel_index):
		_status.text = "Выброшено: %s" % item.display_name
		_sel_index = -1
	else:
		_status.text = "Это выбросить нельзя."
	_refresh()


func _inv(in_stash: bool) -> Inventory:
	return PlayerState.stash if in_stash else PlayerState.backpack


# ====================== ОТРИСОВКА ======================

func _refresh() -> void:
	if not _is_open:
		return
	if _sel_index >= 0 and _inv(_sel_in_stash).is_slot_empty(_sel_index):
		_sel_index = -1  # ячейка опустела во время операции

	var bp: Inventory = PlayerState.backpack
	var st: Inventory = PlayerState.stash
	_title.text = "Хранилище в квартире   ·   рюкзак %d/%d   ·   хранилище %d/%d" % [
		bp.get_capacity() - bp.get_free_slot_count(), bp.get_capacity(),
		st.get_capacity() - st.get_free_slot_count(), st.get_capacity()]

	_fill_grid(_backpack_grid, bp, false, Vector2(140, 56))
	_fill_grid(_stash_grid, st, true, Vector2(96, 48))

	var item: ItemData = null
	if _sel_index >= 0:
		item = _inv(_sel_in_stash).get_slot_item(_sel_index)
	_description.text = "" if item == null else "%s\n%s" % [item.display_name, item.description]

	var where := "в рюкзак" if _sel_in_stash else "в хранилище"
	var can_move := item != null and _inv(not _sel_in_stash).space_for(item.item_id) > 0
	if item != null and item.has_durability():
		can_move = _inv(not _sel_in_stash).get_free_slot_count() > 0
	_btn_move_one.text = "1 шт. %s" % where
	_btn_move_all.text = "Всё %s" % where
	_btn_move_one.disabled = not can_move
	_btn_move_all.disabled = not can_move
	_btn_discard.disabled = item == null or not _inv(_sel_in_stash).can_discard(_sel_index)


func _fill_grid(grid: GridContainer, inv: Inventory, in_stash: bool, slot_size: Vector2) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in range(inv.get_capacity()):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = slot_size
		button.text = _slot_text(inv, i)
		if _sel_index == i and _sel_in_stash == in_stash:
			button.modulate = COLOR_SELECTED
		button.pressed.connect(_on_slot_pressed.bind(in_stash, i))
		grid.add_child(button)


func _slot_text(inv: Inventory, index: int) -> String:
	var item := inv.get_slot_item(index)
	if item == null:
		return "—"
	var detail := ""
	if item.has_durability():
		detail = "прочн. %d/%d" % [inv.get_slot_durability(index), item.max_durability]
	elif item.get_stack_limit() > 1:
		detail = "x%d" % inv.get_slot_count(index)
	if item.is_key_item:
		detail = ("%s  [ключ]" % detail).strip_edges()
	return "%s\n%s" % [item.display_name, detail]


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_title = Label.new()
	vbox.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	vbox.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	var backpack_label := Label.new()
	backpack_label.text = "Рюкзак"
	left.add_child(backpack_label)
	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 2
	left.add_child(_backpack_grid)

	var right := VBoxContainer.new()
	columns.add_child(right)
	var stash_label := Label.new()
	stash_label.text = "Хранилище"
	right.add_child(stash_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(6 * 100, 5 * 52)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_stash_grid = GridContainer.new()
	_stash_grid.columns = 6
	scroll.add_child(_stash_grid)

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(900, 52)
	vbox.add_child(_description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	_btn_move_one = _make_button(actions, "1 шт. в хранилище", _on_move_pressed.bind(false))
	_btn_move_all = _make_button(actions, "Всё в хранилище", _on_move_pressed.bind(true))
	_btn_discard = _make_button(actions, "Выбросить", _on_discard_pressed)
	_make_button(actions, "Закрыть", close)

	_status = Label.new()
	_status.modulate = Color(1.0, 0.9, 0.5)
	vbox.add_child(_status)

	var hint := Label.new()
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.text = "Выбери ячейку слева или справа  ·  «Всё» — сколько влезет  ·  Esc — закрыть"
	vbox.add_child(hint)


func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
