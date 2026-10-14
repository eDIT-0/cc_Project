class_name CombatItemEffect
extends ItemEffect
## Боевой эффект предмета: урон и/или оглушение одной цели или всей группы.
## Контроллер передаётся через контекст, без зависимости от автозагрузки.

@export_range(0, 1000) var damage: int = 0
@export_range(0.0, 30.0) var stun_seconds: float = 0.0
@export var all_targets: bool = false
@export var tags: PackedStringArray = PackedStringArray(["item"])


func requires_combat_target() -> bool:
	return not all_targets


func can_apply(context: Dictionary) -> bool:
	var combat = context.get("combat")
	if combat == null or not context.get("in_combat", false):
		return false
	var target: int = context.get("target_index", -1)
	if all_targets or target < 0:
		for index in combat.get_alive_indices():
			if combat.can_apply_item_effect(index, damage, stun_seconds):
				return true
		return false
	return combat.can_apply_item_effect(target, damage, stun_seconds)


func apply(context: Dictionary) -> bool:
	var combat = context.get("combat")
	if combat == null or not context.get("in_combat", false):
		return false
	var indices: Array[int] = []
	if all_targets:
		indices.assign(combat.get_alive_indices())
	else:
		indices.append(int(context.get("target_index", -1)))
	var applied := false
	for index in indices:
		if combat.apply_item_effect(index, damage, stun_seconds, tags):
			applied = true
	return applied
