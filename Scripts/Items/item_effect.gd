class_name ItemEffect
extends Resource
## Базовый класс эффекта предмета. Конкретные эффекты (лечение, снятие
## статуса, урон врагу...) — подклассы с переопределённым apply().
## Новый эффект = новый класс, Inventory и ItemData при этом не меняются.
##
## context — словарь с тем, что известно в момент использования. Сейчас:
##   "item": ItemData, "inventory": Inventory, "in_combat": bool
## Позже сюда добавятся "player" (состояние персонажа), "target" (враг) и т.п.

## Возвращает true, если эффект реально сработал. Если ни один эффект
## предмета не сработал, предмет не тратится (см. Inventory.use_slot).
func apply(_context: Dictionary) -> bool:
	push_warning("ItemEffect.apply() не переопределён в %s" % resource_path)
	return false
