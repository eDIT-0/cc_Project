class_name ItemCatalog
extends Resource
## Справочник всех предметов и рецептов игры: item_id -> ItemData и
## пара ингредиентов -> CraftRecipe. Один .tres на всю игру
## (например, res://Data/Items/item_catalog.tres) — новый предмет или рецепт
## добавляется перетаскиванием в массив в инспекторе.
##
## В отличие от квестов, здесь справочник по id действительно нужен:
## инвентарь хранит только id, а для показа/использования нужен сам ItemData.

@export var items: Array[ItemData] = []
@export var recipes: Array[CraftRecipe] = []

var _items_by_id: Dictionary = {}     # item_id -> ItemData
var _recipes_by_key: Dictionary = {}  # make_recipe_key(a, b) -> CraftRecipe
var _is_built: bool = false


## Ключ рецепта, не зависящий от порядка ингредиентов.
static func make_recipe_key(id_a: String, id_b: String) -> String:
	if id_a <= id_b:
		return "%s+%s" % [id_a, id_b]
	return "%s+%s" % [id_b, id_a]


func get_item(item_id: String) -> ItemData:
	_ensure_built()
	return _items_by_id.get(item_id)


func has_item(item_id: String) -> bool:
	_ensure_built()
	return _items_by_id.has(item_id)


## Рецепт для пары предметов или null, если они не соединяются.
func find_recipe(id_a: String, id_b: String) -> CraftRecipe:
	_ensure_built()
	return _recipes_by_key.get(make_recipe_key(id_a, id_b))


## Пересобрать индексы — если массивы items/recipes меняли из кода.
func rebuild() -> void:
	_is_built = false
	_ensure_built()


func _ensure_built() -> void:
	if _is_built:
		return
	_is_built = true
	_items_by_id.clear()
	_recipes_by_key.clear()

	for item in items:
		if item == null:
			continue
		if item.item_id.is_empty():
			push_warning("ItemCatalog: предмет '%s' без item_id — пропущен." % item.display_name)
			continue
		if _items_by_id.has(item.item_id):
			push_warning("ItemCatalog: повтор item_id '%s' — используется первый." % item.item_id)
			continue
		if item.has_durability() and item.max_stack > 1:
			push_warning("ItemCatalog: у '%s' есть прочность — max_stack %d игнорируется, по 1 в ячейке." % [item.item_id, item.max_stack])
		_items_by_id[item.item_id] = item

	for recipe in recipes:
		if recipe == null:
			continue
		if not recipe.is_valid():
			push_warning("ItemCatalog: рецепт с пустым ингредиентом/результатом — пропущен.")
			continue
		var key := recipe.get_key()
		if _recipes_by_key.has(key):
			push_warning("ItemCatalog: два рецепта для '%s' — используется первый." % key)
			continue
		for part in [recipe.ingredient_a, recipe.ingredient_b, recipe.result]:
			if not _items_by_id.has(part.item_id):
				push_warning("ItemCatalog: предмет '%s' из рецепта '%s' не добавлен в items." % [part.item_id, key])
		_recipes_by_key[key] = recipe
