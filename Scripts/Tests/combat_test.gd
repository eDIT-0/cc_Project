extends Node
## F6 на Scenes/Tests/combat_test.tscn — бой без поиска клетки в лабиринте.
## Только тест: смена сценария восстанавливает HP/выносливость, поражение
## не отбирает предметы и не перемещает игрока, победа не выдаёт опыт.

const RULES: CombatRules = preload("res://Data/Combat/test_combat_rules.tres")
const BANDIT: EnemyData = preload("res://Data/Combat/Profiles/bandit_ai.tres")
const BRUTE: EnemyData = preload("res://Data/Combat/Profiles/brute_ai.tres")
const DOG: EnemyData = preload("res://Data/Combat/Profiles/dog_ai.tres")

const JOINT: EnemyAttack = preload("res://Data/Combat/Attacks/bandit_joint.tres")

const PUNCH: EnemyAttack = preload("res://Data/Combat/Attacks/bandit_punch.tres")
const HOLD: EnemyAttack = preload("res://Data/Combat/Attacks/bandit_hold.tres")

var _use_minigames: bool = RULES.use_defense_minigames
var _mode_button: Button
var _screen: CombatDebugScreen
var _toolbar: PanelContainer
var _toolbar_reopen: Button
var _combat: CombatController
var _result: Label
var _test_inventory: Inventory
var _dog: EnemyData
const SPRAY_EFFECT: ItemEffect = preload("res://Data/Combat/ItemEffects/pepper_spray_combat.tres")
const FIRE_EFFECT: ItemEffect = preload("res://Data/Combat/ItemEffects/molotov_combat.tres")


func _ready() -> void:
	_build_test_inventory()
	_dog = DOG.duplicate() as EnemyData
	_dog.lust_affects_escape = false
	_combat = CombatController.new()
	_combat.inventory_override = _test_inventory
	add_child(_combat)
	_combat.combat_finished.connect(_on_finished)
	_combat.combat_escaped.connect(func(): _result.text = "ПОБЕГ — без опыта. В этой сцене карты нет; перемещение проверяется в лабиринте.")
	var screen := CombatDebugScreen.new()
	screen.combat = _combat
	screen.top_margin = 296.0
	screen.show_ai_debug = true
	_screen = screen
	screen.debug_toolbar_toggle_requested.connect(_toggle_toolbar)
	add_child(screen)
	_build_toolbar()
	_start(1, Encounter.Opening.NORMAL)


func _start(count: int, opening: Encounter.Opening) -> void:
	_combat.abort()
	PlayerState.stats.add_arousal(-PlayerState.stats.arousal)
	PlayerState.stats.restore_all()
	_fill_test_inventory()
	var enemies: Array[EnemyData] = [BANDIT]
	if count > 1:
		enemies.append(BRUTE)
		enemies.append(_dog)
	var enc := Encounter.new(enemies, EncounterTable.new())
	enc.opening = opening
	_result.text = "Тест: отдельный рюкзак. W/S — удары, D — умения, A — уникальная, пробел — предметы. В меню A/D + пробел; Esc — назад. F1 — свернуть/развернуть примеры."
	_combat.minigames_override = _use_minigames
	_combat.start(enc, RULES, Difficulty.Level.NORMAL)


func _on_finished(won: bool) -> void:
	_result.text = "ПОБЕДА — без опыта. Выбери новый сценарий." if won else "ПОРАЖЕНИЕ — без потери вещей. Выбери новый сценарий."


func _change_moods(irritated: bool) -> void:
	if not _combat.is_active():
		return
	for i in _combat.get_alive_indices():
		var brain: EnemyBrain = _combat.fighters[i].brain
		brain.set_emotions(brain.aggression, 80.0 if irritated else brain.irritation, brain.lust if irritated else 80.0)
		_combat.reconsider_intent(i)


func _stun_enemy() -> void:
	if not _combat.is_active():
		return
	var alive := _combat.get_alive_indices()
	if alive.is_empty():
		return
	var index := _combat.selected_target if alive.has(_combat.selected_target) else alive[0]
	_combat.stun_target(index, 4.0)


func _joint_demo() -> void:
	_start(3, Encounter.Opening.NORMAL)
	# У помощника уже есть требуемые 60%. Лидер ещё заряжается: есть
	# время увидеть связанную подготовку и сорвать её оглушением.
	_combat.fighters[0].energy = 80.0
	_combat.fighters[1].energy = 80.0
	if not _combat.debug_force_intent(0, JOINT):
		_result.text = "Совместное намерение не удалось подготовить."


func _build_test_inventory() -> void:
	# Не изменяем ни PlayerState.backpack, ни исходные ItemData ресурсы.
	var catalog := ItemCatalog.new()
	for source in PlayerState.catalog.items:
		if source == null:
			continue
		var item := source.duplicate() as ItemData
		if item.item_id == "pepper_spray":
			var effects: Array[ItemEffect] = [SPRAY_EFFECT]
			item.effects = effects
		elif item.item_id == "molotov":
			var effects: Array[ItemEffect] = [FIRE_EFFECT]
			item.effects = effects
		catalog.items.append(item)
	_test_inventory = Inventory.new(catalog, 8)


func _fill_test_inventory() -> void:
	for slot in range(_test_inventory.get_capacity()):
		_test_inventory.discard_slot(slot)
	var amounts := {"herb_green": 2, "injector": 1, "energy_drink": 1, "pepper_spray": 1, "molotov": 2, "metal_parts_small": 2}
	for id in amounts:
		_test_inventory.add(id, amounts[id])


func _escape_demo() -> void:
	_start(3, Encounter.Opening.NORMAL)
	for i in _combat.get_alive_indices():
		var brain: EnemyBrain = _combat.fighters[i].brain
		brain.set_emotions(brain.aggression, brain.irritation, 0.0)
		_combat.stun_target(i, 4.0)
	_combat.player_energy = 45.0
	_combat.open_menu(CombatController.MenuKind.SKILLS)


func _charm_demo() -> void:
	_start(1, Encounter.Opening.NORMAL)
	var brain: EnemyBrain = _combat.fighters[0].brain
	brain.set_emotions(10.0, 0.0, 30.0)
	_combat.stun_target(0, 4.0)
	_combat.player_energy = 45.0
	_combat.open_menu(CombatController.MenuKind.SKILLS)
	_combat.menu_selection = 1
	_combat.changed.emit()


func _build_toolbar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	# Явный размер и пять строк кнопок: без схлопывающегося ScrollContainer.
	var panel := PanelContainer.new()
	_toolbar = panel
	layer.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = 8
	panel.offset_bottom = 284
	panel.custom_minimum_size.y = 276
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	column.add_child(row)
	_add_button(row, "Один враг", func(): _start(1, Encounter.Opening.NORMAL))
	_add_button(row, "Группа", func(): _start(3, Encounter.Opening.NORMAL))
	_add_button(row, "Засада игрока", func(): _start(3, Encounter.Opening.PLAYER_FIRST))
	_add_button(row, "Засада врагов", func(): _start(3, Encounter.Opening.ENEMY_FIRST))
	_add_button(row, "Похоть ИИ = 80", func(): _change_moods(false))
	_add_button(row, "Раздражение ИИ = 80", func(): _change_moods(true))
	_add_button(row, "Оглушить врага", _stun_enemy)
	_add_button(row, "Оглушить игрока", func(): _combat.stun_target(-1, 4.0))
	_add_button(row, "Совместная — пример", _joint_demo)
	_add_button(row, "Захват — пример", func():
		if _combat.is_active() and not _combat.get_alive_indices().is_empty():
			_combat.immobilize_player(6.0, _combat.get_alive_indices()[0])
	)
	_add_button(row, "Пик возбуждения", func():
		if _combat.is_active():
			PlayerState.stats.add_arousal(CharacterStats.AROUSAL_MAX)
	)
	_add_button(row, "Выносливость в 0", func():
		if _combat.is_active():
			PlayerState.stats.spend_stamina(PlayerState.stats.stamina)
	)
	_add_button(row, "Энергия 100%", func():
		if _combat.is_active() and _combat.state == CombatController.State.CHARGING:
			_combat.player_energy = 100.0
			_combat.changed.emit()
	)
	_add_button(row, "Ранить игрока -10", func():
		if _combat.is_active():
			PlayerState.stats.damage(10)
	)
	_add_button(row, "Побег — пример", _escape_demo)
	_add_button(row, "Отвлечение — пример", _charm_demo)
	_add_button(row, "Стоп-полоса — пример", func(): _defense_demo(CombatDefense.Kind.STOP_BAR))
	_add_button(row, "Нажатия — пример", func(): _defense_demo(CombatDefense.Kind.MASH))
	_mode_button = _add_button(row, "", _toggle_defense_mode)
	_update_mode_label()
	_add_button(row, "Совместная защита", _joint_defense_demo)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_result)
	_toolbar_reopen = Button.new()
	_toolbar_reopen.text = "F1 · Показать примеры"
	_toolbar_reopen.focus_mode = Control.FOCUS_NONE
	_toolbar_reopen.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toolbar_reopen.offset_left = -220
	_toolbar_reopen.offset_right = -16
	_toolbar_reopen.offset_top = 8
	_toolbar_reopen.offset_bottom = 42
	_toolbar_reopen.pressed.connect(_toggle_toolbar)
	layer.add_child(_toolbar_reopen)
	_toolbar_reopen.hide()


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _toggle_defense_mode() -> void:
	if _combat.is_defending():
		return
	_use_minigames = not _use_minigames
	_combat.minigames_override = _use_minigames
	_update_mode_label()


func _update_mode_label() -> void:
	_mode_button.text = "Защита: мини-игры" if _use_minigames else "Защита: авто DEX"


func _defense_demo(kind: CombatDefense.Kind) -> void:
	_start(1, Encounter.Opening.NORMAL)
	# Копии не перезаписывают пользовательские настройки ресурсов.
	_combat.rules = RULES.duplicate() as CombatRules
	_combat.rules.defense_enabled = true
	var attack := (PUNCH if kind == CombatDefense.Kind.STOP_BAR else HOLD).duplicate() as EnemyAttack
	attack.defense_kind = kind
	attack.damage = 10
	attack.stun_seconds = 2.0 if kind == CombatDefense.Kind.STOP_BAR else 0.0
	attack.immobilize_seconds = 6.0 if kind == CombatDefense.Kind.MASH else 0.0
	attack.arousal = 10 if kind == CombatDefense.Kind.MASH else 0
	if _combat.debug_force_intent(0, attack):
		_combat.fighters[0].energy = 100.0
		_combat._process(0.01)
	_result.text = "Защита: идеально — 0 последствий; частично — ослабление; провал — полностью. Пробел/кнопка; Esc — провал."


func _joint_defense_demo() -> void:
	_start(3, Encounter.Opening.NORMAL)
	_combat.rules = RULES.duplicate() as CombatRules
	_combat.rules.defense_enabled = true
	var attack := JOINT.duplicate() as EnemyAttack
	attack.defense_kind = CombatDefense.Kind.MASH
	_combat.fighters[0].energy = 100.0
	_combat.fighters[1].energy = 80.0
	if _combat.debug_force_intent(0, attack):
		_combat._process(0.01)
	_result.text = "Совместная атака — одна защита на обоих врагов, не две подряд. Помощник тратит 60% энергии."


func _toggle_toolbar() -> void:
	_toolbar.visible = not _toolbar.visible
	_toolbar_reopen.visible = not _toolbar.visible
	_screen.top_margin = 296.0 if _toolbar.visible else 52.0
	_screen._relayout()
