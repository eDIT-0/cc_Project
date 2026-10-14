class_name BedSaveManager
extends Node
## Сервис PlayerState: сохранение только из кровати, загрузка — с подтверждением.
## Не автозагрузка: создаётся ребёнком PlayerState, новые настройки проекта не нужны.
var player
var store := BedSaveStore.new()
var codec := BedSaveCodec.new()
var loading: bool = false
var screen: BedSaveScreen
var _last_bed_line: WeakRef
var _sleep_authorized: bool = false


func _ready() -> void:
	screen = BedSaveScreen.new()
	screen.manager = self
	add_child(screen)


func is_playable() -> bool:
	return player.in_dungeon or get_tree().get_first_node_in_group("hub_ui") != null


func is_blocked() -> bool:
	if loading or get_tree().get_first_node_in_group("active_combat") != null: return true
	for name in ["InventoryScreen", "CharacterScreen", "TradeManager"]:
		var node = get_node_or_null("/root/" + name)
		if node != null and node.is_open(): return true
	for box in get_tree().get_nodes_in_group("dialogue_box"):
		if box.is_active(): return true
	return false


func authorize_sleep() -> Dictionary:
	if loading or player.in_dungeon or get_tree().get_first_node_in_group("active_combat") != null or get_tree().get_first_node_in_group("save_load_menu") != null:
		return {"ok": false, "error": "Сон с сохранением доступен только в кровати квартиры."}
	for name in ["InventoryScreen", "CharacterScreen", "TradeManager"]:
		var node = get_node_or_null("/root/" + name)
		if node != null and node.is_open(): return {"ok": false, "error": "Сначала закрой открытый экран."}
	var hub = get_tree().get_first_node_in_group("hub_ui")
	if hub == null or hub.hub_manager == null or hub.hub_manager.current_location == null or hub.hub_manager.current_location.location_id != "apartment":
		return {"ok": false, "error": "Сон с сохранением доступен только в кровати квартиры."}
	for box in get_tree().get_nodes_in_group("dialogue_box"):
		if box.is_active() and box._current_resource == load("res://Dialogue/bed.dialogue"):
			if _last_bed_line != null and _last_bed_line.get_ref() == box._current_line:
				return {"ok": false, "duplicate": true}
			_last_bed_line = weakref(box._current_line)
			_sleep_authorized = true
			return {"ok": true}
	return {"ok": false, "error": "Чтобы сохраниться, выбери сон в диалоге кровати."}


func save_after_sleep() -> Dictionary:
	if not _sleep_authorized: return {"ok": false, "error": "Запись доступна только после сна в кровати."}
	_sleep_authorized = false
	var captured := codec.capture(player)
	if not captured.ok: return captured
	return store.write_slot(captured.data)


func inspect_slot() -> Dictionary:
	var result := store.read_slot()
	if not result.ok: return result
	var checked := codec.prepare(result.data, player.catalog)
	if checked.ok: checked["recovered"] = result.recovered
	return checked


func load_checkpoint() -> Dictionary:
	if not is_playable() or is_blocked(): return {"ok": false, "error": "Загрузка недоступна во время боя, диалога или открытого экрана."}
	var checked := inspect_slot()
	if not checked.ok: return checked
	var game = get_node_or_null("/root/GameManager")
	if game == null: return {"ok": false, "error": "Менеджер игры не готов."}
	var packed := load(game.HUB_SCENE_PATH) as PackedScene
	if packed == null: return {"ok": false, "error": "Не найдена сцена города."}
	# Проверяем точку появления ДО смены сцены и изменения состояния.
	var instance := packed.instantiate()
	var preview := instance as HubUI
	if preview == null:
		instance.free()
		return {"ok": false, "error": "Сцена города больше не содержит HubUI."}
	var home_exists := false
	if preview.hub_manager != null:
		for location in preview.hub_manager.locations:
			if location != null and location.location_id == "apartment": home_exists = true
	preview.free()
	if not home_exists: return {"ok": false, "error": "В городе не найдена квартира для загрузки."}
	loading = true
	var scene_error := get_tree().change_scene_to_packed(packed)
	if scene_error != OK:
		loading = false
		return {"ok": false, "error": "Не удалось открыть город. Состояние не изменено."}
	# Старая сцена уже вышла из дерева; новая получит _ready на следующем кадре.
	player._load_spawn_pending = true
	codec.apply(checked.state, player)
	player.last_save_message = "Загружено сохранение после сна."
	await get_tree().scene_changed
	loading = false
	return {"ok": true}
