class_name LootTable
extends Resource
## Таблица добычи. Одна на локацию И сложность (LocationData.loot_*):
## отдельные таблицы — чтобы лучшее в игре физически не могло выпасть на
## ранних локациях, даже при большом везении. Ею пользуются клетки REWARD,
## случайные ивенты (run.roll_loot()), позже — добыча с врагов.
##
## Ориентир для выживания: основа — материалы для крафта, готовые
## расходники — редко, деньги — мелочь и не всегда.

@export var entries: Array[LootEntry] = []
## Сколько строк разыгрывается за одну находку (с повторами; одинаковые
## предметы складываются).
@export_range(1, 10) var rolls: int = 1

@export_group("Деньги")
@export_range(0.0, 1.0) var money_chance: float = 0.25
@export_range(0, 10000) var money_min: int = 5
@export_range(0, 10000) var money_max: int = 15


## Бросок. Результат: { "items": { item_id: count }, "money": int }.
func roll() -> Dictionary:
	var items := {}
	for i in range(rolls):
		var entry := _pick_entry()
		if entry == null:
			continue
		var count := randi_range(entry.min_count, maxi(entry.min_count, entry.max_count))
		items[entry.item.item_id] = items.get(entry.item.item_id, 0) + count
	var money := 0
	if money_max > 0 and randf() < money_chance:
		money = randi_range(money_min, maxi(money_min, money_max))
	return { "items": items, "money": money }


func _pick_entry() -> LootEntry:
	var total := 0.0
	for entry in entries:
		if entry != null and entry.item != null:
			total += entry.weight
	if total <= 0.0:
		return null
	var roll_value := randf() * total
	for entry in entries:
		if entry == null or entry.item == null:
			continue
		roll_value -= entry.weight
		if roll_value <= 0.0:
			return entry
	return null
