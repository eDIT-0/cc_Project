extends CanvasLayer
## Автозагрузка "InventoryScreen" (Project Settings -> Autoload, ПОСЛЕ PlayerState).
## ОТЛАДОЧНЫЙ экран рюкзака — строится целиком из кода, без макета: нужен,
## чтобы проверять инвентарь в игре, а не только в консоли. Когда будет
## нормальный UI под макет, заменить этот файл; логика всё равно живёт в
## Inventory / PlayerState, здесь только показ и ввод.
##
## Автозагрузка, а не нода в сценах — потому что рюкзак нужен и в хабе, и в
## лабиринте, а автозагрузка переживает смену сцены и не требует правок в них.
##
## Управление:
##   I            — открыть / закрыть (не открывается поверх диалога)
##   1-9          — выбрать ячейку (или цель для "Соединить"/"Переложить";
##                  для "Соединить" можно выбрать ту же ячейку — два
##                  одинаковых предмета из одного стака)
##   мышь         — то же самое + кнопки действий
##   Esc          — отменить "Соединить"/"Переложить", иначе закрыть
## Пока экран открыт, он забирает ВСЮ клавиатуру (в _input, раньше всех
## _unhandled_input) — игрок не ходит, хаб не листается, диалог не жмётся.
##
## Задел под бой: open(true) — режим боя. В нём скрыты "Соединить",
## "Переложить" и "Выбросить", а "Использовать" смотрит на usable_in_combat.
## Стоимость действия в бою — забота будущего боевого контроллера.
##
## ПЕРЕПОЛНЕНИЕ (resolve_overflow, вызывает PlayerState.give_item):
##   "Рюкзак полон — освободи место или оставь находку". Можно выбросить,
##   использовать, соединить; в хабе — отправить в квартиру любую ячейку или
##   саму находку. Как только место появилось — находка ложится в рюкзак
##   сама. Ключевую находку оставить нельзя (защита от софтлока). Закрыть
##   экран (I / Esc / "Закрыть") нельзя, пока вопрос не решён.
##   Экстренный случай: находка ключевая, а освободить место нечем (рюкзак из
##   одних ключевых, а в лабиринте ещё и квартиры нет) — находка уходит прямо
##   в хранилище. Если и хранилище полно — показываем хранилище и просим
##   выбросить что-то ОТТУДА. Если и там одни ключевые — хранилище молча
##   расширяется (практически невозможный случай, только чтобы не сломаться).
##
## Отладка (только в debug-сборке, при открытом экране):
##   F1 — находка «Самогон», F2 — находка «Тестовый ключ»,
##   F3 — переключить хаб/лабиринт, F4 — забить хранилище тканью.

signal _overflow_finished(lost: int)

enum Mode { NORMAL, COMBINE, MOVE }

const COLUMNS := 4
const STASH_COLUMNS := 8
const COLOR_SELECTED := Color(1.0, 0.85, 0.3)
const COLOR_COMBINABLE := Color(0.55, 1.0, 0.55)

var _is_open: bool = false
var _in_combat: bool = false
var _mode: Mode = Mode.NORMAL
var _selected: int = -1

# --- переполнение ---
var _overflow_active: bool = false
var _overflow_item: ItemData = null
var _overflow_left: int = 0           # сколько находки ещё не размещено
var _overflow_opened_screen: bool = false  # экран открыли ради переполнения -> закрыть после
var _stash_view: bool = false         # экстренный режим: показываем хранилище
var _notice: String = ""              # итоговое сообщение, ждёт "Понятно"

var _root: Control
var _title: Label
var _overflow_info: Label
var _grid: GridContainer
var _description: Label
var _status: Label
var _btn_use: Button
var _btn_combine: Button
var _btn_move: Button
var _btn_discard: Button
var _btn_to_stash: Button
var _btn_found_to_stash: Button
var _btn_leave: Button
var _btn_close: Button
var _debug_hint: Label
var _stash_screen: StashScreen


func _ready() -> void:
	layer = 10
	_build_ui()
	_root.visible = false
	_stash_screen = StashScreen.new()
	add_child(_stash_screen)

	if PlayerState == null or PlayerState.backpack == null:
		push_error("InventoryScreen: PlayerState не готов — проверь порядок автозагрузок (PlayerState выше InventoryScreen).")
		return
	PlayerState.backpack.changed.connect(_refresh)
	PlayerState.stash.changed.connect(_refresh)
	PlayerState.money_changed.connect(func(_amount): _refresh())


# ====================== ПУБЛИЧНО ======================

## true и когда открыт экран хранилища — для остальных экранов это тоже
## "инвентарь занят".
func is_open() -> bool:
	return _is_open or (_stash_screen != null and _stash_screen.is_open())


## Экран хранилища в квартире (рюкзак <-> хранилище). Корутина: в диалоге
## обычный  do InventoryScreen.open_stash()  — диалог дождётся закрытия.
func open_stash() -> void:
	if _stash_screen.is_open() or _is_open:
		return
	_stash_screen.open()
	await _stash_screen.closed


func is_resolving_overflow() -> bool:
	return _overflow_active


func open(in_combat: bool = false) -> void:
	_is_open = true
	_in_combat = in_combat
	_mode = Mode.NORMAL
	_selected = -1
	_status.text = ""
	_root.visible = true
	_refresh()


func close() -> void:
	if _overflow_active:
		return  # сначала реши, что делать с находкой
	_is_open = false
	_root.visible = false


## Рюкзак полон: показать экран и дождаться решения игрока.
## Возвращает, сколько находки так и не взято (0 — всё разместилось).
## Вызывать через await (это делает PlayerState.give_item).
func resolve_overflow(item: ItemData, amount: int) -> int:
	while _overflow_active:  # две выдачи подряд без await — по очереди
		await _overflow_finished

	var left := PlayerState.backpack.add(item.item_id, amount)  # вдруг место уже появилось
	if left == 0:
		return 0

	_overflow_active = true
	_overflow_item = item
	_overflow_left = left
	_stash_view = false
	_notice = ""
	_overflow_opened_screen = not _is_open
	if not _is_open:
		open()
	_mode = Mode.NORMAL
	_selected = -1
	_status.text = ""

	if item.is_key_item and not _has_way_out():
		_emergency_store()
	_refresh()

	var lost: int = await _overflow_finished
	return lost


# ====================== ВВОД ======================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if not _is_open:
		if event.keycode == KEY_I and not _is_dialogue_active() and not _stash_screen.is_open():
			get_viewport().set_input_as_handled()
			open()
		return

	get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_I:
			close()
		KEY_ESCAPE:
			if _mode != Mode.NORMAL:
				_mode = Mode.NORMAL
				_status.text = "Отменено."
				_refresh()
			else:
				close()
		KEY_F1, KEY_F2, KEY_F3, KEY_F4:
			if OS.is_debug_build() and not _overflow_active:
				_debug_key(event.keycode)
		_:
			var index: int = event.keycode - KEY_1
			if index >= 0 and index < 9 and index < _view_inv().get_capacity():
				_on_slot_pressed(index)


func _is_dialogue_active() -> bool:
	for box in get_tree().get_nodes_in_group("dialogue_box"):
		if box.has_method("is_active") and box.is_active():
			return true
	return false


func _debug_key(keycode: Key) -> void:
	match keycode:
		KEY_F1:
			PlayerState.give_item("moonshine")  # без await: экран сам переключится
		KEY_F2:
			PlayerState.give_item("debug_key")
		KEY_F3:
			PlayerState.in_dungeon = not PlayerState.in_dungeon
			_status.text = "Отладка: теперь %s." % ("в лабиринте" if PlayerState.in_dungeon else "в хабе")
		KEY_F4:
			var st: Inventory = PlayerState.stash
			st.add("cloth", st.get_capacity() * 999)
			_status.text = "Отладка: хранилище забито тканью."
	_refresh()


# ====================== ДЕЙСТВИЯ ======================

func _on_slot_pressed(index: int) -> void:
	var inv := _view_inv()

	match _mode:
		Mode.NORMAL:
			_selected = -1 if inv.is_slot_empty(index) else index
			_status.text = ""

		Mode.COMBINE:
			if inv.is_slot_empty(index):
				_status.text = "Ячейка пуста."
				_refresh()
				return
			var recipe := inv.get_recipe_for_slots(_selected, index)
			if recipe == null and index == _selected:
				_status.text = "Из одной ячейки соединяются только два одинаковых предмета (нужно 2+ шт. и рецепт)."
			elif recipe == null:
				_status.text = "Эти предметы не соединяются."
			elif inv.combine_slots(_selected, index):
				_status.text = "Получено: %s x%d" % [recipe.result.display_name, recipe.result_count]
				if inv.is_slot_empty(_selected):
					_selected = -1
			else:
				_status.text = "Некуда положить результат — освободи место."
			_mode = Mode.NORMAL

		Mode.MOVE:
			if index != _selected and inv.move_slot(_selected, index):
				_selected = index
				_status.text = ""
			_mode = Mode.NORMAL

	_after_action()


func _on_use_pressed() -> void:
	var inv: Inventory = PlayerState.backpack
	var item := inv.get_slot_item(_selected)
	if item == null:
		return
	if inv.use_slot(_selected, _in_combat):
		_status.text = "Использовано: %s (эффект — в консоли)" % item.display_name
		if inv.is_slot_empty(_selected):
			_selected = -1
	else:
		_status.text = "Не подействовало (сейчас нельзя или не нужно — например, здоровье полное)."
	_after_action()


func _on_combine_pressed() -> void:
	var item := PlayerState.backpack.get_slot_item(_selected)
	if item == null:
		return
	_mode = Mode.COMBINE
	_status.text = "Соединить «%s» с... (выбери предмет, Esc — отмена)" % item.display_name
	_refresh()


func _on_move_pressed() -> void:
	var item := PlayerState.backpack.get_slot_item(_selected)
	if item == null:
		return
	_mode = Mode.MOVE
	_status.text = "Куда переложить «%s»? (Esc — отмена)" % item.display_name
	_refresh()


func _on_discard_pressed() -> void:
	var inv := _view_inv()
	var item := inv.get_slot_item(_selected)
	if item == null:
		return
	if inv.discard_slot(_selected):
		_status.text = "Выброшено: %s" % item.display_name
		_selected = -1
	else:
		_status.text = "Это выбросить нельзя."

	if _stash_view:
		_emergency_store()  # место в хранилище появилось — пробуем ещё раз
		_refresh()
	else:
		_after_action()


## Переполнение, хаб: отправить выбранную ячейку рюкзака в квартиру.
func _on_to_stash_pressed() -> void:
	var item := PlayerState.backpack.get_slot_item(_selected)
	if item == null:
		return
	if PlayerState.backpack.transfer_slot(_selected, PlayerState.stash):
		_status.text = "Отправлено в квартиру: %s" % item.display_name
		_selected = -1
	else:
		_status.text = "В хранилище нет места."
	_after_action()


## Переполнение, хаб: отправить в квартиру саму находку.
func _on_found_to_stash_pressed() -> void:
	_overflow_left = PlayerState.stash.add(_overflow_item.item_id, _overflow_left)
	if _overflow_left == 0:
		print("🏠 Находка отправлена в квартиру: %s" % _overflow_item.display_name)
		_finish_overflow(0)
	else:
		_status.text = "В хранилище влезло не всё."
		_refresh()


## "Оставить находку" (нельзя для ключевых) или "Понятно" после сообщения.
func _on_leave_pressed() -> void:
	if _notice != "":
		_finish_overflow(_overflow_left)
	elif not _overflow_item.is_key_item:
		_finish_overflow(_overflow_left)


## После любого действия в режиме переполнения: если место появилось —
## находка сама ложится в рюкзак.
func _after_action() -> void:
	if _overflow_active and not _stash_view and _notice == "":
		_overflow_left = PlayerState.backpack.add(_overflow_item.item_id, _overflow_left)
		if _overflow_left == 0:
			_finish_overflow(0)
			return
	_refresh()


# ====================== ПЕРЕПОЛНЕНИЕ: ВНУТРЕННЕЕ ======================

func _view_inv() -> Inventory:
	return PlayerState.stash if _stash_view else PlayerState.backpack


## Может ли игрок сам освободить место под находку.
func _has_way_out() -> bool:
	var bp: Inventory = PlayerState.backpack
	if bp.has_discardable_slot():
		return true
	if PlayerState.in_dungeon:
		return false
	var st: Inventory = PlayerState.stash
	if st.can_add(_overflow_item.item_id, 1):
		return true
	for i in range(bp.get_capacity()):
		if bp.can_transfer_slot(i, st):
			return true
	return false


## Экстренно: ключевая находка — прямо в хранилище (см. шапку файла).
func _emergency_store() -> void:
	var st: Inventory = PlayerState.stash
	_overflow_left = st.add(_overflow_item.item_id, _overflow_left)

	if _overflow_left > 0 and not st.has_discardable_slot():
		push_warning("InventoryScreen: и рюкзак, и хранилище забиты ключевыми предметами — расширяю хранилище.")
		st.grow_capacity(st.get_capacity() + _overflow_left)
		_overflow_left = st.add(_overflow_item.item_id, _overflow_left)

	if _overflow_left == 0:
		_stash_view = false
		_selected = -1
		_notice = "Рюкзак забит ключевыми предметами — «%s» отправлен в хранилище в квартире." % _overflow_item.display_name
		_status.text = _notice
		print("🏠 ", _notice)
		return

	_stash_view = true
	_selected = -1
	_status.text = "Рюкзак забит ключевыми предметами, а хранилище переполнено. Выброси что-нибудь из хранилища — «%s» отправится туда." % _overflow_item.display_name


func _finish_overflow(lost: int) -> void:
	_overflow_active = false
	_overflow_item = null
	_overflow_left = 0
	_stash_view = false
	_notice = ""
	_selected = -1
	_mode = Mode.NORMAL
	if _overflow_opened_screen:
		close()
	else:
		_refresh()
	_overflow_finished.emit(lost)


# ====================== ОТРИСОВКА ======================

func _refresh() -> void:
	if not _is_open:
		return
	var inv := _view_inv()
	var capacity := inv.get_capacity()

	if _stash_view:
		_title.text = "Хранилище в квартире — занято %d/%d" % [capacity - inv.get_free_slot_count(), capacity]
	else:
		_title.text = "Рюкзак — занято %d/%d   ·   Деньги: %d%s%s" % [
			capacity - inv.get_free_slot_count(), capacity, PlayerState.money,
			"   ·   БОЙ" if _in_combat else "",
			"   ·   лабиринт" if PlayerState.in_dungeon else "   ·   хаб",
		]

	_overflow_info.visible = _overflow_active
	if _overflow_active:
		_overflow_info.text = _overflow_text()

	_grid.columns = STASH_COLUMNS if _stash_view else COLUMNS
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	for i in range(capacity):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(80, 44) if _stash_view else Vector2(150, 64)
		button.text = _slot_text(inv, i)
		if i == _selected:
			button.modulate = COLOR_SELECTED
		elif _mode == Mode.COMBINE and inv.get_recipe_for_slots(_selected, i) != null:
			button.modulate = COLOR_COMBINABLE
		button.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(button)

	var item: ItemData = inv.get_slot_item(_selected)  # null, если ничего не выбрано
	_description.text = "" if item == null else "%s\n%s" % [item.display_name, item.description]

	var normal := _mode == Mode.NORMAL and _notice == ""
	var usable_here := item != null and (item.usable_in_combat if _in_combat else item.usable_in_field)
	_btn_use.disabled = not (normal and usable_here)
	_btn_combine.disabled = not (normal and item != null)
	_btn_move.disabled = not (normal and item != null)
	_btn_discard.disabled = not (normal and item != null and inv.can_discard(_selected))

	_btn_use.visible = not _stash_view
	_btn_combine.visible = not _in_combat and not _stash_view
	_btn_move.visible = not _in_combat and not _stash_view
	_btn_discard.visible = not _in_combat

	# --- кнопки переполнения ---
	var hub_options := _overflow_active and not PlayerState.in_dungeon and not _stash_view and _notice == ""
	_btn_to_stash.visible = hub_options
	_btn_found_to_stash.visible = hub_options
	_btn_leave.visible = _overflow_active
	_btn_close.visible = not _overflow_active

	if _overflow_active:
		var st: Inventory = PlayerState.stash
		_btn_to_stash.disabled = not (normal and item != null and PlayerState.backpack.can_transfer_slot(_selected, st))
		_btn_found_to_stash.disabled = not (normal and st.can_add(_overflow_item.item_id, 1))
		if _notice != "":
			_btn_leave.text = "Понятно"
			_btn_leave.disabled = false
		else:
			_btn_leave.text = "Оставить находку"
			_btn_leave.disabled = _overflow_item.is_key_item or _stash_view

	_debug_hint.visible = OS.is_debug_build() and not _overflow_active


func _overflow_text() -> String:
	if _notice != "":
		return "Рюкзак полон!"
	var text := "Рюкзак полон!  Находка: «%s» x%d" % [_overflow_item.display_name, _overflow_left]
	if _overflow_item.is_key_item:
		text += "  [ключевой — оставить нельзя]"
	if _stash_view:
		return text
	if PlayerState.in_dungeon:
		text += "\nВыброси, используй или соедини что-нибудь. Выброшенное в лабиринте пропадает навсегда."
	else:
		var st: Inventory = PlayerState.stash
		text += "\nОсвободи место или отправь вещь в квартиру (хранилище %d/%d)." % [
			st.get_capacity() - st.get_free_slot_count(), st.get_capacity()]
	return text


func _slot_text(inv: Inventory, index: int) -> String:
	var item := inv.get_slot_item(index)
	if item == null:
		return "%d. —" % (index + 1)

	var detail := ""
	if item.has_durability():
		detail = "прочн. %d/%d" % [inv.get_slot_durability(index), item.max_durability]
	elif item.get_stack_limit() > 1:
		detail = "x%d" % inv.get_slot_count(index)
	if item.is_key_item:
		detail = ("%s  [ключ]" % detail).strip_edges()
	return "%d. %s\n%s" % [index + 1, item.display_name, detail]


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # клики не проходят в хаб/лабиринт под экраном
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
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

	_overflow_info = Label.new()
	_overflow_info.modulate = Color(1.0, 0.6, 0.5)
	_overflow_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overflow_info.custom_minimum_size = Vector2(640, 0)
	vbox.add_child(_overflow_info)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	vbox.add_child(_grid)

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(_description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	_btn_use = _make_action_button(actions, "Использовать", _on_use_pressed)
	_btn_combine = _make_action_button(actions, "Соединить", _on_combine_pressed)
	_btn_move = _make_action_button(actions, "Переложить", _on_move_pressed)
	_btn_discard = _make_action_button(actions, "Выбросить", _on_discard_pressed)
	_btn_close = _make_action_button(actions, "Закрыть", close)

	var overflow_actions := HBoxContainer.new()
	overflow_actions.add_theme_constant_override("separation", 8)
	vbox.add_child(overflow_actions)
	_btn_to_stash = _make_action_button(overflow_actions, "В квартиру", _on_to_stash_pressed)
	_btn_found_to_stash = _make_action_button(overflow_actions, "Находку — в квартиру", _on_found_to_stash_pressed)
	_btn_leave = _make_action_button(overflow_actions, "Оставить находку", _on_leave_pressed)

	_status = Label.new()
	_status.modulate = Color(1.0, 0.9, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(640, 0)
	vbox.add_child(_status)

	var hint := Label.new()
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.text = "1-9 — ячейка  ·  Esc — отмена / закрыть  ·  I — закрыть"
	vbox.add_child(hint)

	_debug_hint = Label.new()
	_debug_hint.modulate = Color(0.6, 0.8, 1.0, 0.6)
	_debug_hint.text = "Отладка: F1 — найти самогон · F2 — найти тестовый ключ · F3 — хаб/лабиринт · F4 — забить хранилище"
	vbox.add_child(_debug_hint)


func _make_action_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
