class_name HealEffect
extends ItemEffect
## Восстанавливает здоровье. Если здоровье и так полное — не срабатывает,
## и предмет не тратится (см. Inventory.use_slot).

@export_range(1, 999) var amount: int = 10


func apply(context: Dictionary) -> bool:
	var stats: CharacterStats = context.get("stats", PlayerState.stats)
	var healed := stats.heal(amount)
	if healed == 0:
		print("❤ Здоровье и так полное.")
		return false
	print("❤ +%d здоровья (%d/%d)" % [healed, stats.hp, stats.get_max_hp()])
	return true


func can_apply(context: Dictionary) -> bool:
	var stats: CharacterStats = context.get("stats", PlayerState.stats)
	return amount > 0 and stats.hp < stats.get_max_hp()
