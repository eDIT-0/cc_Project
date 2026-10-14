extends Node
## Автозагружаемый синглтон (Project Settings -> Autoload -> имя "PlayerState").
## Всё, что персонаж носит и копит МЕЖДУ сценами: рюкзак, хранилище в
## квартире, деньги, состояние персонажа (stats) и игровое время.
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

## Игровое время за действия (в минутах). Бой времени не тратит.
const MAZE_STEP_MINUTES := 10
const HUB_MOVE_MINUTES := 5
## Выносливость за шаг по клетке лабиринта (по хабу ходить бесплатно).
const MAZE_STEP_STAMINA := 2
## Сон в кровати: сколько длится и что даёт (полное здоровье и выносливость).
const SLEEP_MINUTES := 8 * 60

## Поражение: сколько игрового времени проходит и до какой доли
## восстанавливаются здоровье и выносливость.
const DEFEAT_MINUTES := 2 * 60
const DEFEAT_RESTORE_FRACTION := 0.5

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
## Характеристики, здоровье, выносливость, возбуждение, эффекты состояния.
var stats: CharacterStats
## Игровые часы: день, день недели, время суток (см. GameClock).
var clock: GameClock = GameClock.new()
## Сколько игровых минут прошло с начала игры (только чтение).
var game_minutes: int:
	get:
		return clock.get_elapsed_minutes()

## Скрытые параметры и сюжетные отметки (игроку не показываются).
## Флаги — да/нет ("met_boss"), счётчики — числа ("reputation").
## Пока без сохранений — живут до перезапуска.
var _flags: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	catalog = load(CATALOG_PATH) as ItemCatalog
	if catalog == null:
		push_error("PlayerState: не найден каталог предметов %s — создаю пустой." % CATALOG_PATH)
		catalog = ItemCatalog.new()

	backpack = Inventory.new(catalog, BACKPACK_CAPACITY)
	stash = Inventory.new(catalog, STASH_CAPACITY)
	stats = CharacterStats.new()
	stats.died.connect(func(): print("☠ Здоровье на нуле — поражение (обрабатывают DungeonRun / HubUI)."))

	if OS.is_debug_build():
		for item_id in DEBUG_START_ITEMS:
			backpack.add(item_id, DEBUG_START_ITEMS[item_id])  # без экрана переполнения
		money = DEBUG_START_MONEY


# ====================== ВРЕМЯ И ДЕЙСТВИЯ ======================

## Прошло игровое время: тикают эффекты состояния.
func advance_time(minutes: int) -> void:
	if minutes <= 0:
		return
	clock.advance(minutes)  # раньше эффектов: экраны по stats.changed видят уже новое время
	stats.advance_time(minutes)


## Шаг по клетке лабиринта (зовёт DungeonRun).
func on_maze_step() -> void:
	stats.spend_stamina(MAZE_STEP_STAMINA)
	advance_time(MAZE_STEP_MINUTES)


## Переход между локациями хаба (зовёт HubManager).
func on_hub_move() -> void:
	advance_time(HUB_MOVE_MINUTES)


## Сон (кровать в квартире): проходит SLEEP_MINUTES — эффекты тикают
## (опьянение выветривается), затем полностью восстанавливаются здоровье и
## выносливость. Из диалога: do PlayerState.sleep()
func sleep() -> void:
	advance_time(SLEEP_MINUTES)
	stats.restore_all()
	print("🛏 Сон: %s. Здоровье и выносливость восстановлены." % format_minutes(SLEEP_MINUTES))


## "3 ч 20 мин" — для отладочных экранов.
func format_minutes(minutes: int) -> String:
	if minutes < 60:
		return "%d мин" % minutes
	return "%d ч %02d мин" % [minutes / 60, minutes % 60]


## Привлекательность — ЗАГЛУШКА: потом будет считаться от одежды и т.п.
## Пока берётся из скрытого счётчика "attractiveness" (для тестов:
## кнопка на экране персонажа или do PlayerState.set_value("attractiveness", 10)).
## Влияет на шанс неприятностей в хабе (HubEvent).
func get_attractiveness() -> int:
	return value("attractiveness")


## Бонус к шансу заметить врага первым (доля: 0.05 = +5%) — ЗАГЛУШКА:
## потом одежда, пассивные навыки и т.п. См. EncounterTable.get_spot_chance.
func get_stealth_bonus() -> float:
	return 0.0


# ====================== ПРОВЕРКИ (короткие имена для диалогов) ======================

## Бросок проверки характеристики:  if PlayerState.check("DEX", 6)
func check(stat: String, difficulty: int) -> bool:
	return stats.roll_check(stat, difficulty)


## Шансов почти нет — предупредить игрока:  [if PlayerState.is_hopeless("DEX", 6) /]
func is_hopeless(stat: String, difficulty: int) -> bool:
	return stats.is_check_hopeless(stat, difficulty)


# ====================== ФЛАГИ И СЧЁТЧИКИ ======================
## В диалогах:
##   if PlayerState.flag("met_boss")
##   do PlayerState.set_flag("met_boss")
##   if PlayerState.value("reputation") >= 10
##   do PlayerState.add_value("reputation", 2)

func flag(flag_name: String) -> bool:
	return _flags.get(flag_name, false)


func set_flag(flag_name: String, enabled: bool = true) -> void:
	if enabled:
		_flags[flag_name] = true
	else:
		_flags.erase(flag_name)


func value(value_name: String) -> int:
	return _values.get(value_name, 0)


func has_value(value_name: String) -> bool:
	return _values.has(value_name)


func set_value(value_name: String, amount: int) -> void:
	_values[value_name] = amount


## Возвращает новое значение.
func add_value(value_name: String, amount: int) -> int:
	_values[value_name] = value(value_name) + amount
	return _values[value_name]


## Для отладочного экрана.
func get_debug_flags() -> Dictionary:
	return _flags.duplicate()


func get_debug_values() -> Dictionary:
	return _values.duplicate()


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


# ====================== ПОРАЖЕНИЕ ======================

## Штрафы поражения в лабиринте (сцену и перенос делает DungeonRun):
## предметы (кроме ключевых) и часть денег теряются — on_death(); проходит
## DEFEAT_MINUTES; здоровье и выносливость — до половины. Опыт не трогаем.
func apply_defeat() -> void:
	on_death()
	advance_time(DEFEAT_MINUTES)
	stats.restore_to_fraction(DEFEAT_RESTORE_FRACTION)


# ====================== СМЕРТЬ ======================

## Смерть в вылазке: теряется всё, кроме ключевых предметов, и часть денег
## (DEATH_MONEY_LOSS). Хранилище в квартире не трогается.
## Вызывать будет будущая система здоровья/боя.
func on_death() -> void:
	backpack.clear_non_key_items()
	var lost := lose_money(roundi(money * DEATH_MONEY_LOSS))
	print("☠ Смерть: потеряны предметы (кроме ключевых) и %d денег." % lost)
