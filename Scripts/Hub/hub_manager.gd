class_name HubManager
extends Node
## Логика хаба. Ничего не знает про кнопки/картинки — только состояние и переходы.
## Присоединяется к узлу в сцене хаба (не автозагрузка — хаб существует, пока мы в хабе).

signal location_changed(location: HubLocation)

@export var locations: Array[HubLocation] = []
@export var start_location_id: String = "apartment"

var current_location: HubLocation

var _locations_by_id: Dictionary = {}


func _ready() -> void:
	for loc in locations:
		if loc.location_id.is_empty():
			push_warning("HubManager: у одной из локаций пустой location_id, она будет проигнорирована.")
			continue
		_locations_by_id[loc.location_id] = loc

	# ВАЖНО: go_to() здесь больше не вызывается.
	# HubManager — дочерний узел HubUI, а в Godot дочерние узлы получают
	# _ready() раньше родителя. Если бы мы стартовали локацию прямо тут,
	# сигнал location_changed улетел бы до того, как HubUI успеет на него
	# подписаться в своём _ready() — и первый экран остался бы пустым.
	# Поэтому старт локации теперь запускает сам HubUI, уже после подписки.


func go_to(location_id: String) -> void:
	if not _locations_by_id.has(location_id):
		push_error("HubManager: локация '%s' не найдена среди назначенных locations!" % location_id)
		return

	# Первый go_to() — это вход в хаб (старт игры / возврат из лабиринта),
	# а не переход, время не тратится.
	if current_location != null:
		PlayerState.on_hub_move()
	current_location = _locations_by_id[location_id]
	location_changed.emit(current_location)
