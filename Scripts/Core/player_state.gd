extends Node
## Автозагружаемый синглтон (Project Settings -> Autoload -> имя "PlayerState").
## Всё, что персонаж носит и копит МЕЖДУ сценами: рюкзак, хранилище в
## квартире, деньги. Позже сюда же лягут здоровье и прочие параметры.
##
## Функции ниже рассчитаны в том числе на вызов из .dialogue-файлов:
##   - Поддеть ломом [if PlayerState.has_item("crowbar")] => pry
##   $> PlayerState.give_item("bandage")
##   $> PlayerState.add_money(25)
##   Денег: {{PlayerState.money}}
##
## Посмотреть рюкзак в игре — отладочный экран InventoryScreen (клавиша I).

signal money_changed(new_amount: int)

const CATALOG_PATH := "res://Data/Items/item_catalog.tres"
## Вместимость — пока константы. Улучшение рюкзака: backpack.grow_capacity().
const BACKPACK_CAPACITY := 8
const STASH_CAPACITY := 48

## Стартовый набор для тестов — выдаётся только в отладочной сборке.
## Чтобы начать с пустыми руками, просто очисти словарь.
## Следи, чтобы набор влезал в рюкзак (BACKPACK_CAPACITY) и оставалась хоть
## одна свободная ячейка — иначе часть крафтов не сработает.
## Сейчас: 7 ячеек из 8 (трава не стакается — 2 ячейки).
const DEBUG_START_ITEMS := {
	"homemade_injector": 2,
	"gunpowder": 2,
	"metal_parts_small": 4,
	"herb_green": 2,
	"moonshine": 1,
	"cloth": 1,
}
const DEBUG_START_MONEY := 100

## Доля денег, теряемая при смерти (0.1 = 10%). Инвентарь и так отбирается,
## поэтому деньги — лишь частично.
const DEATH_MONEY_LOSS := 0.1

var catalog: ItemCatalog
var backpack: Inventory
var stash: Inventory
var money: int = 0
## Где персонаж: в лабиринте или в городе (хабе). Ставит DungeonRun при
## старте забега и снимает при выходе со сцены лабиринта. Влияет на экран
## переполнения: только в хабе можно отправлять вещи в квартиру.
var in_dungeon: bool = false


func _ready() -> void:
	catalog = load(CATALOG_PATH) as ItemCatalog
	if catalog == null:
		push_error("PlayerState: не найден каталог предметов %s — создаю пустой." % CATALOG_PATH)
		catalog = ItemCatalog.new()

	backpack = Inventory.new(catalog, BACKPACK_CAPACITY)
	stash = Inventory.new(catalog, STASH_CAPACITY)

	if OS.is_debug_build():
		for item_id in DEBUG_START_ITEMS:
			backpack.add(item_id, DEBUG_START_ITEMS[item_id])  # без экрана переполнения
		money = DEBUG_START_MONEY


# ====================== ПРЕДМЕТЫ (для кода и диалогов) ======================

func has_item(item_id: String, amount: int = 1) -> bool:
	return backpack.has_item(item_id, amount)


## Положить в рюкзак. Если не влезло — открывается экран переполнения
## (InventoryScreen.resolve_overflow): выбросить / использовать что-то,
## в хабе — отправить в квартиру, или оставить находку (кроме ключевых).
## Возвращает, сколько в итоге НЕ взято (игрок решил оставить находку).
##
## ВАЖНО: это корутина, когда рюкзак полон.
##   Из кода:   var lost := await PlayerState.give_item("ammo_45", 10)
##   В диалоге: do PlayerState.give_item("ammo_45", 10)
##              (обычный do / $> Dialogue Manager сам дождётся экрана;
##               do! / $>> — НЕ ждут, для выдачи предметов не использовать)
func give_item(item_id: String, amount: int = 1) -> int:
	var item := catalog.get_item(item_id)
	if item == null:
		push_error("PlayerState.give_item: неизвестный item_id '%s'." % item_id)
		return amount

	var leftover := backpack.add(item_id, amount)
	if leftover < amount:
		print("🎒 Получено: %s x%d" % [item.display_name, amount - leftover])
	if leftover == 0:
		return 0

	var screen = get_node_or_null("/root/InventoryScreen")  # без типа: метод вызывается динамически
	if screen != null and screen.has_method("resolve_overflow"):
		leftover = await screen.resolve_overflow(item, leftover)
	elif item.is_key_item:
		# Без экрана (тесты, другая сцена) — ключевой хотя бы не теряется.
		leftover = stash.add(item_id, leftover)
		print("🎒 Рюкзак полон — «%s» отправлен в хранилище." % item.display_name)

	if leftover > 0:
		print("🎒 Оставлено на месте: %s x%d" % [item.display_name, leftover])
	return leftover


## Забрать из рюкзака. Всё или ничего.
func take_item(item_id: String, amount: int = 1) -> bool:
	return backpack.remove(item_id, amount)


# ====================== ДЕНЬГИ ======================

func has_money(amount: int) -> bool:
	return money >= amount


func add_money(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	print("💰 +%d (всего %d)" % [amount, money])
	money_changed.emit(money)


## Потратить — только если хватает (покупка). Всё или ничего.
func spend_money(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	print("💰 -%d (всего %d)" % [amount, money])
	money_changed.emit(money)
	return true


## Отобрать "сколько есть, но не больше amount" (грабёж, штраф).
## Возвращает, сколько реально забрали.
func lose_money(amount: int) -> int:
	var lost := clampi(amount, 0, money)
	if lost > 0:
		money -= lost
		print("💰 -%d (всего %d)" % [lost, money])
		money_changed.emit(money)
	return lost


# ====================== СМЕРТЬ ======================

## Смерть в вылазке: теряется всё, кроме ключевых предметов, и часть денег
## (DEATH_MONEY_LOSS). Хранилище в квартире не трогается.
## Вызывать будет будущая система здоровья/боя.
func on_death() -> void:
	backpack.clear_non_key_items()
	var lost := lose_money(roundi(money * DEATH_MONEY_LOSS))
	print("☠ Смерть: потеряны предметы (кроме ключевых) и %d денег." % lost)
