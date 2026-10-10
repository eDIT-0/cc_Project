class_name ItemData
extends Resource
## Описание одного типа предмета. Сами экземпляры в инвентаре — это только
## item_id + количество (см. Inventory), а всё остальное берётся отсюда
## через ItemCatalog. Так состояние инвентаря остаётся простыми данными
## (задел под сохранения), а баланс правится в .tres без кода.

@export var item_id: String = ""                 ## Уникальный ключ, например "bandage"
@export var display_name: String = "Новый предмет"
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Хранение")
## Сколько штук помещается в ОДНУ ячейку. 1 = не стакается.
@export_range(1, 999) var max_stack: int = 1
## Ключевой предмет: занимает ячейку как обычный, но его нельзя выбросить
## (Inventory.can_discard) и он не теряется при смерти
## (Inventory.clear_non_key_items) — чтобы не было софтлока.
@export var is_key_item: bool = false

@export_group("Износ")
## Сколько раз предмет можно использовать, прежде чем он сломается
## (ножи, баллончик). 0 = не изнашивается. Прочность хранится у КАЖДОГО
## экземпляра отдельно (в ячейке инвентаря), поэтому такие предметы
## никогда не стакаются — по одному в ячейке, независимо от max_stack.
## Износ — это НЕ трата: тратящийся предмет (consumed_on_use) просто
## исчезает по 1 шт., изнашиваемый теряет единицу прочности за применение.
@export_range(0, 999) var max_durability: int = 0

@export_group("Использование")
@export var usable_in_field: bool = false        ## Вне боя (хаб, лабиринт)
@export var usable_in_combat: bool = false       ## В бою (там использование — действие со стоимостью)
## Тратится ли 1 шт. при успешном использовании. false — многоразовое
## (например, фонарик), true — расходник.
@export var consumed_on_use: bool = true
## Что происходит при использовании. Порядок важен — применяются по очереди.
@export var effects: Array[ItemEffect] = []

@export_group("Экономика")
@export_range(0, 99999) var base_price: int = 0


func is_usable() -> bool:
	return usable_in_field or usable_in_combat


func has_durability() -> bool:
	return max_durability > 0


## Сколько штук реально помещается в одну ячейку.
func get_stack_limit() -> int:
	return 1 if has_durability() else max_stack
