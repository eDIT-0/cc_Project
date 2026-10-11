class_name Inventory
extends RefCounted
## Инвентарь с фиксированным числом ячеек (как в классических RE).
## Ячейка — либо пустая ({}), либо { "item_id": String, "count": int }
## (+ "durability": int у изнашиваемых предметов, см. ItemData.max_durability).
## Хранятся только id и количество — всё остальное берётся из ItemCatalog.
##
## Один и тот же класс — и для рюкзака персонажа, и для хранилища в квартире
## (просто разная вместимость). Кто владеет инвентарём — решает не он
## (будущий PlayerState).
##
## Inventory НЕ знает про бой. Ограничения боя (нельзя перемещать и
## крафтить, использование — действие со стоимостью) будет накладывать
## UI/боевой контроллер, решая, какие из этих методов вообще предлагать.
## Единственное, что зависит от контекста здесь, — флаги usable_in_field /
## usable_in_combat у предмета в use_slot().

## Любое изменение содержимого — для перерисовки UI.
signal changed

var catalog: ItemCatalog
var _slots: Array[Dictionary] = []


func _init(p_catalog: ItemCatalog, p_capacity: int) -> void:
	catalog = p_catalog
	if catalog == null:
		push_error("Inventory: не передан ItemCatalog!")
	for i in range(maxi(0, p_capacity)):
		_slots.append({})


# ====================== ЧТЕНИЕ ======================

func get_capacity() -> int:
	return _slots.size()


func is_valid_slot(index: int) -> bool:
	return index >= 0 and index < _slots.size()


func is_slot_empty(index: int) -> bool:
	return not is_valid_slot(index) or _slots[index].is_empty()


## Копия содержимого ячейки: {} или { "item_id", "count" [, "durability"] }.
func get_slot(index: int) -> Dictionary:
	return _slots[index].duplicate() if is_valid_slot(index) else {}


## ItemData предмета в ячейке или null, если ячейка пуста.
func get_slot_item(index: int) -> ItemData:
	if is_slot_empty(index):
		return null
	return catalog.get_item(_slots[index].item_id)


func get_slot_count(index: int) -> int:
	return 0 if is_slot_empty(index) else _slots[index].count


## Оставшаяся прочность предмета в ячейке, -1 — если он не изнашивается.
func get_slot_durability(index: int) -> int:
	if is_slot_empty(index):
		return -1
	return _slots[index].get("durability", -1)


func get_free_slot_count() -> int:
	var free := 0
	for slot in _slots:
		if slot.is_empty():
			free += 1
	return free


func count_of(item_id: String) -> int:
	var total := 0
	for slot in _slots:
		if not slot.is_empty() and slot.item_id == item_id:
			total += slot.count
	return total


func has_item(item_id: String, amount: int = 1) -> bool:
	return count_of(item_id) >= amount


## Сколько штук предмета ещё влезет (докладывая в стаки и в пустые ячейки).
func space_for(item_id: String) -> int:
	var item := catalog.get_item(item_id)
	return 0 if item == null else _space_for(item)


## Поместится ли amount штук целиком (без фактического добавления).
func can_add(item_id: String, amount: int = 1) -> bool:
	var item := catalog.get_item(item_id)
	if item == null or amount <= 0:
		return false
	return _space_for(item) >= amount


# ====================== ДОБАВЛЕНИЕ / УДАЛЕНИЕ ======================

## Добавляет предмет: сначала докладывает в неполные стаки того же
## предмета, потом занимает пустые ячейки. Возвращает, сколько НЕ влезло —
## вызывающая сторона обязана с этим что-то сделать (предложить выбросить
## что-то, оставить предмет на месте), а не терять молча.
func add(item_id: String, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var item := catalog.get_item(item_id)
	if item == null:
		push_error("Inventory.add: неизвестный item_id '%s'." % item_id)
		return amount

	var leftover := _add_internal(item, amount)
	if leftover < amount:
		changed.emit()
	return leftover


## Убирает amount штук предмета (из последних ячеек к первым).
## Всё или ничего: если столько нет — ничего не трогает и вернёт false.
func remove(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count_of(item_id) < amount:
		return false

	var remaining := amount
	for i in range(_slots.size() - 1, -1, -1):
		if remaining == 0:
			break
		if _slots[i].is_empty() or _slots[i].item_id != item_id:
			continue
		remaining -= _take_from_slot(i, remaining)

	changed.emit()
	return true


## Убирает до amount штук из конкретной ячейки. Возвращает, сколько убрано.
func remove_from_slot(index: int, amount: int = 1) -> int:
	if is_slot_empty(index) or amount <= 0:
		return 0
	var removed := _take_from_slot(index, amount)
	changed.emit()
	return removed


## Можно ли выбросить содержимое ячейки. Ключевые предметы — нельзя (софтлок).
func can_discard(index: int) -> bool:
	var item := get_slot_item(index)
	return item != null and not item.is_key_item


## Выбросить ячейку целиком.
func discard_slot(index: int) -> bool:
	if not can_discard(index):
		return false
	_slots[index] = {}
	changed.emit()
	return true


## Есть ли хоть одна ячейка, которую можно выбросить (не ключевой предмет).
func has_discardable_slot() -> bool:
	for i in range(_slots.size()):
		if can_discard(i):
			return true
	return false


# ====================== ПЕРЕНОС МЕЖДУ ИНВЕНТАРЯМИ ======================

## Можно ли переложить ячейку ЦЕЛИКОМ в другой инвентарь (рюкзак -> хранилище).
## Ключевые предметы переносить можно — из хранилища их всегда можно забрать.
func can_transfer_slot(index: int, target: Inventory) -> bool:
	if target == null or target == self or is_slot_empty(index):
		return false
	var item := get_slot_item(index)
	if item.has_durability():
		return target.get_free_slot_count() > 0
	return target.can_add(item.item_id, _slots[index].count)


## Переложить ячейку целиком в другой инвентарь. Всё или ничего.
## Изнашиваемый предмет переезжает со своей прочностью.
func transfer_slot(index: int, target: Inventory) -> bool:
	if not can_transfer_slot(index, target):
		return false
	var slot: Dictionary = _slots[index]
	if slot.has("durability"):
		target._put_slot(slot.duplicate())
	else:
		target.add(slot.item_id, slot.count)
	_slots[index] = {}
	changed.emit()
	return true


# ====================== ПЕРЕМЕЩЕНИЕ / КРАФТ / ИСПОЛЬЗОВАНИЕ ======================

## Переложить ячейку from в to:
##   to пуста          -> просто переезд;
##   тот же предмет    -> доложить в стак to, остаток останется в from;
##   другой предмет    -> поменять местами (изнашиваемые одного типа — тоже:
##                        у них разная прочность, сливать нельзя).
func move_slot(from: int, to: int) -> bool:
	if from == to or is_slot_empty(from) or not is_valid_slot(to):
		return false

	if _slots[to].is_empty():
		_slots[to] = _slots[from]
		_slots[from] = {}
	elif _slots[to].item_id == _slots[from].item_id and not get_slot_item(to).has_durability():
		var item := get_slot_item(to)
		var moved := mini(item.get_stack_limit() - _slots[to].count, _slots[from].count)
		if moved <= 0:
			return false
		_slots[to].count += moved
		_take_from_slot(from, moved)
	else:
		var tmp := _slots[to]
		_slots[to] = _slots[from]
		_slots[from] = tmp

	changed.emit()
	return true


## Рецепт для двух ячеек (или null) — чтобы UI мог заранее подсветить,
## что с чем соединяется, не пытаясь соединить.
## a == b — особый случай: рецепт из двух ОДИНАКОВЫХ предметов (детали x2,
## порошок x2) можно собрать из одного стака, если в нём минимум 2 шт.
## Иначе стакающийся ингредиент пришлось бы сначала вручную делить на две
## ячейки, а такой операции в инвентаре нет.
func get_recipe_for_slots(a: int, b: int) -> CraftRecipe:
	if is_slot_empty(a) or is_slot_empty(b):
		return null
	if a == b and _slots[a].count < 2:
		return null
	return catalog.find_recipe(_slots[a].item_id, _slots[b].item_id)


## Крафт как в классических RE: выбран предмет A -> "Соединить" -> предмет B.
## Тратится по 1 шт. из A и B (или 2 шт. из A, если a == b — см.
## get_recipe_for_slots), результат появляется на месте A (если A
## опустела), остаток результата — по обычным правилам add().
## Если результат не помещается — откат, ничего не меняется, вернёт false.
func combine_slots(a: int, b: int) -> bool:
	var recipe := get_recipe_for_slots(a, b)
	if recipe == null:
		return false

	var snapshot := _slots.duplicate(true)

	if a == b:
		_take_from_slot(a, 2)  # оба ингредиента — из одного стака
	else:
		_take_from_slot(b, 1)
		_take_from_slot(a, 1)

	var to_place := recipe.result_count
	if _slots[a].is_empty():
		var in_a := mini(to_place, recipe.result.get_stack_limit())
		_slots[a] = _new_slot(recipe.result, in_a)
		to_place -= in_a

	if _add_internal(recipe.result, to_place) > 0:
		_slots.assign(snapshot)
		return false

	changed.emit()
	return true


## Использовать предмет из ячейки. Проверяет, можно ли его использовать в
## текущем контексте (бой / вне боя), применяет эффекты и, если хоть один
## сработал: расходный предмет тратит 1 шт., изнашиваемый — 1 прочности.
## extra_context — что ещё передать эффектам (позже: игрок, цель и т.п.).
func use_slot(index: int, in_combat: bool = false, extra_context: Dictionary = {}) -> bool:
	var item := get_slot_item(index)
	if item == null:
		return false
	if (in_combat and not item.usable_in_combat) or (not in_combat and not item.usable_in_field):
		return false

	var context := { "item": item, "inventory": self, "in_combat": in_combat }
	context.merge(extra_context)

	var any_applied := false
	for effect in item.effects:
		if effect != null and effect.apply(context):
			any_applied = true

	if not any_applied:
		return false
	if item.consumed_on_use:
		_take_from_slot(index, 1)
	elif item.has_durability():
		_wear_internal(index, 1)
	changed.emit()
	return true


## Износ без "использования" — для систем, которые применяют предмет по-своему
## (бой: удар ножом — это атака, а не "использовать предмет").
## Возвращает true, если предмет сломался.
func wear_slot(index: int, amount: int = 1) -> bool:
	var item := get_slot_item(index)
	if item == null or not item.has_durability():
		return false
	var broke := _wear_internal(index, amount)
	changed.emit()
	return broke


## Смерть: теряется всё, кроме ключевых предметов (чтобы не было софтлока).
func clear_non_key_items() -> void:
	for i in range(_slots.size()):
		var item := get_slot_item(i)
		if item != null and not item.is_key_item:
			_slots[i] = {}
	changed.emit()


## Увеличить вместимость (улучшение рюкзака). Уменьшать нельзя — некуда
## девать содержимое лишних ячеек.
func grow_capacity(new_capacity: int) -> void:
	if new_capacity <= _slots.size():
		push_warning("Inventory.grow_capacity: %d не больше текущей вместимости %d." % [new_capacity, _slots.size()])
		return
	while _slots.size() < new_capacity:
		_slots.append({})
	changed.emit()


## Текстовый снимок для отладки: "[0] Патроны x20 | [1] — | ..."
func debug_string() -> String:
	var parts: PackedStringArray = []
	for i in range(_slots.size()):
		var item := get_slot_item(i)
		var text := "—"
		if item != null:
			text = "%s x%d" % [item.display_name, _slots[i].count]
			if item.has_durability():
				text += " (прочн. %d/%d)" % [_slots[i].durability, item.max_durability]
		parts.append("[%d] %s" % [i, text])
	return " | ".join(parts)


# ====================== ВНУТРЕННЕЕ (без сигнала) ======================

func _space_for(item: ItemData) -> int:
	var limit := item.get_stack_limit()
	var space := 0
	for slot in _slots:
		if slot.is_empty():
			space += limit
		elif slot.item_id == item.item_id and not item.has_durability():
			space += maxi(0, limit - slot.count)
	return space


## Новая ячейка с предметом. Изнашиваемый получает полную прочность.
func _new_slot(item: ItemData, count: int) -> Dictionary:
	var slot := { "item_id": item.item_id, "count": count }
	if item.has_durability():
		slot["durability"] = item.max_durability
	return slot


## Снять прочность; на нуле предмет ломается и ячейка освобождается.
func _wear_internal(index: int, amount: int) -> bool:
	_slots[index].durability -= amount
	if _slots[index].durability > 0:
		return false
	print("💥 Сломался: %s" % get_slot_item(index).display_name)
	_slots[index] = {}
	return true


func _add_internal(item: ItemData, amount: int) -> int:
	var remaining := amount
	var limit := item.get_stack_limit()

	# 1. Докладываем в неполные стаки того же предмета (изнашиваемые не стакаются)
	if not item.has_durability():
		for slot in _slots:
			if remaining == 0:
				return 0
			if not slot.is_empty() and slot.item_id == item.item_id and slot.count < limit:
				var put := mini(limit - slot.count, remaining)
				slot.count += put
				remaining -= put

	# 2. Занимаем пустые ячейки
	for i in range(_slots.size()):
		if remaining == 0:
			return 0
		if _slots[i].is_empty():
			var put := mini(limit, remaining)
			_slots[i] = _new_slot(item, put)
			remaining -= put

	return remaining


## Убирает до amount штук из ячейки, пустую ячейку очищает. Возвращает, сколько убрано.
func _take_from_slot(index: int, amount: int) -> int:
	var taken := mini(amount, _slots[index].count)
	_slots[index].count -= taken
	if _slots[index].count <= 0:
		_slots[index] = {}
	return taken


## Положить готовую ячейку в первую пустую (для transfer_slot; место
## проверено заранее).
func _put_slot(slot: Dictionary) -> void:
	for i in range(_slots.size()):
		if _slots[i].is_empty():
			_slots[i] = slot
			changed.emit()
			return
	push_error("Inventory._put_slot: нет свободной ячейки — предмет потерян.")
