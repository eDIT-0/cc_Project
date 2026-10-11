class_name ApplyStatusEffect
extends ItemEffect
## Накладывает эффект состояния (StatusEffect). stack_stages — на сколько
## стадий поднять уже висящий эффект той же группы: пиво — 1, самогон — 2
## (см. CharacterStats.apply_effect). Срабатывает всегда.

@export var effect: StatusEffect
@export_range(0, 10) var stack_stages: int = 0


func apply(context: Dictionary) -> bool:
	if effect == null:
		push_warning("ApplyStatusEffect: не назначен effect (%s)." % resource_path)
		return false
	var stats: CharacterStats = context.get("stats", PlayerState.stats)
	stats.apply_effect(effect, stack_stages)
	return true
