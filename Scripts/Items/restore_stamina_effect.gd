class_name RestoreStaminaEffect
extends ItemEffect
## Восстанавливает выносливость. На полной — не срабатывает.

@export_range(1, 999) var amount: int = 10


func apply(context: Dictionary) -> bool:
	var stats: CharacterStats = context.get("stats", PlayerState.stats)
	var restored := stats.restore_stamina(amount)
	if restored == 0:
		print("⚡ Выносливость и так полная.")
		return false
	print("⚡ +%d выносливости (%d/%d)" % [restored, stats.stamina, stats.get_max_stamina()])
	return true


func can_apply(context: Dictionary) -> bool:
	var stats: CharacterStats = context.get("stats", PlayerState.stats)
	return amount > 0 and stats.stamina < stats.get_max_stamina()
