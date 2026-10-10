class_name ChanceEffect
extends ItemEffect
## Эффект с шансом: с вероятностью success_chance применяются on_success,
## иначе — on_failure (например, самодельный инъектор: лечит или вешает
## дебафф). Использование засчитывается в любом случае — даже неудачная
## попытка тратит предмет.

@export_range(0.0, 1.0) var success_chance: float = 0.5
@export var on_success: Array[ItemEffect] = []
@export var on_failure: Array[ItemEffect] = []


func apply(context: Dictionary) -> bool:
	var succeeded := randf() < success_chance
	for effect in (on_success if succeeded else on_failure):
		if effect != null:
			effect.apply(context)
	return true
