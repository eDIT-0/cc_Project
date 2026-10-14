extends Node
## Отдельный тестовый слот. Никаких дополнительных кнопок сохранения.
var _info: Label
var _hub: HubUI


func _ready() -> void:
	PlayerState.saves.store.slot_path = "user://saves/bed_checkpoint_test.json"
	_hub = load("res://hub_ui.tscn").instantiate() as HubUI
	# В тесте добавляем кровать/шкаф в копию ресурса, не меняя настройки хаба.
	for i in range(_hub.hub_manager.locations.size()):
		var location := _hub.hub_manager.locations[i]
		if location.location_id == "apartment":
			var copy := location.duplicate() as HubLocation
			copy.choices = location.choices.duplicate()
			for path in ["res://Data/Locations/Hub/Navigation/apartment_bed.tres", "res://Data/Locations/Hub/Navigation/apartment_wardrobe.tres"]:
				var choice := load(path) as HubChoice
				if not copy.choices.has(choice): copy.choices.append(choice)
			_hub.hub_manager.locations[i] = copy
	add_child(_hub)
	var overlay := CanvasLayer.new()
	overlay.layer = 5
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 54)
	overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 290
	panel.add_child(column)
	_info = Label.new()
	_info.custom_minimum_size.x = 290
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info)
	for entry in [["Подготовить состояние до сна", _prepare], ["Изменить состояние после сна", _mutate]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 40
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		column.add_child(button)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _available() -> bool:
	return not PlayerState.saves.is_blocked() and get_tree().get_first_node_in_group("save_load_menu") == null


func _prepare() -> void:
	if not _available(): return
	PlayerState.money = 321
	PlayerState.clock.minutes = 22 * 60
	PlayerState.clock.phase = GameClock._phase_for(PlayerState.clock.minutes)
	PlayerState.clock.time_changed.emit()
	PlayerState.clock.phase_changed.emit(PlayerState.clock.phase)
	PlayerState.stats.level = 3; PlayerState.stats.xp = 42; PlayerState.stats.stat_points = 2
	PlayerState.stats._effects.clear()
	PlayerState.stats.apply_effect(load("res://Data/Status/invigorated.tres"))
	PlayerState.stats.hp = 10; PlayerState.stats.stamina = 20
	PlayerState.set_flag("save_test_mark")
	PlayerState.set_value("save_test_counter", 7)
	for i in range(PlayerState.backpack.get_capacity()): PlayerState.backpack._slots[i] = {}
	PlayerState.backpack._slots[0] = {"item_id": "pepper_spray", "count": 1, "durability": 2}
	PlayerState.backpack._slots[2] = {"item_id": "cloth", "count": 2}
	for i in range(PlayerState.stash.get_capacity()): PlayerState.stash._slots[i] = {}
	PlayerState.stash.add("metal_parts_small", 3)
	PlayerState.money_changed.emit(PlayerState.money)
	PlayerState.backpack.changed.emit()
	PlayerState.stats.changed.emit()


func _mutate() -> void:
	if not _available(): return
	PlayerState.money = 9
	PlayerState.stats.hp = 5; PlayerState.stats.stamina = 10
	PlayerState.set_flag("save_test_mark", false)
	PlayerState.set_value("save_test_counter", -5)
	PlayerState.backpack.remove("pepper_spray", 1)
	PlayerState.advance_time(65)
	PlayerState.money_changed.emit(PlayerState.money)
	PlayerState.stats.changed.emit()


func _refresh() -> void:
	if _info == null: return
	_info.text = "Тестовый слот — отдельно от игры.\nПодготовь состояние, выбери кровать и сон.\nПосле изменений открой F9. Загрузка вернёт в обычную квартиру без этой панели.\n\n%s\nДеньги %d · HP %d · выносл. %d\nФлаг %s · счётчик %d\nСлот %s" % [PlayerState.clock.get_date_text(), PlayerState.money, PlayerState.stats.hp, PlayerState.stats.stamina, str(PlayerState.flag("save_test_mark")), PlayerState.value("save_test_counter"), "есть" if PlayerState.saves.store.exists() else "пуст"]
