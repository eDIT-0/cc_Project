class_name TradeScreen
extends CanvasLayer
## ОТЛАДОЧНЫЙ экран торговли — как и InventoryScreen, строится из кода и
## потом заменяется нормальным UI. Создаётся и открывается TradeManager'ом,
## вся логика (цены, покупка, продажа) — там, здесь только показ и ввод.
##
## Слева — товары торговца, справа — рюкзак (продажа). Выбрал товар —
## "Купить 1" / "Купить всё"; выбрал ячейку рюкзака — "Продать 1" /
## "Продать всё". Пока экран открыт, забирает всю клавиатуру; Esc — уйти.

signal closed

const COLOR_SELECTED := Color(1.0, 0.85, 0.3)
const COLOR_DISABLED := Color(1, 1, 1, 0.45)

var _merchant: MerchantData = null
var _is_open: bool = false
var _sel_offer: int = -1
var _sel_slot: int = -1

var _root: Control
var _title: Label
var _offers_box: VBoxContainer
var _backpack_grid: GridContainer
var _description: Label
var _status: Label
var _btn_buy_one: Button
var _btn_buy_all: Button
var _btn_sell_one: Button
var _btn_sell_all: Button


func _ready() -> void:
	layer = 11  # поверх InventoryScreen
	_build_ui()
	_root.visible = false
	PlayerState.backpack.changed.connect(_refresh)
	PlayerState.money_changed.connect(func(_amount): _refresh())


func is_open() -> bool:
	return _is_open


func open(merchant: MerchantData) -> void:
	_merchant = merchant
	_is_open = true
	_sel_offer = -1
	_sel_slot = -1
	_status.text = ""
	_root.visible = true
	_refresh()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_merchant = null
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		close()


# ====================== ДЕЙСТВИЯ ======================

func _on_offer_pressed(index: int) -> void:
	_sel_offer = index
	_sel_slot = -1
	_status.text = ""
	_refresh()


func _on_slot_pressed(index: int) -> void:
	_sel_slot = -1 if PlayerState.backpack.is_slot_empty(index) else index
	_sel_offer = -1
	_status.text = ""
	_refresh()


func _on_buy(all: bool) -> void:
	var result := TradeManager.buy(_merchant, _sel_offer, 9999 if all else 1)
	_status.text = result.message
	if _sel_offer >= TradeManager.get_stock(_merchant).size():
		_sel_offer = -1  # стак раскупили — строка исчезла
	_refresh()


func _on_sell(all: bool) -> void:
	var result := TradeManager.sell(_merchant, _sel_slot, 9999 if all else 1)
	_status.text = result.message
	if PlayerState.backpack.is_slot_empty(_sel_slot):
		_sel_slot = -1
	_refresh()


# ====================== ОТРИСОВКА ======================

func _refresh() -> void:
	if not _is_open:
		return
	var catalog := PlayerState.catalog
	var inv: Inventory = PlayerState.backpack
	var stock := TradeManager.get_stock(_merchant)

	# Выбор мог устареть прямо во время операции: inventory.changed
	# перерисовывает экран, когда ячейка уже опустела, а стак уже раскуплен.
	if _sel_slot >= 0 and inv.is_slot_empty(_sel_slot):
		_sel_slot = -1
	if _sel_offer >= stock.size():
		_sel_offer = -1

	_title.text = "%s   ·   Деньги: %d   ·   %s" % [
		_merchant.display_name, PlayerState.money,
		"лабиринт" if PlayerState.in_dungeon else "хаб (не влезло в рюкзак — доставка в квартиру)",
	]

	# --- товары ---
	for child in _offers_box.get_children():
		_offers_box.remove_child(child)
		child.queue_free()
	if stock.is_empty():
		var empty := Label.new()
		empty.text = "Всё раскуплено."
		_offers_box.add_child(empty)
	for i in range(stock.size()):
		var item := catalog.get_item(stock[i].item_id)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(300, 0)
		var amount: String = "x%d  " % stock[i].count if stock[i].count > 1 else ""
		button.text = "%s  %s— %d" % [item.display_name, amount, TradeManager.get_buy_price(_merchant, item)]
		if stock[i].count > 1:
			button.text += " за шт."
		if i == _sel_offer:
			button.modulate = COLOR_SELECTED
		elif TradeManager.get_buy_block_reason(_merchant, i) != "":
			button.modulate = COLOR_DISABLED
		button.pressed.connect(_on_offer_pressed.bind(i))
		_offers_box.add_child(button)

	# --- рюкзак ---
	for child in _backpack_grid.get_children():
		_backpack_grid.remove_child(child)
		child.queue_free()
	for i in range(inv.get_capacity()):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(150, 56)
		button.text = _slot_text(inv, i)
		if i == _sel_slot:
			button.modulate = COLOR_SELECTED
		button.pressed.connect(_on_slot_pressed.bind(i))
		_backpack_grid.add_child(button)

	# --- описание и кнопки ---
	_description.text = ""
	var can_buy := false
	var can_sell := false
	if _sel_offer >= 0:
		var item := catalog.get_item(stock[_sel_offer].item_id)
		var reason := TradeManager.get_buy_block_reason(_merchant, _sel_offer)
		_description.text = "%s\n%s%s" % [item.display_name, item.description, "" if reason == "" else "\n" + reason]
		can_buy = reason == ""
	elif _sel_slot >= 0:
		var item := inv.get_slot_item(_sel_slot)
		var price := TradeManager.get_sell_price(_merchant, _sel_slot)
		var note: String = "Торговец даст: %d за шт." % price if price > 0 else ("Ключевой предмет — не продаётся." if item.is_key_item else "Торговцу это не нужно.")
		_description.text = "%s\n%s\n%s" % [item.display_name, item.description, note]
		can_sell = price > 0

	_btn_buy_one.disabled = not can_buy
	_btn_buy_all.disabled = not can_buy
	_btn_sell_one.disabled = not can_sell
	_btn_sell_all.disabled = not can_sell


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
	panel.custom_minimum_size = Vector2(700, 0)
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
	var offers_label := Label.new()
	offers_label.text = "Товары"
	left.add_child(offers_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_offers_box = VBoxContainer.new()
	scroll.add_child(_offers_box)

	var right := VBoxContainer.new()
	columns.add_child(right)
	var backpack_label := Label.new()
	backpack_label.text = "Рюкзак (продажа)"
	right.add_child(backpack_label)
	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 2
	right.add_child(_backpack_grid)

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(660, 70)
	vbox.add_child(_description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	_btn_buy_one = _make_button(actions, "Купить 1", _on_buy.bind(false))
	_btn_buy_all = _make_button(actions, "Купить всё", _on_buy.bind(true))
	_btn_sell_one = _make_button(actions, "Продать 1", _on_sell.bind(false))
	_btn_sell_all = _make_button(actions, "Продать всё", _on_sell.bind(true))
	_make_button(actions, "Уйти", close)

	_status = Label.new()
	_status.modulate = Color(1.0, 0.9, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(660, 0)
	vbox.add_child(_status)

	var hint := Label.new()
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.text = "«Купить всё» — сколько хватит денег и места  ·  Esc — уйти"
	vbox.add_child(hint)


func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
