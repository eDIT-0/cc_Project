extends Node
## Самопроверка Inventory / ItemCatalog без UI. Запуск: открыть
## res://Scenes/Tests/inventory_test.tscn и нажать F6 (Run Current Scene).
## Результат — в консоли: ✅/❌ по каждой проверке и итог в конце.
## Предметы создаются прямо в коде, чтобы тест не зависел от .tres-данных.

var _passed := 0
var _failed := 0


func _ready() -> void:
	var catalog := _make_catalog()

	_test_stacking(catalog)
	_test_remove_and_discard(catalog)
	_test_move(catalog)
	_test_craft(catalog)
	_test_use(catalog)
	_test_death(catalog)
	_test_durability(catalog)
	_test_chance_effect()
	_test_transfer(catalog)

	print("\n==== ИТОГ: %d пройдено, %d провалено ====" % [_passed, _failed])
	if _failed > 0:
		push_error("InventoryTest: есть проваленные проверки — см. консоль.")


# ====================== ТЕСТОВЫЕ ДАННЫЕ ======================

func _make_item(id: String, display: String, max_stack: int, key := false) -> ItemData:
	var item := ItemData.new()
	item.item_id = id
	item.display_name = display
	item.max_stack = max_stack
	item.is_key_item = key
	return item


func _make_catalog() -> ItemCatalog:
	var ammo := _make_item("ammo", "Патроны", 20)
	var grenade := _make_item("grenade", "Граната", 4)
	var gunpowder := _make_item("gunpowder", "Порох", 2)
	var herb_green := _make_item("herb_green", "Зелёная трава", 1)
	var herb_red := _make_item("herb_red", "Красная трава", 1)
	var herb_mix := _make_item("herb_mix", "Смесь трав", 1)
	var key_card := _make_item("key_card", "Ключ-карта", 1, true)

	var bandage := _make_item("bandage", "Бинт", 3)
	bandage.usable_in_field = true
	bandage.usable_in_combat = true
	var heal := LogStubEffect.new()
	heal.message = "лечение (заглушка — здоровья ещё нет)"
	bandage.effects.append(heal)

	var flashlight := _make_item("flashlight", "Фонарик", 1)
	flashlight.usable_in_field = true          # только вне боя
	flashlight.consumed_on_use = false         # многоразовый
	var light := LogStubEffect.new()
	light.message = "стало светлее"
	flashlight.effects.append(light)

	var knife := _make_item("knife", "Нож", 5)     # max_stack 5 должен игнорироваться
	knife.max_durability = 2
	knife.consumed_on_use = false

	var spray := _make_item("spray", "Баллончик", 1)
	spray.max_durability = 2
	spray.usable_in_combat = true
	spray.consumed_on_use = false
	var blind := LogStubEffect.new()
	blind.message = "пшик"
	spray.effects.append(blind)

	var r_herbs := CraftRecipe.new()
	r_herbs.ingredient_a = herb_green
	r_herbs.ingredient_b = herb_red
	r_herbs.result = herb_mix

	var r_ammo := CraftRecipe.new()
	r_ammo.ingredient_a = gunpowder
	r_ammo.ingredient_b = gunpowder
	r_ammo.result = ammo
	r_ammo.result_count = 30                   # больше одного стака — займёт 2 ячейки

	var catalog := ItemCatalog.new()
	catalog.items.assign([ammo, grenade, gunpowder, herb_green, herb_red, herb_mix, key_card, bandage, flashlight, knife, spray])
	catalog.recipes.assign([r_herbs, r_ammo])
	return catalog


# ====================== ТЕСТЫ ======================

func _test_stacking(catalog: ItemCatalog) -> void:
	print("\n-- Стаки и вместимость --")
	var inv := Inventory.new(catalog, 6)
	_check(inv.get_free_slot_count() == 6, "новый инвентарь: 6 пустых ячеек")
	_check(inv.add("ammo", 45) == 0, "45 патронов влезли")
	_check(inv.get_free_slot_count() == 3, "45 патронов заняли 3 ячейки (20+20+5)")
	_check(inv.add("ammo", 10) == 0 and inv.get_free_slot_count() == 3, "+10 патронов дозаполнили неполный стак, новых ячеек не заняли")
	_check(inv.add("grenade", 3) == 0 and inv.add("bandage", 5) == 0, "гранаты (1 ячейка) и бинты (2 ячейки) влезли")
	_check(inv.get_free_slot_count() == 0, "инвентарь полон")
	_check(inv.add("key_card") == 1, "в полный инвентарь не влезло — add() вернул остаток 1")
	_check(not inv.can_add("key_card") and inv.can_add("grenade", 1) and not inv.can_add("grenade", 2), "can_add учитывает место в неполных стаках")
	_check(inv.add("no_such_item") == 1, "неизвестный id не добавляется (ожидается ошибка в консоли)")
	print("   ", inv.debug_string())


func _test_remove_and_discard(catalog: ItemCatalog) -> void:
	print("\n-- Удаление и выбрасывание --")
	var inv := Inventory.new(catalog, 4)
	inv.add("ammo", 30)
	inv.add("key_card")
	_check(not inv.remove("ammo", 31) and inv.count_of("ammo") == 30, "нельзя убрать больше, чем есть — ничего не тронуто")
	_check(inv.remove("ammo", 15) and inv.count_of("ammo") == 15, "убрали 15 патронов, осталось 15")
	var key_slot := _find_slot(inv, "key_card")
	_check(not inv.can_discard(key_slot) and not inv.discard_slot(key_slot), "ключевой предмет выбросить нельзя")
	var ammo_slot := _find_slot(inv, "ammo")
	_check(inv.discard_slot(ammo_slot) and inv.count_of("ammo") == 0, "обычный предмет выбрасывается")


func _test_move(catalog: ItemCatalog) -> void:
	print("\n-- Перемещение --")
	var inv := Inventory.new(catalog, 4)
	inv.add("grenade", 1)       # [0] граната
	inv.add("bandage", 2)       # [1] бинт x2
	_check(inv.move_slot(0, 3) and inv.is_slot_empty(0) and inv.get_slot(3).item_id == "grenade", "переезд в пустую ячейку")
	_check(inv.move_slot(1, 3) and inv.get_slot(3).item_id == "bandage" and inv.get_slot(1).item_id == "grenade", "разные предметы меняются местами")
	inv.add("ammo", 20)         # займёт [0]
	inv.add("ammo", 5)          # займёт [2]
	_check(not inv.move_slot(2, 0), "в полный стак доложить нельзя")
	inv.remove_from_slot(0, 10) # [0] = 10
	_check(inv.move_slot(2, 0) and inv.get_slot_count(0) == 15 and inv.is_slot_empty(2), "стаки одного предмета сливаются")
	print("   ", inv.debug_string())


func _test_craft(catalog: ItemCatalog) -> void:
	print("\n-- Крафт --")
	var inv := Inventory.new(catalog, 4)
	inv.add("herb_green")       # [0]
	inv.add("herb_red")         # [1]
	inv.add("grenade")          # [2]
	_check(inv.get_recipe_for_slots(1, 0) != null, "рецепт находится в любом порядке ингредиентов")
	_check(not inv.combine_slots(0, 2) and inv.count_of("herb_green") == 1, "без рецепта не соединяется, ничего не тронуто")
	_check(inv.combine_slots(0, 1), "трава + трава соединились")
	_check(inv.get_slot(0).item_id == "herb_mix" and inv.is_slot_empty(1), "результат на месте первого, второй исчез")

	var inv2 := Inventory.new(catalog, 2)
	inv2.add("gunpowder", 2)
	inv2.add("gunpowder", 2)    # [0] x2, [1] x2
	_check(not inv2.combine_slots(0, 1), "30 патронов не влезают (обе ячейки ещё заняты порохом) — отказ")
	_check(inv2.get_slot_count(0) == 2 and inv2.get_slot_count(1) == 2, "при отказе — полный откат")

	# У пороха max_stack = 2, так что по одной штуке в двух ячейках
	# раскладываем так: 2 в [0], 1 в [1], потом убираем 1 из [0].
	var inv3 := Inventory.new(catalog, 3)
	inv3.add("gunpowder", 2)    # [0] x2
	inv3.add("gunpowder", 1)    # [1] x1
	inv3.remove_from_slot(0, 1) # [0] x1, [1] x1
	_check(inv3.combine_slots(0, 1), "порох + порох соединились")
	_check(inv3.count_of("ammo") == 30 and inv3.count_of("gunpowder") == 0, "получено 30 патронов (20 на месте первого + 10 в свободной ячейке)")
	print("   ", inv3.debug_string())

	var inv4 := Inventory.new(catalog, 2)
	inv4.add("gunpowder", 1)    # [0] x1
	_check(inv4.get_recipe_for_slots(0, 0) == null and not inv4.combine_slots(0, 0), "одинаковые из одного стака: 1 шт. — нельзя")
	inv4.add("gunpowder", 1)    # [0] x2
	_check(inv4.combine_slots(0, 0), "одинаковые из одного стака: 2 шт. — соединились")
	_check(inv4.count_of("gunpowder") == 0 and inv4.count_of("ammo") == 30, "потрачено 2 пороха из одной ячейки, получено 30 патронов")
	inv4 = Inventory.new(catalog, 2)
	inv4.add("herb_green")
	_check(not inv4.combine_slots(0, 0), "ячейка с самой собой без рецепта на пару — не соединяется")


func _test_use(catalog: ItemCatalog) -> void:
	print("\n-- Использование --")
	var inv := Inventory.new(catalog, 4)
	inv.add("bandage", 2)
	inv.add("flashlight")
	inv.add("key_card")
	var bandage_slot := _find_slot(inv, "bandage")
	var flashlight_slot := _find_slot(inv, "flashlight")
	_check(inv.use_slot(bandage_slot) and inv.count_of("bandage") == 1, "бинт использован вне боя и потрачен (см. строку-заглушку выше)")
	_check(inv.use_slot(bandage_slot, true) and inv.count_of("bandage") == 0, "бинт использован в бою")
	_check(not inv.use_slot(flashlight_slot, true), "фонарик в бою использовать нельзя")
	_check(inv.use_slot(flashlight_slot) and inv.count_of("flashlight") == 1, "фонарик вне боя — работает и не тратится")
	_check(not inv.use_slot(_find_slot(inv, "key_card")), "ключ-карту просто так не используешь")


func _test_death(catalog: ItemCatalog) -> void:
	print("\n-- Смерть --")
	var inv := Inventory.new(catalog, 4)
	inv.add("ammo", 20)
	inv.add("key_card")
	inv.add("bandage", 3)
	inv.clear_non_key_items()
	_check(inv.count_of("key_card") == 1 and inv.count_of("ammo") == 0 and inv.count_of("bandage") == 0, "после смерти остались только ключевые предметы")


func _test_durability(catalog: ItemCatalog) -> void:
	print("\n-- Прочность (ожидается варнинг каталога про max_stack у 'knife') --")
	var inv := Inventory.new(catalog, 4)
	_check(inv.add("knife", 2) == 0 and inv.get_free_slot_count() == 2, "изнашиваемые не стакаются: 2 ножа = 2 ячейки")
	var a := _find_slot(inv, "knife")
	_check(inv.get_slot_durability(a) == 2, "новый нож — полная прочность 2")
	_check(not inv.wear_slot(a) and inv.get_slot_durability(a) == 1, "износ 1 — не сломался, прочность 1")
	var b := a + 1
	_check(inv.move_slot(a, b) and inv.get_slot_durability(a) == 2 and inv.get_slot_durability(b) == 1, "два ножа меняются местами, а не сливаются (прочность у каждого своя)")
	_check(inv.wear_slot(b) and inv.is_slot_empty(b) and inv.count_of("knife") == 1, "износ до нуля — нож сломался и исчез")
	_check(inv.can_add("knife", 3) and not inv.can_add("knife", 4), "can_add: в 3 пустые ячейки влезает ровно 3 ножа")
	inv.add("spray")
	var s := _find_slot(inv, "spray")
	_check(not inv.use_slot(s), "баллончик вне боя не используется")
	_check(inv.use_slot(s, true) and inv.get_slot_durability(s) == 1, "баллончик в бою: сработал, прочность 2 -> 1")
	_check(inv.use_slot(s, true) and inv.count_of("spray") == 0, "второй пшик — баллончик кончился")
	print("   ", inv.debug_string())


func _test_chance_effect() -> void:
	print("\n-- Эффект с шансом --")
	var ok := LogStubEffect.new()
	ok.message = "успех"
	var bad := LogStubEffect.new()
	bad.message = "провал"
	var effect := ChanceEffect.new()
	effect.on_success.append(ok)
	effect.on_failure.append(bad)
	effect.success_chance = 1.0
	_check(effect.apply({}), "шанс 1.0 — сработал (в консоли 'успех')")
	effect.success_chance = 0.0
	_check(effect.apply({}), "шанс 0.0 — тоже засчитан как использование (в консоли 'провал')")


func _test_transfer(catalog: ItemCatalog) -> void:
	print("\n-- Перенос рюкзак -> хранилище --")
	var bp := Inventory.new(catalog, 3)
	var st := Inventory.new(catalog, 2)
	bp.add("ammo", 15)      # [0]
	bp.add("knife")         # [1]
	bp.add("key_card")      # [2]
	bp.wear_slot(1)
	_check(bp.has_discardable_slot(), "в рюкзаке есть что выбросить")
	_check(bp.transfer_slot(0, st) and bp.is_slot_empty(0) and st.count_of("ammo") == 15, "стак переехал целиком")
	_check(bp.transfer_slot(1, st) and st.get_slot_durability(_find_slot(st, "knife")) == bp.catalog.get_item("knife").max_durability - 1, "нож переехал со своей прочностью")
	_check(not bp.can_transfer_slot(2, st) and not bp.transfer_slot(2, st) and bp.count_of("key_card") == 1, "хранилище полно — перенос не идёт, ничего не тронуто")
	_check(not bp.has_discardable_slot(), "остались одни ключевые — выбрасывать нечего")
	st.add("ammo", 5)       # стак патронов в хранилище дорастает до 20
	bp.add("ammo", 1)
	_check(not bp.can_transfer_slot(_find_slot(bp, "ammo"), st), "стак не влезает даже частично — перенос запрещён (всё или ничего)")

	var a := Inventory.new(catalog, 2)
	var b := Inventory.new(catalog, 1)
	a.add("ammo", 20)
	_check(a.transfer_amount(0, b, 1) == 1 and a.count_of("ammo") == 19 and b.count_of("ammo") == 1, "переложить 1 шт. из стака")
	_check(a.transfer_amount(0, b, 9999) == 19 and a.is_slot_empty(0) and b.count_of("ammo") == 20, "переложить всё")
	a.add("ammo", 20)
	_check(a.transfer_amount(0, b, 9999) == 0 and a.count_of("ammo") == 20, "некуда — ничего не переложено")
	b.remove("ammo", 5)
	_check(a.transfer_amount(0, b, 9999) == 5 and a.count_of("ammo") == 15, "«всё» — сколько влезло (5 из 20)")


# ====================== УТИЛИТЫ ======================

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("✅ ", label)
	else:
		_failed += 1
		print("❌ ", label)


func _find_slot(inv: Inventory, item_id: String) -> int:
	for i in range(inv.get_capacity()):
		if not inv.is_slot_empty(i) and inv.get_slot(i).item_id == item_id:
			return i
	return -1
