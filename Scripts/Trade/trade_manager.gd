extends Node
## Автозагрузка "TradeManager" (Project Settings -> Autoload, ПОСЛЕ PlayerState
## и InventoryScreen). Логика торговли: ассортимент торговцев, цены, покупка
## и продажа. Экран (TradeScreen) создаёт сам, отдельной автозагрузки не нужно.
##
## Из диалога:
##   do TradeManager.open(merchant)          — открыть торговлю и ЖДАТЬ закрытия
##   do TradeManager.set_price_factor("wanderer", 1.2)  — сюжет влияет на цены
##
## Правила (обсуждённые):
##   - каждый товар — один полный стак; раскупили — пусто до перебора;
##   - лабиринт: ассортимент разыгрывается заново каждый забег
##     (MerchantData.restock_each_run), хаб — заново каждый игровой день;
##   - покупка: в рюкзак; не влезло — в хабе доставка в квартиру, в лабиринте
##     нельзя (сначала освободи место);
##   - продажа: только из рюкзака, за sell_ratio от base_price × сюжетный
##     множитель (изношенное —
##     пропорционально прочности), ключевые не продаются; проданное
##     в ассортимент торговца НЕ попадает (никакого выкупа обратно).

## Ассортимент: merchant_id -> Array[Dictionary] { "item_id", "count" }.
## Живёт, пока идёт игра (сохранений пока нет).
var _stocks: Dictionary = {}
## Кого перебирать в начале забега: merchant_id -> true.
var _restock_each_run_ids: Dictionary = {}
## Сюжетные множители цен: merchant_id -> float (по умолчанию 1.0).
var _price_factors: Dictionary = {}

var _screen: TradeScreen


func _ready() -> void:
	_screen = TradeScreen.new()
	add_child(_screen)
	PlayerState.clock.day_changed.connect(_on_day_changed)


# ====================== ОТКРЫТИЕ ======================

## Открыть экран торговли и дождаться, пока игрок уйдёт. Корутина — в
## диалоге обычный do (Dialogue Manager дождётся), в коде — await.
func open(merchant: MerchantData) -> void:
	if merchant == null:
		push_error("TradeManager.open: merchant не передан (в диалог не попал {\"merchant\": ...}?).")
		return
	if _screen.is_open():
		return
	_screen.open(merchant)
	await _screen.closed


func is_open() -> bool:
	return _screen.is_open()


# ====================== АССОРТИМЕНТ ======================

## Текущий товар торговца (разыгрывается при первом обращении).
## Возвращается живой массив — менять только через buy().
func get_stock(merchant: MerchantData) -> Array:
	var id := merchant.get_id()
	if not _stocks.has(id):
		_stocks[id] = _roll_stock(merchant)
		if merchant.restock_each_run:
			_restock_each_run_ids[id] = true
	return _stocks[id]


## Сбросить ассортимент — при следующем открытии разыграется заново.
func restock(merchant: MerchantData) -> void:
	_stocks.erase(merchant.get_id())


## Новый игровой день: торговцы хаба (не restock_each_run) перебирают товар.
## Торговцев лабиринта не трогаем — у них свой цикл, по забегам (иначе
## ночёвка посреди забега перетасовала бы уже встреченного торговца).
## TODO: ассортимент побольше (~10 позиций) с весом по редкости.
func _on_day_changed(_day: int) -> void:
	for id in _stocks.keys():
		if not _restock_each_run_ids.has(id):
			_stocks.erase(id)


## Начало забега (зовёт DungeonRun): торговцы лабиринта перебирают товар.
func on_run_started() -> void:
	for id in _restock_each_run_ids:
		_stocks.erase(id)
	_restock_each_run_ids.clear()


func _roll_stock(merchant: MerchantData) -> Array:
	var pool: Array[ItemData] = []
	for item in merchant.stock_pool:
		if item != null and not pool.has(item):
			pool.append(item)
	if merchant.offers_count > 0 and merchant.offers_count < pool.size():
		pool.shuffle()
		pool.resize(merchant.offers_count)

	var stock: Array = []
	for item in pool:
		stock.append({ "item_id": item.item_id, "count": item.get_stack_limit() })
	return stock


# ====================== ЦЕНЫ ======================

func set_price_factor(merchant_id: String, factor: float) -> void:
	_price_factors[merchant_id] = maxf(0.0, factor)


func get_price_factor(merchant_id: String) -> float:
	return _price_factors.get(merchant_id, 1.0)


## Цена покупки одной штуки. 0 — не продаётся (base_price не задан).
func get_buy_price(merchant: MerchantData, item: ItemData) -> int:
	if item == null or item.base_price <= 0:
		return 0
	var price := item.base_price * merchant.price_multiplier * get_price_factor(merchant.get_id())
	return maxi(1, roundi(price))


## Сколько торговец даст за одну штуку из ячейки рюкзака. 0 — не купит.
## Сюжетный множитель влияет и сюда: поднял торговец цены — и скупает дороже.
func get_sell_price(merchant: MerchantData, slot_index: int) -> int:
	var inv: Inventory = PlayerState.backpack
	var item := inv.get_slot_item(slot_index)
	if item == null or item.is_key_item or item.base_price <= 0:
		return 0
	var ratio := 1.0
	if item.has_durability():
		ratio = float(inv.get_slot_durability(slot_index)) / item.max_durability
	return floori(item.base_price * merchant.sell_ratio * get_price_factor(merchant.get_id()) * ratio)


# ====================== ПОКУПКА ======================

## Сколько штук товара можно купить прямо сейчас (деньги, остаток стака,
## место: рюкзак, а в хабе — ещё и квартира). wanted — сколько хотим.
func get_max_buy(merchant: MerchantData, offer_index: int, wanted: int) -> int:
	var offer := _get_offer(merchant, offer_index)
	if offer.is_empty():
		return 0
	var item := PlayerState.catalog.get_item(offer.item_id)
	var price := get_buy_price(merchant, item)
	if price <= 0:
		return 0
	var amount := mini(wanted, offer.count)
	amount = mini(amount, PlayerState.money / price)
	var space: int = PlayerState.backpack.space_for(offer.item_id)
	if not PlayerState.in_dungeon:
		space = maxi(space, PlayerState.stash.space_for(offer.item_id))
	return mini(amount, space)


## Почему нельзя купить (для подсказки на экране). "" — можно.
func get_buy_block_reason(merchant: MerchantData, offer_index: int) -> String:
	var offer := _get_offer(merchant, offer_index)
	if offer.is_empty():
		return "Этого уже нет."
	var item := PlayerState.catalog.get_item(offer.item_id)
	var price := get_buy_price(merchant, item)
	if price <= 0:
		return "Не продаётся."
	if PlayerState.money < price:
		return "Не хватает денег."
	if get_max_buy(merchant, offer_index, 1) == 0:
		if PlayerState.in_dungeon:
			return "Рюкзак полон — освободи место (продай что-нибудь)."
		return "Некуда положить — полны и рюкзак, и квартира."
	return ""


## Купить amount штук (сколько получится, но не больше). Всё куплено
## одним заходом идёт в одно место: рюкзак, а если не влезло (только хаб) —
## квартира. Возвращает { "ok": bool, "message": String }.
func buy(merchant: MerchantData, offer_index: int, amount: int) -> Dictionary:
	var count := get_max_buy(merchant, offer_index, amount)
	if count <= 0:
		return { "ok": false, "message": get_buy_block_reason(merchant, offer_index) }

	var stock := get_stock(merchant)
	var offer: Dictionary = stock[offer_index]
	var item := PlayerState.catalog.get_item(offer.item_id)
	var total := get_buy_price(merchant, item) * count

	var to_home := PlayerState.backpack.space_for(offer.item_id) < count
	var target: Inventory = PlayerState.stash if to_home else PlayerState.backpack
	if not PlayerState.spend_money(total):
		return { "ok": false, "message": "Не хватает денег." }
	target.add(offer.item_id, count)

	offer.count -= count
	if offer.count <= 0:
		stock.remove_at(offer_index)

	var message := "Куплено: %s x%d за %d." % [item.display_name, count, total]
	if to_home:
		message += " В рюкзак не влезло — доставят в квартиру."
	print("🛒 ", message)
	return { "ok": true, "message": message }


# ====================== ПРОДАЖА ======================

## Продать amount штук из ячейки рюкзака (не больше, чем там есть).
func sell(merchant: MerchantData, slot_index: int, amount: int) -> Dictionary:
	var inv: Inventory = PlayerState.backpack
	var item := inv.get_slot_item(slot_index)
	if item == null:
		return { "ok": false, "message": "Ячейка пуста." }
	if item.is_key_item:
		return { "ok": false, "message": "Это не продаётся." }
	var price := get_sell_price(merchant, slot_index)
	if price <= 0:
		return { "ok": false, "message": "Торговцу это не нужно." }

	var sold := inv.remove_from_slot(slot_index, mini(amount, inv.get_slot_count(slot_index)))
	var total := price * sold
	PlayerState.add_money(total)
	var message := "Продано: %s x%d за %d." % [item.display_name, sold, total]
	print("🛒 ", message)
	return { "ok": true, "message": message }


func _get_offer(merchant: MerchantData, offer_index: int) -> Dictionary:
	var stock := get_stock(merchant)
	if offer_index < 0 or offer_index >= stock.size():
		return {}
	return stock[offer_index]
