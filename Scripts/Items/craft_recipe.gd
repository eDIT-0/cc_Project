class_name CraftRecipe
extends Resource
## Рецепт "предмет + предмет = предмет" (как в классических RE).
## Порядок ингредиентов не важен: A+B и B+A — один и тот же рецепт
## (см. ItemCatalog.make_recipe_key). Тратится по 1 шт. каждого ингредиента.

@export var ingredient_a: ItemData
@export var ingredient_b: ItemData
@export var result: ItemData
## Сколько штук результата получается (например, порох + порох = 10 патронов).
@export_range(1, 999) var result_count: int = 1


func is_valid() -> bool:
	return ingredient_a != null and ingredient_b != null and result != null \
		and not ingredient_a.item_id.is_empty() and not ingredient_b.item_id.is_empty() \
		and not result.item_id.is_empty()


func get_key() -> String:
	return ItemCatalog.make_recipe_key(ingredient_a.item_id, ingredient_b.item_id)
