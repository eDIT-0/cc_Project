class_name LogStubEffect
extends ItemEffect
## Заглушка: просто пишет в консоль. Для предметов, чей настоящий эффект
## зависит от ещё не построенных систем (здоровье, статусы, бой).

@export_multiline var message: String = ""


func apply(context: Dictionary) -> bool:
	var item: ItemData = context.get("item")
	print("[Эффект-заглушка] %s: %s" % [item.display_name if item else "?", message])
	return true
