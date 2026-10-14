class_name CombatDebugScreen
extends CanvasLayer
## Боевой интерфейс: ромб действий, фигуры/намерения, лента событий.
## Имя класса сохранено для совместимости сцен. Скрытые шкалы — только в тесте.

signal debug_toolbar_toggle_requested

var combat: CombatController
var top_margin: float = 16.0
var show_ai_debug: bool = false
var _root: Control
var _frame: PanelContainer
var _layout_scroll: ScrollContainer
var _body: BoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _enemy_scroll: ScrollContainer
var _status: Label
var _player_hp: ProgressBar
var _player_energy: ProgressBar
var _player_text: Label
var _enemy_row: HBoxContainer
var _cards: Array[Dictionary] = []
var _hand: CombatDiamondButton
var _kick: CombatDiamondButton
var _skills: CombatDiamondButton
var _unique: CombatDiamondButton
var _items: CombatDiamondButton
var _board: Control
var _menu_panel: PanelContainer
var _menu_scroll: ScrollContainer
var _menu_row: HBoxContainer
var _menu_description: Label
var _menu_buttons: Array[Button] = []
var _menu_signature: String = ""
var _confirm: Button
var _cancel: Button
var _selection_row: HBoxContainer
var _messages: RichTextLabel
var _log_panel: PanelContainer
var _log_signature: String = ""
var _compact_mode: bool = false
var _shown_encounter: Encounter


func _ready() -> void:
	layer = 20
	_build_ui()
	_root.hide()
	if combat == null:
		push_error("CombatDebugScreen: CombatController не назначен.")
		return
	combat.changed.connect(_refresh)
	_root.resized.connect(_relayout)
	_relayout()
	_refresh()


func _input(event: InputEvent) -> void:
	if combat == null or not (event is InputEventKey):
		return
	if event.pressed and not event.echo and show_ai_debug and (event.physical_keycode == KEY_F1 or event.keycode == KEY_F1):
		get_viewport().set_input_as_handled()
		debug_toolbar_toggle_requested.emit()
		return
	if not combat.is_active():
		return
	if combat.is_defending():
		return  # Ввод принадлежит отдельному CombatDefenseScreen.
	# Захватываем ввод до DebugMazeView/диалога. У кнопок нет клавиатурного
	# фокуса: пробел подтверждает цель, а не повторяет последнюю GUI-кнопку.
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if combat.state == CombatController.State.MENU:
		match key:
			KEY_A: combat.cycle_menu(-1)
			KEY_D: combat.cycle_menu(1)
			KEY_SPACE: combat.confirm_menu()
			KEY_ESCAPE: combat.close_menu()
	elif combat.state == CombatController.State.TARGETING:
		match key:
			KEY_A: combat.cycle_target(-1)
			KEY_D: combat.cycle_target(1)
			KEY_SPACE: combat.confirm_target()
			KEY_ESCAPE: combat.cancel_target()
	elif combat.state == CombatController.State.CHARGING:
		match key:
			KEY_W: combat.request_attack(CombatController.Attack.HAND)
			KEY_S: combat.request_attack(CombatController.Attack.KICK)
			KEY_D: combat.open_menu(CombatController.MenuKind.SKILLS)
			KEY_A: combat.open_menu(CombatController.MenuKind.UNIQUE)
			KEY_SPACE: combat.open_menu(CombatController.MenuKind.ITEMS)


func _refresh() -> void:
	if _root == null or combat == null:
		return
	_root.visible = combat.is_active()
	if not combat.is_active():
		return
	if _shown_encounter != combat.encounter or _cards.size() != combat.fighters.size():
		_shown_encounter = combat.encounter
		_menu_signature = ""
		_log_signature = ""
		_build_enemy_cards()
	var stats: CharacterStats = PlayerState.stats
	_player_hp.max_value = stats.get_max_hp()
	_player_hp.value = stats.hp
	_player_energy.value = combat.player_energy
	_player_text.text = "HP %d/%d     Энергия %.0f%%     Выносливость %d/%d" % [stats.hp, stats.get_max_hp(), combat.player_energy, stats.stamina, stats.get_max_stamina()]
	if combat.player_immobilized > 0.0:
		_player_text.text += "     ЗАХВАТ"
	var effects: PackedStringArray = []
	if combat.player_delay > 0.0:
		effects.append("Зарядка через %.1f с" % combat.player_delay)
	if combat.player_stun_remaining > 0.0:
		effects.append("Оглушение %.1f с" % combat.player_stun_remaining)
	if combat.player_immobilized > 0.0:
		effects.append("Захват · %s · D: вырваться" % combat.get_grapple_sources_text())
	match combat.state:
		CombatController.State.DEFENDING: _status.text = "ЗАЩИТА · боевые часы остановлены"
		CombatController.State.MENU: _status.text = "ПАУЗА · A/D — выбор, пробел или клик — использовать, Esc — назад"
		CombatController.State.TARGETING: _status.text = "ВЫБЕРИ ЦЕЛЬ · A/D + пробел или клик по фигуре · Esc — назад"
		CombatController.State.RESOLVING: _status.text = combat.last_defense_text if combat.has_defense_feedback() else "Исполнение действия…"
		_: _status.text = " · ".join(effects) if not effects.is_empty() else "БОЙ · выбирай действие, когда оно готово"
	_status.add_theme_color_override("font_color", Color("eac26b") if combat.state in [CombatController.State.MENU, CombatController.State.TARGETING] else Color("aab6c8"))
	for i in range(_cards.size()):
		var card: Dictionary = _cards[i]
		var fighter: Dictionary = combat.fighters[i]
		var enemy: EnemyData = fighter.data
		var alive: bool = fighter.hp > 0
		var selected := combat.state == CombatController.State.TARGETING and combat.selected_target == i
		if card.selected != selected:
			card.panel.add_theme_stylebox_override("panel", _surface(Color("20344c") if selected else Color("17202d"), Color("5e9fe8") if selected else Color("344155")))
			card.selected = selected
		card.figure.modulate = Color(1.25, 1.25, 1.25) if selected else (Color.WHITE if alive else Color(0.4, 0.4, 0.4))
		card.name_button.text = ("› " if selected else "") + "%s #%d" % [enemy.display_name, i + 1]
		card.name_button.disabled = not alive or combat.state != CombatController.State.TARGETING or not combat.get_target_indices().has(i)
		card.hp.max_value = maxi(1, enemy.max_hp)
		card.hp.value = fighter.hp
		card.energy.value = fighter.energy
		var attack: EnemyAttack = fighter.intent
		if fighter.supporting >= 0:
			attack = combat.fighters[int(fighter.supporting)].intent
		card.badge.set_intent(attack, fighter.supporting >= 0, alive)
		card.intent.text = combat.get_intent_text(i)
		card.badge.tooltip_text = card.intent.text + "\nТеги: " + combat.get_intent_tags(i)
		card.intent.tooltip_text = card.badge.tooltip_text
		if card.compact != _compact_mode:
			card.column.add_theme_constant_override("separation", 3 if _compact_mode else 6)
			for style in ["normal", "hover", "pressed", "disabled"]:
				card.name_button.remove_theme_stylebox_override(style)
				if _compact_mode:
					var box: StyleBox = card.name_button.get_theme_stylebox(style).duplicate()
					box.set_content_margin(SIDE_TOP, 2.0)
					box.set_content_margin(SIDE_BOTTOM, 2.0)
					card.name_button.add_theme_stylebox_override(style, box)
			card.compact = _compact_mode
		card.figure.custom_minimum_size.y = 44.0 if _compact_mode else 104.0
		card.name_button.custom_minimum_size.y = 28.0 if _compact_mode else 36.0
		card.info.text = "HP %d/%d · энергия %.0f%%" % [fighter.hp, enemy.max_hp, fighter.energy]
		card.info.tooltip_text = "Задержка зарядки %.1f с" % fighter.delay
		if fighter.delay > 0.0 and not _compact_mode:
			card.info.text += "\nЗарядка через %.1f с" % fighter.delay
		if show_ai_debug:
			var brain: EnemyBrain = fighter.brain
			card.info.tooltip_text += "\n" + brain.get_debug_text()
			if not _compact_mode:
				card.info.text += "\n" + brain.get_debug_text()
	_hand.set_charge(combat.player_energy, combat.rules.hand_energy, combat.can_attack(CombatController.Attack.HAND))
	_kick.set_charge(combat.player_energy, combat.rules.kick_energy, combat.can_attack(CombatController.Attack.KICK))
	_skills.set_charge(combat.player_energy, combat.rules.skill_energy, combat.can_open_menu(CombatController.MenuKind.SKILLS))
	_unique.set_charge(combat.player_energy, _unique_cost(), combat.can_open_menu(CombatController.MenuKind.UNIQUE))
	_items.set_charge(combat.player_energy, combat.rules.item_energy, combat.can_open_menu(CombatController.MenuKind.ITEMS))
	_hand.tooltip_text = "W · Удар рукой\n%.0f%% энергии · %d урона" % [combat.rules.hand_energy, combat.get_attack_damage(CombatController.Attack.HAND)]
	_kick.tooltip_text = "S · Удар ногой\n%.0f%% энергии · %d урона · %d выносливости" % [combat.rules.kick_energy, combat.get_attack_damage(CombatController.Attack.KICK), combat.rules.kick_stamina]
	_skills.tooltip_text = "D · Умения: побег и отвлечение\n%.0f%% энергии" % combat.rules.skill_energy
	if combat.player_immobilized > 0.0:
		_skills.tooltip_text += "\nВырваться из захвата — проверка %s" % combat.rules.break_free_stat
	_unique.tooltip_text = "A · Уникальные атаки\nЦена самой дешёвой доступной по уровню/DEX атаки — %.0f%%" % _unique_cost()
	_items.tooltip_text = "Пробел · Предметы из рюкзака\n%.0f%% энергии; отдельные быстрые ячейки не нужны" % combat.rules.item_energy
	_refresh_menu_ui()
	_menu_panel.visible = combat.state == CombatController.State.MENU
	_selection_row.visible = combat.state == CombatController.State.TARGETING or combat.state == CombatController.State.MENU
	_confirm.visible = _selection_row.visible
	_cancel.visible = _selection_row.visible
	_log_panel.visible = combat.state != CombatController.State.MENU and not (_compact_mode and combat.state == CombatController.State.TARGETING)
	_refresh_log()


func _unique_cost() -> float:
	var cheapest := INF
	for attack in combat.rules.unique_attacks:
		if attack != null and PlayerState.stats.level >= attack.min_level and PlayerState.stats.get_stat("DEX") >= attack.min_dex:
			cheapest = minf(cheapest, attack.energy_cost)
	return 100.0 if is_inf(cheapest) else cheapest


func _refresh_log() -> void:
	var signature := "\n".join(combat.recent_messages)
	if signature == _log_signature:
		return
	_log_signature = signature
	_messages.clear()
	for line in combat.recent_messages:
		var ink := Color("b9c7da")
		if "урона" in line: ink = Color("efb2a8")
		elif "защит" in line.to_lower() or "Частично" in line: ink = Color("a4c5ef")
		elif "Победа" in line or "Побег" in line: ink = Color("a1d1b6")
		_messages.push_color(ink)
		_messages.add_text("• " + line + "\n")
		_messages.pop()


func _build_enemy_cards() -> void:
	for child in _enemy_row.get_children():
		_enemy_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	for i in range(combat.fighters.size()):
		var enemy: EnemyData = combat.fighters[i].data
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size.x = 180
		_enemy_row.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		panel.add_child(column)
		var name_button := _button("", func(): _confirm_pointer_target(i))
		name_button.custom_minimum_size.y = 36
		column.add_child(name_button)
		var figure := TextureRect.new()
		figure.texture = enemy.figure
		figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
		figure.custom_minimum_size = Vector2(140, 104)
		figure.mouse_filter = Control.MOUSE_FILTER_STOP
		figure.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_pointer_target(i)
				figure.accept_event()
			elif event is InputEventScreenTouch and event.pressed:
				_confirm_pointer_target(i)
				figure.accept_event()
		)
		column.add_child(figure)
		if enemy.figure == null:
			column.add_child(_label("Нет фигуры · цель выбирается по имени"))
		var hp := _bar(Color("e97366"))
		column.add_child(hp)
		var intent_row := HBoxContainer.new()
		intent_row.add_theme_constant_override("separation", 8)
		column.add_child(intent_row)
		var badge := CombatIntentBadge.new()
		intent_row.add_child(badge)
		var intent := _label("")
		intent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		intent.mouse_filter = Control.MOUSE_FILTER_PASS
		intent_row.add_child(intent)
		var energy := _bar(Color("de9255"))
		column.add_child(energy)
		var info := _label("")
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color("aab6c8"))
		column.add_child(info)
		_cards.append({"panel": panel, "column": column, "compact": null, "selected": null, "name_button": name_button, "figure": figure, "hp": hp, "energy": energy, "info": info, "intent": intent, "badge": badge})


func _confirm_pointer_target(index: int) -> void:
	if combat.state != CombatController.State.TARGETING or not combat.get_target_indices().has(index):
		return
	combat.select_target(index)
	combat.confirm_target()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = _theme()
	add_child(_root)
	_frame = PanelContainer.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 16
	_frame.offset_right = -16
	_frame.offset_bottom = -16
	_frame.offset_top = top_margin
	_frame.add_theme_stylebox_override("panel", _surface(Color(0.045, 0.065, 0.10, 0.94), Color("344155")))
	_root.add_child(_frame)
	_layout_scroll = ScrollContainer.new()
	_layout_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_layout_scroll)
	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout_scroll.add_child(_body)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 8)
	_body.add_child(_left)
	_player_text = _label("")
	_left.add_child(_player_text)
	var bars := HBoxContainer.new()
	_left.add_child(bars)
	_player_hp = _bar(Color("72bc8f"))
	_player_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_hp.tooltip_text = "Здоровье игрока"
	bars.add_child(_player_hp)
	_player_energy = _bar(Color("5e9fe8"))
	_player_energy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_energy.tooltip_text = "Энергия игрока"
	bars.add_child(_player_energy)
	_status = _label("")
	_left.add_child(_status)
	_enemy_scroll = ScrollContainer.new()
	_enemy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(_enemy_scroll)
	_enemy_row = HBoxContainer.new()
	_enemy_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enemy_row.add_theme_constant_override("separation", 10)
	_enemy_scroll.add_child(_enemy_row)
	_menu_panel = PanelContainer.new()
	_menu_panel.add_theme_stylebox_override("panel", _surface(Color("18263a"), Color("5e9fe8")))
	_left.add_child(_menu_panel)
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 6)
	_menu_panel.add_child(menu_column)
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.custom_minimum_size.y = 72
	_menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_column.add_child(_menu_scroll)
	_menu_row = HBoxContainer.new()
	_menu_row.add_theme_constant_override("separation", 6)
	_menu_scroll.add_child(_menu_row)
	_menu_description = _label("")
	_menu_description.add_theme_font_size_override("font_size", 13)
	menu_column.add_child(_menu_description)
	_selection_row = HBoxContainer.new()
	_left.add_child(_selection_row)
	_confirm = _button("Пробел · Подтвердить", func():
		if combat.state == CombatController.State.MENU: combat.confirm_menu()
		else: combat.confirm_target()
	)
	_cancel = _button("Esc · Назад", func():
		if combat.state == CombatController.State.MENU: combat.close_menu()
		else: combat.cancel_target()
	)
	_selection_row.add_child(_confirm)
	_selection_row.add_child(_cancel)
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", _surface(Color("101824"), Color("2c394c")))
	_log_panel.custom_minimum_size.y = 92
	_left.add_child(_log_panel)
	var log_column := VBoxContainer.new()
	_log_panel.add_child(log_column)
	var log_title := _label("ЛЕНТА БОЯ")
	log_title.add_theme_font_size_override("font_size", 12)
	log_title.add_theme_color_override("font_color", Color("8895a8"))
	log_column.add_child(log_title)
	_messages = RichTextLabel.new()
	_messages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages.custom_minimum_size.y = 50
	_messages.scroll_following = true
	_messages.selection_enabled = true
	_messages.add_theme_font_size_override("normal_font_size", 13)
	log_column.add_child(_messages)
	_right = VBoxContainer.new()
	_right.custom_minimum_size.x = 280
	_right.add_theme_constant_override("separation", 8)
	_body.add_child(_right)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(center)
	_board = Control.new()
	_board.custom_minimum_size = Vector2(272, 272)
	center.add_child(_board)
	_hand = _diamond("Рука", "W", Vector2(92, 0), Color("5e9fe8"), func():
		if not _hand.disabled: combat.request_attack(CombatController.Attack.HAND)
	)
	_skills = _diamond("Умения", "D", Vector2(184, 92), Color("72bc8f"), func():
		if not _skills.disabled: combat.open_menu(CombatController.MenuKind.SKILLS)
	)
	_kick = _diamond("Нога", "S", Vector2(92, 184), Color("de9255"), func():
		if not _kick.disabled: combat.request_attack(CombatController.Attack.KICK)
	)
	_unique = _diamond("Уник.", "A", Vector2(0, 92), Color("bf8eda"), func():
		if not _unique.disabled: combat.open_menu(CombatController.MenuKind.UNIQUE)
	)
	_items = _diamond("Вещи", "SPC", Vector2(104, 104), Color("eac26b"), func():
		if not _items.disabled: combat.open_menu(CombatController.MenuKind.ITEMS)
	)
	_items.compact = true
	_items.size = Vector2(64, 64)
	var hint := _label("W/A/S/D · пробел — предметы")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("8895a8"))
	_right.add_child(hint)


func _relayout() -> void:
	if _body == null:
		return
	_frame.offset_top = top_margin
	var narrow := _root.size.x < 760.0
	_compact_mode = not narrow and _root.size.y - top_margin - 16.0 < 440.0
	_log_panel.custom_minimum_size.y = 64.0 if _compact_mode else 92.0
	_messages.custom_minimum_size.y = 22.0 if _compact_mode else 50.0
	_body.vertical = narrow
	_layout_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if narrow else ScrollContainer.SCROLL_MODE_DISABLED
	_left.custom_minimum_size.y = 380.0 if narrow else 0.0
	_right.custom_minimum_size.y = 304.0 if narrow else 0.0
	_refresh()


func _diamond(caption: String, key: String, position: Vector2, color: Color, callback: Callable) -> CombatDiamondButton:
	var button := CombatDiamondButton.new()
	button.caption = caption
	button.key_caption = key
	button.accent = color
	button.position = position
	button.size = Vector2(88, 88)
	button.pressed.connect(callback)
	_board.add_child(button)
	return button


func _refresh_menu_ui() -> void:
	var opened := combat.state == CombatController.State.MENU
	_menu_scroll.visible = opened
	_menu_description.visible = opened
	if not opened:
		return
	var keys: PackedStringArray = []
	for entry in combat.menu_entries:
		keys.append(entry.key)
	var signature := str(combat.menu_kind) + ":" + "|".join(keys)
	if signature != _menu_signature:
		_menu_signature = signature
		for child in _menu_row.get_children():
			_menu_row.remove_child(child)
			child.queue_free()
		_menu_buttons.clear()
		for i in range(combat.menu_entries.size()):
			var button := _button("", func(): combat.choose_menu(i))
			button.custom_minimum_size = Vector2(140, 64)
			button.add_theme_font_size_override("font_size", 13)
			_menu_row.add_child(button)
			_menu_buttons.append(button)
	for i in range(_menu_buttons.size()):
		var entry: Dictionary = combat.menu_entries[i]
		var button := _menu_buttons[i]
		button.text = ("› " if i == combat.menu_selection else "") + entry.name
		button.tooltip_text = entry.description
		if entry.has("icon"):
			button.icon = entry.icon
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 28)
		if entry.has("count"):
			button.text += " ×%d" % entry.count
			if entry.durability >= 0:
				button.text += "\nПрочность %d" % entry.durability
		button.disabled = not entry.reason.is_empty()
		button.modulate = Color.WHITE
		button.add_theme_stylebox_override("normal", _surface(Color("274567") if i == combat.menu_selection else Color("202d40"), Color("5e9fe8") if i == combat.menu_selection else Color("455268")))
		button.add_theme_stylebox_override("disabled", _surface(Color("152031"), Color("5e9fe8") if i == combat.menu_selection else Color("344155")))
	if combat.menu_entries.is_empty():
		_menu_description.text = "Доступных вариантов нет. Esc — закрыть."
		return
	var selected: Dictionary = combat.menu_entries[combat.menu_selection]
	_menu_description.text = selected.name + " — " + selected.description
	if selected.has("attack"):
		var attack: PlayerCombatAttack = selected.attack
		_menu_description.text += "\n%.0f%% энергии · %d выносливости · оглушение %.1f с" % [attack.energy_cost, attack.stamina_cost, attack.stun_seconds]
	if not selected.reason.is_empty():
		_menu_description.text += "\nНедоступно — " + selected.reason
	call_deferred("_scroll_menu_selection")


func _scroll_menu_selection() -> void:
	if not is_inside_tree() or not is_instance_valid(combat) or combat.state != CombatController.State.MENU:
		return
	# После изменения размера контейнеры ещё могут пересчитать ширину ячеек.
	# Ждём раскладку, затем читаем ТЕКУЩИЙ выбор, не старую кнопку.
	for frame in range(2):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	# Меню могло закрыться/перестроиться до отложенного вызова.
	if not is_instance_valid(combat) or combat.state != CombatController.State.MENU:
		return
	if combat.menu_selection < 0 or combat.menu_selection >= _menu_buttons.size():
		return
	var button := _menu_buttons[combat.menu_selection]
	if is_instance_valid(button) and _menu_scroll.is_ancestor_of(button):
		_menu_scroll.ensure_control_visible(button)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	return button


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("293649")
	background.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", background)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _surface(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 8.0)
	return box


func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", Color("edf2fa"))
	theme.set_color("default_color", "RichTextLabel", Color("b9c7da"))
	for style in ["normal", "hover", "pressed", "disabled"]:
		var bg := Color("202d40")
		var border := Color("455268")
		if style == "hover":
			bg = Color("2a405c")
			border = Color("5e9fe8")
		elif style == "pressed":
			bg = Color("345a85")
		elif style == "disabled":
			bg = Color("17202d")
			border = Color("2c394c")
		theme.set_stylebox(style, "Button", _surface(bg, border))
	theme.set_color("font_color", "Button", Color("edf2fa"))
	theme.set_color("font_disabled_color", "Button", Color("8797ad"))
	return theme
