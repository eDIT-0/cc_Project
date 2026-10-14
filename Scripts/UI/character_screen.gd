extends CanvasLayer
## Автозагрузка "CharacterScreen" (Project Settings -> Autoload, ПОСЛЕ PlayerState).
## ОТЛАДОЧНЫЙ экран персонажа — строится из кода, как InventoryScreen.
## Отдельно от инвентаря специально: когда будет настоящий UI, характеристики
## подвязываются к своему экрану/HUD независимо от рюкзака. Вся логика —
## в CharacterStats (PlayerState.stats), здесь только показ.
##
## C — открыть / закрыть (не поверх диалога и не поверх инвентаря), Esc — закрыть.
## Пока открыт, забирает всю клавиатуру.
## Скрытые эффекты (StatusEffect.hidden) показываются только в debug-сборке,
## с пометкой [скрыт].
## В debug-сборке внизу — кнопки для проверки (урон, выносливость, ...),
## а в тексте — скрытые флаги и счётчики PlayerState.

var _is_open: bool = false
var _root: Control
var _info: RichTextLabel
var _raise_row: HBoxContainer


func _ready() -> void:
	layer = 10
	_build_ui()
	_root.visible = false
	if PlayerState == null or PlayerState.stats == null:
		push_error("CharacterScreen: PlayerState не готов — проверь порядок автозагрузок.")
		return
	PlayerState.stats.changed.connect(_refresh)


func is_open() -> bool:
	return _is_open


func open() -> void:
	if get_tree().get_first_node_in_group("save_load_menu") != null: return
	if get_tree().get_first_node_in_group("active_combat") != null:
		return
	_is_open = true
	_root.visible = true
	_refresh()


func close() -> void:
	_is_open = false
	_root.visible = false


func _input(event: InputEvent) -> void:
	if get_tree().get_first_node_in_group("save_load_menu") != null: return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not _is_open:
		if event.keycode == KEY_C and not _is_blocked():
			get_viewport().set_input_as_handled()
			open()
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_C or event.keycode == KEY_ESCAPE:
		close()


func _is_blocked() -> bool:
	if get_tree().get_first_node_in_group("active_combat") != null:
		return true
	var inventory = get_node_or_null("/root/InventoryScreen")  # без типа: методы вызываются динамически
	if inventory != null and inventory.is_open():
		return true
	var trade = get_node_or_null("/root/TradeManager")
	if trade != null and trade.is_open():
		return true
	for box in get_tree().get_nodes_in_group("dialogue_box"):
		if box.has_method("is_active") and box.is_active():
			return true
	return false


# ====================== ОТРИСОВКА ======================

func _refresh() -> void:
	if not _is_open:
		return
	var st: CharacterStats = PlayerState.stats
	var lines: PackedStringArray = []

	lines.append("[b]Персонаж[/b]   ·   %s   ·   прошло: %s" % [PlayerState.clock.get_date_text(), PlayerState.format_minutes(PlayerState.game_minutes)])
	lines.append("")
	if st.level >= CharacterStats.MAX_LEVEL:
		lines.append("Уровень: %d (максимум)" % st.level)
	else:
		lines.append("Уровень: %d   ·   опыт %d / %d" % [st.level, st.xp, CharacterStats.xp_to_next(st.level)])
	if st.stat_points > 0:
		lines.append("[color=#ff8]Очков характеристик: %d — распредели кнопками ниже[/color]" % st.stat_points)
	lines.append("")
	lines.append("Здоровье: %d / %d" % [st.hp, st.get_max_hp()])
	lines.append("Выносливость: %d / %d" % [st.stamina, st.get_max_stamina()])
	lines.append("Возбуждение: %d / %d" % [st.arousal, CharacterStats.AROUSAL_MAX])
	lines.append("")

	for stat in CharacterStats.STATS:
		var base := st.get_base(stat)
		var mod := st.get_modifier(stat)
		var text := "%s (%s): [b]%d[/b]" % [CharacterStats.STAT_NAMES[stat], stat, st.get_stat(stat)]
		if mod != 0:
			var color: String = "#7f7" if mod > 0 else "#f77"
			text += "   [color=#999]база %d[/color] [color=%s]%+d[/color]" % [base, color, mod]
		lines.append(text)
	lines.append("")

	lines.append("[b]Эффекты[/b]")
	var shown := 0
	for entry in st.get_effects_for_display():
		var effect: StatusEffect = entry.effect
		if effect.hidden and not OS.is_debug_build():
			continue
		var time: String = "пока действует условие" if entry.get("system", false) else (
			"бессрочно" if entry.remaining < 0 else "ещё %s" % PlayerState.format_minutes(entry.remaining))
		var hidden_mark: String = "  [color=#999][скрыт][/color]" if effect.hidden else ""
		lines.append("• %s%s — %s   [color=#aaa](%s)[/color]" % [effect.display_name, hidden_mark, effect.describe_modifiers(), time])
		shown += 1
	if shown == 0:
		lines.append("[color=#999]нет[/color]")

	if OS.is_debug_build():
		var flags := PlayerState.get_debug_flags()
		var values := PlayerState.get_debug_values()
		lines.append("")
		lines.append("[color=#999][отладка] Флаги: %s[/color]" % (", ".join(PackedStringArray(flags.keys())) if not flags.is_empty() else "нет"))
		var parts: PackedStringArray = []
		for key in values:
			parts.append("%s = %d" % [key, values[key]])
		lines.append("[color=#999][отладка] Счётчики: %s[/color]" % (", ".join(parts) if not parts.is_empty() else "нет"))

	_info.text = "\n".join(lines)
	_rebuild_raise_buttons(st)


## "+ Сила" и т.д. — видны, только пока есть нераспределённые очки.
func _rebuild_raise_buttons(st: CharacterStats) -> void:
	for child in _raise_row.get_children():
		_raise_row.remove_child(child)
		child.queue_free()
	_raise_row.visible = st.stat_points > 0
	if not _raise_row.visible:
		return
	for stat in CharacterStats.STATS:
		if stat == "LEW":
			continue
		var button := Button.new()
		button.text = "+ %s" % stat
		button.tooltip_text = CharacterStats.STAT_NAMES[stat]
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not st.can_raise_stat(stat)
		button.pressed.connect(func(): st.raise_stat(stat))
		_raise_row.add_child(button)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(_info)

	_raise_row = HBoxContainer.new()
	_raise_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_raise_row)

	if OS.is_debug_build():
		var debug_row := HFlowContainer.new()
		vbox.add_child(debug_row)
		_make_button(debug_row, "Урон 10", func(): PlayerState.stats.damage(10))
		_make_button(debug_row, "Выносл. −20", func(): PlayerState.stats.spend_stamina(20))
		_make_button(debug_row, "Возбужд. +10", func(): PlayerState.stats.add_arousal(10))
		_make_button(debug_row, "Похоть +5", func(): PlayerState.stats.add_lewdness(5))
		_make_button(debug_row, "Опыт +100", func(): PlayerState.stats.add_xp(100))
		_make_button(debug_row, "+60 мин", func(): PlayerState.advance_time(60))
		_make_button(debug_row, "+6 ч", func(): PlayerState.advance_time(6 * 60))
		_make_button(debug_row, "Привлек. +5", func():
			PlayerState.add_value("attractiveness", 5)
			_refresh())
		_make_button(debug_row, "Отдых (всё восстановить)", func(): PlayerState.stats.restore_all())

	var hint := Label.new()
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.text = "C / Esc — закрыть" + ("   ·   кнопки сверху — отладка" if OS.is_debug_build() else "")
	vbox.add_child(hint)


func _make_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
