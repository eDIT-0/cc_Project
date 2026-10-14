class_name BedSaveCodec
extends RefCounted
## Формат состояния v1. Только JSON-данные и ссылки на ресурсы проекта.
## prepare() проверяет ВСЁ на временных данных, не меняя живую игру.
## apply() сохраняет объекты stats/clock/inventory и их сигнальные подписки.

const MAX_NUMBER := 1000000000000
var error: String = ""


func capture(player) -> Dictionary:
	var quest = player.get_node_or_null("/root/QuestManager")
	var trade = player.get_node_or_null("/root/TradeManager")
	var game = player.get_node_or_null("/root/GameManager")
	if quest == null or trade == null or game == null:
		return _fail("Не готовы менеджеры квестов, торговли или игры.")
	var st: CharacterStats = player.stats
	var effects: Array = []
	for entry in st._effects:
		var effect: StatusEffect = entry.effect
		if effect.resource_path.is_empty():
			return _fail("Эффект «%s» не имеет ресурса для сохранения." % effect.display_name)
		effects.append({"path": effect.resource_path, "id": effect.effect_id, "remaining": entry.remaining})
	var active: Array = []
	for location in quest._active_side_quests:
		for difficulty in quest._active_side_quests[location]:
			active.append({"location": location, "difficulty": int(difficulty), "id": quest._active_side_quests[location][difficulty]})
	var stocks: Dictionary = {}
	for id in trade._stocks:
		if not trade._restock_each_run_ids.has(id):
			stocks[id] = trade._stocks[id].duplicate(true)
	var data := {
		"schema": 1, "home": "apartment", "minutes": player.clock.minutes,
		"money": player.money, "flags": player._flags.duplicate(true), "values": player._values.duplicate(true),
		"backpack": _inventory_data(player.backpack), "stash": _inventory_data(player.stash),
		"stats": {"base": st._base.duplicate(), "level": st.level, "xp": st.xp,
			"points": st.stat_points, "hp": st.hp, "stamina": st.stamina, "arousal": st.arousal, "effects": effects},
		"quests": {"active": active, "completed": quest._completed_quests.duplicate(), "rewarded": quest._rewarded_side_quests.duplicate()},
		"trade": {"stocks": stocks, "prices": trade._price_factors.duplicate()},
		"difficulty": int(game.current_difficulty), "saved_at_utc": Time.get_datetime_string_from_system(true)
	}
	var checked := prepare(data, player.catalog)
	return {"ok": true, "data": data} if checked.ok else checked


func _inventory_data(inv: Inventory) -> Array:
	var slots: Array = []
	for index in range(inv.get_capacity()):
		slots.append(inv.get_slot(index))
	return slots


func prepare(data: Variant, catalog: ItemCatalog) -> Dictionary:
	error = ""
	if not data is Dictionary or catalog == null:
		return _fail("Сохранение не содержит корректного состояния игры.")
	if not _integer(data.get("schema"), 1, 1) or data.get("home") != "apartment":
		return _fail("Неизвестная версия или точка сохранения.")
	if not _integer(data.get("minutes"), GameClock.START_MINUTES, 1000000000) or not _integer(data.get("money"), 0, MAX_NUMBER):
		return _fail("Некорректное время или деньги.")
	if not _integer(data.get("difficulty"), 0, Difficulty.Level.size() - 1) or not _text(data.get("saved_at_utc"), 64):
		return _fail("Некорректные параметры сохранения.")
	if not _mapping(data.get("flags"), "bool") or not _mapping(data.get("values"), "int"):
		return _fail("Некорректные сюжетные флаги или счётчики.")
	var backpack := _slots(data.get("backpack"), catalog)
	if not error.is_empty(): return _fail(error)
	var stash := _slots(data.get("stash"), catalog)
	if not error.is_empty(): return _fail(error)
	var st := _stats(data.get("stats"))
	if st == null: return _fail(error)
	var quests: Variant = data.get("quests")
	if not quests is Dictionary or not _mapping(quests.get("completed"), "text") or not _mapping(quests.get("rewarded"), "bool"):
		return _fail("Некорректный журнал квестов.")
	var active_rows: Variant = quests.get("active")
	if not active_rows is Array or active_rows.size() > 4096:
		return _fail("Некорректные активные квесты.")
	var active: Dictionary = {}
	for row in active_rows:
		if not row is Dictionary or not _text(row.get("location")) or not _text(row.get("id")) or not _integer(row.get("difficulty"), 0, Difficulty.Level.size() - 1):
			return _fail("Некорректная запись активного квеста.")
		var location: String = row.location
		var difficulty := int(row.difficulty)
		if not active.has(location): active[location] = {}
		if active[location].has(difficulty): return _fail("Два квеста занимают один слот.")
		active[location][difficulty] = row.id
	var trade: Variant = data.get("trade")
	if not trade is Dictionary or not _mapping(trade.get("prices"), "price") or not trade.get("stocks") is Dictionary or trade.stocks.size() > 4096:
		return _fail("Некорректное состояние торговли.")
	var stocks: Dictionary = {}
	for id in trade.stocks:
		var offers: Variant = trade.stocks[id]
		if not _text(id) or not offers is Array or offers.size() > 4096:
			return _fail("Некорректный ассортимент торговца.")
		var rows: Array = []
		for offer in offers:
			if not offer is Dictionary or not _text(offer.get("item_id")) or not _integer(offer.get("count"), 0, 999999):
				return _fail("Некорректная позиция торговца.")
			var item := catalog.get_item(offer.item_id)
			if item == null or int(offer.count) > item.get_stack_limit():
				return _fail("Неизвестный предмет или неверный остаток у торговца.")
			rows.append({"item_id": offer.item_id, "count": int(offer.count)})
		stocks[id] = rows
	var values: Dictionary = {}
	for key in data.values: values[key] = int(data.values[key])
	return {"ok": true, "state": {"minutes": int(data.minutes), "money": int(data.money), "flags": data.flags.duplicate(),
		"values": values, "backpack": backpack, "stash": stash, "stats": st,
		"active": active, "completed": quests.completed.duplicate(), "rewarded": quests.rewarded.duplicate(),
		"stocks": stocks, "prices": trade.prices.duplicate(), "difficulty": int(data.difficulty)}, "data": data}


func _slots(raw: Variant, catalog: ItemCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array or raw.is_empty() or raw.size() > 4096:
		error = "Некорректная вместимость инвентаря."
		return result
	for row in raw:
		if not row is Dictionary:
			error = "Некорректная ячейка инвентаря."; return []
		if row.is_empty():
			result.append({}); continue
		if not _text(row.get("item_id")) or not _integer(row.get("count"), 1, 999999):
			error = "Некорректный предмет в инвентаре."; return []
		var item := catalog.get_item(row.item_id)
		if item == null:
			error = "В каталоге больше нет предмета «%s»." % row.item_id; return []
		if int(row.count) > item.get_stack_limit():
			error = "Количество превышает размер стака «%s»." % item.display_name; return []
		var slot := {"item_id": row.item_id, "count": int(row.count)}
		if item.has_durability():
			if not _integer(row.get("durability"), 1, item.max_durability):
				error = "Некорректная прочность «%s»." % item.display_name; return []
			slot["durability"] = int(row.durability)
		elif row.has("durability"):
			error = "Прочность задана для предмета без износа."; return []
		result.append(slot)
	return result


func _stats(raw: Variant) -> CharacterStats:
	if not raw is Dictionary or not raw.get("base") is Dictionary or raw.base.size() != CharacterStats.STATS.size():
		error = "Некорректные характеристики."; return null
	var st := CharacterStats.new()
	for stat in CharacterStats.STATS:
		var limit := 100 if stat == "LEW" else 100000
		if not _integer(raw.base.get(stat), 0, limit):
			error = "Некорректная характеристика %s." % stat; return null
		st._base[stat] = int(raw.base[stat])
	if not _integer(raw.get("level"), 1, CharacterStats.MAX_LEVEL) or not _integer(raw.get("points"), 0, 100000) or not _integer(raw.get("xp"), 0, MAX_NUMBER):
		error = "Некорректные уровень, опыт или очки."; return null
	st.level = int(raw.level); st.xp = int(raw.xp); st.stat_points = int(raw.points)
	if (st.level < CharacterStats.MAX_LEVEL and st.xp >= CharacterStats.xp_to_next(st.level)) or (st.level == CharacterStats.MAX_LEVEL and st.xp != 0):
		error = "Опыт не соответствует уровню."; return null
	if not _integer(raw.get("arousal"), 0, CharacterStats.AROUSAL_MAX - 1) or not raw.get("effects") is Array or raw.effects.size() > 256:
		error = "Некорректное возбуждение или эффекты."; return null
	st.arousal = int(raw.arousal)
	var used: Dictionary = {}
	for entry in raw.effects:
		if not entry is Dictionary or not _text(entry.get("path"), 1024) or not _text(entry.get("id")) or not _integer(entry.get("remaining"), -1, 1000000000) or int(entry.remaining) == 0:
			error = "Некорректный эффект состояния."; return null
		var path: String = entry.path
		if not path.begins_with("res://") or ".." in path or path.split("::")[0].get_extension() != "tres" or not ResourceLoader.exists(path):
			error = "Не найден ресурс эффекта «%s»." % entry.id; return null
		var effect := load(path) as StatusEffect
		if effect == null or effect.effect_id != entry.id:
			error = "Ресурс эффекта «%s» изменился." % entry.id; return null
		var key := "group:" + effect.group if not effect.group.is_empty() else "id:" + effect.effect_id
		if used.has(key):
			error = "Эффект или группа сохранены дважды."; return null
		used[key] = true
		st._effects.append({"effect": effect, "remaining": int(entry.remaining)})
	if not _integer(raw.get("hp"), 1, st.get_max_hp()) or not _integer(raw.get("stamina"), 0, st.get_max_stamina()):
		error = "Некорректное здоровье или выносливость."; return null
	st.hp = int(raw.hp); st.stamina = int(raw.stamina)
	return st


func apply(state: Dictionary, player) -> void:
	# Вызывается только после успешного prepare() и удаления старой сцены.
	var st: CharacterStats = state.stats
	var live: CharacterStats = player.stats
	live._base = st._base.duplicate(); live._effects.assign(st._effects)
	live.level = st.level; live.xp = st.xp; live.stat_points = st.stat_points
	live.hp = st.hp; live.stamina = st.stamina; live.arousal = st.arousal
	player.backpack._slots.assign(state.backpack); player.stash._slots.assign(state.stash)
	player.money = state.money; player._flags = state.flags.duplicate(); player._values = state.values.duplicate()
	var clock: GameClock = player.clock
	var old_phase := clock.phase
	clock.minutes = state.minutes; clock.phase = GameClock._phase_for(clock.minutes)
	var quest = player.get_node_or_null("/root/QuestManager")
	quest._active_side_quests = state.active.duplicate(true)
	quest._completed_quests = state.completed.duplicate(); quest._rewarded_side_quests = state.rewarded.duplicate()
	quest._main_quest_completed = false
	var trade = player.get_node_or_null("/root/TradeManager")
	trade._stocks = state.stocks.duplicate(true); trade._price_factors = state.prices.duplicate()
	trade._restock_each_run_ids.clear()
	var game = player.get_node_or_null("/root/GameManager")
	game.clear_run(); game.current_difficulty = state.difficulty
	player.in_dungeon = false
	player.backpack.changed.emit(); player.stash.changed.emit(); player.money_changed.emit(player.money)
	live.changed.emit()
	clock.time_changed.emit()
	# Это восстановление, не новый день: day_changed НЕ эмитим, иначе торговля
	# перетасует только что загруженные товары. Эффекты/опыт тоже не тикаем.
	if clock.phase != old_phase: clock.phase_changed.emit(clock.phase)


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


func _text(value: Variant, limit: int = 256) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit


func _mapping(value: Variant, kind: String) -> bool:
	if not value is Dictionary or value.size() > 10000: return false
	for key in value:
		if not _text(key): return false
		var entry: Variant = value[key]
		match kind:
			"bool":
				if not entry is bool: return false
			"int":
				if not _integer(entry, -MAX_NUMBER, MAX_NUMBER): return false
			"text":
				if not _text(entry, 1024): return false
			"price":
				if not (entry is int or entry is float) or not is_finite(float(entry)) or entry < 0.0 or entry > 1000000: return false
	return true


func _fail(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": message}
