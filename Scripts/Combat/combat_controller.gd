class_name CombatController
extends Node
## Ядро боя, без UI и без смены сцен. DungeonRun обрабатывает итог.
## Не ставит SceneTree на паузу: останавливает только свои боевые часы.
## Индексы врагов стабильны до конца встречи; EnemyData не изменяются.

signal changed
signal combat_finished(won: bool)
## Отдельный исход: не победа и не поражение.
signal combat_escaped
signal defense_completed(grade: CombatDefense.Grade)
## Контракт будущего обработчика реакций. -1 обозначает игрока.
## Пока сигнал никто не читает; портрет/анимации сюда не привязаны.
signal reaction_requested(tags: PackedStringArray, actor_index: int, target_index: int)

enum State { IDLE, CHARGING, TARGETING, RESOLVING, FINISHED, MENU, DEFENDING }
enum MenuKind { NONE, ITEMS, SKILLS, UNIQUE }
enum Command { NONE, ATTACK, ITEM, CHARM, UNIQUE }
enum Attack { NONE, HAND, KICK }

## Тестовая сцена использует отдельный рюкзак, не меняя настоящий.
var inventory_override: Inventory
var escape_allowed: bool = true
var menu_kind: MenuKind = MenuKind.NONE
var menu_entries: Array[Dictionary] = []
var menu_selection: int = 0
var pending_command: Command = Command.NONE
var _return_menu: MenuKind = MenuKind.NONE
var _pending_item_slot: int = -1
var _pending_item_token: Dictionary = {}
var _pending_unique: PlayerCombatAttack
var _observed_inventory: Inventory
var _escape_after_action: bool = false

var defense: CombatDefense
var defense_title: String = ""
var last_defense_text: String = ""
## null — взять настройку из CombatRules; тест переключает режим без
## изменения общего ресурса. bool false означает автоматический бросок.
var minigames_override: Variant = null
var _pending_enemy_attack: Dictionary = {}
var _show_defense_feedback: bool = false

var rules: CombatRules
var encounter: Encounter
var state: State = State.IDLE
var player_energy: float = 0.0
var player_delay: float = 0.0
var player_immobilized: float = 0.0
var player_stun_remaining: float = 0.0
var _grapple_sources: Array[int] = []
var _player_stun_chain: int = 0
var _player_stun_memory: float = 0.0
var _player_stun_guard: float = 0.0
var _fallback_attack: EnemyAttack = EnemyAttack.new()
## HP/энергия/EnemyBrain/намерение — отдельные экземпляры, не EnemyData.
var fighters: Array[Dictionary] = []
var selected_target: int = -1
var pending_attack: Attack = Attack.NONE
var message: String = ""
var recent_messages: PackedStringArray = []

var _active: bool = false
var _difficulty: int = 1
var _action_remaining: float = 0.0
var _win_after_action: bool = false
var _next_enemy: int = 0


func _ready() -> void:
	PlayerState.stats.died.connect(_on_player_died)
	PlayerState.stats.arousal_peaked.connect(_on_arousal_peaked)
	PlayerState.stats.changed.connect(_on_sources_changed)
	_observed_inventory = get_inventory()
	_observed_inventory.changed.connect(_on_sources_changed)
	var defense_screen := CombatDefenseScreen.new()
	defense_screen.combat = self
	add_child(defense_screen)


func _exit_tree() -> void:
	if PlayerState.stats.changed.is_connected(_on_sources_changed):
		PlayerState.stats.changed.disconnect(_on_sources_changed)
	if _observed_inventory != null and _observed_inventory.changed.is_connected(_on_sources_changed):
		_observed_inventory.changed.disconnect(_on_sources_changed)
	if PlayerState.stats.died.is_connected(_on_player_died):
		PlayerState.stats.died.disconnect(_on_player_died)
	if PlayerState.stats.arousal_peaked.is_connected(_on_arousal_peaked):
		PlayerState.stats.arousal_peaked.disconnect(_on_arousal_peaked)


func start(enc: Encounter, settings: CombatRules, difficulty: int) -> void:
	abort()
	encounter = enc
	rules = settings if settings != null else CombatRules.new()
	_difficulty = difficulty
	fighters.clear()
	recent_messages.clear()
	player_energy = 0.0
	player_delay = 0.0
	player_immobilized = 0.0
	player_stun_remaining = 0.0
	_grapple_sources.clear()
	_player_stun_chain = 0
	_player_stun_memory = 0.0
	_player_stun_guard = 0.0
	pending_attack = Attack.NONE
	selected_target = -1
	_action_remaining = 0.0
	_win_after_action = false
	_escape_after_action = false
	_next_enemy = 0
	for enemy in enc.enemies:
		fighters.append({
			"data": enemy, "hp": maxi(1, enemy.max_hp), "energy": 0.0, "delay": 0.0,
			"brain": EnemyBrain.new(enemy), "intent": null, "previous": null,
			"partner": -1, "supporting": -1, "avoid_previous": false,
		})
	if enc.saved_enemy_state.size() == fighters.size():
		for i in range(fighters.size()):
			var saved: Dictionary = enc.saved_enemy_state[i]
			fighters[i].hp = clampi(int(saved.get("hp", fighters[i].hp)), 0, int(fighters[i].data.max_hp))
			var brain: EnemyBrain = fighters[i].brain
			brain.set_emotions(float(saved.get("aggression", brain.aggression)), float(saved.get("irritation", brain.irritation)), float(saved.get("lust", brain.lust)))
	state = State.CHARGING
	_active = true
	add_to_group("active_combat")
	match enc.opening:
		Encounter.Opening.PLAYER_FIRST:
			for i in range(fighters.size()):
				interrupt_energy(i, rules.ambush_delay_seconds)
		Encounter.Opening.ENEMY_FIRST:
			interrupt_energy(-1, rules.ambush_delay_seconds)
	_refresh_intents()
	_log(enc.get_opening_text())
	_notify_changed()
	if PlayerState.stats.hp <= 0:
		_finish(false)
	elif fighters.is_empty():
		_finish(true)


func abort() -> void:
	_clear_defense()
	last_defense_text = ""
	_active = false
	state = State.IDLE
	pending_attack = Attack.NONE
	_clear_pending()
	menu_kind = MenuKind.NONE
	menu_entries.clear()
	_escape_after_action = false
	player_immobilized = 0.0
	player_stun_remaining = 0.0
	_grapple_sources.clear()
	if is_in_group("active_combat"):
		remove_from_group("active_combat")
	_notify_changed()


func is_active() -> bool:
	return _active


func get_alive_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(fighters.size()):
		if fighters[i].hp > 0:
			indices.append(i)
	return indices


func get_player_speed() -> float:
	var dex_multiplier := maxf(0.1, 1.0 + (PlayerState.stats.get_stat("DEX") - 5) * rules.dex_speed_per_point)
	var exhaustion := rules.exhausted_speed_multiplier if PlayerState.stats.stamina <= 0 else 1.0
	var grapple_multiplier := rules.immobilized_speed_multiplier if player_immobilized > 0.0 else 1.0
	return 100.0 / maxf(0.1, rules.player_charge_seconds) * maxf(0.01, rules.player_speed_multiplier) * dex_multiplier * exhaustion * grapple_multiplier


func get_enemy_speed(index: int) -> float:
	var enemy: EnemyData = fighters[index].data
	var difficulty_multiplier := 1.0
	if _difficulty >= 0 and _difficulty < rules.enemy_difficulty_speed.size():
		difficulty_multiplier = maxf(0.01, rules.enemy_difficulty_speed[_difficulty])
	return 100.0 / maxf(0.1, enemy.charge_seconds) * maxf(0.01, enemy.speed_multiplier) * difficulty_multiplier


func get_attack_cost(attack: Attack) -> float:
	return rules.hand_energy if attack == Attack.HAND else rules.kick_energy


func get_attack_damage(attack: Attack) -> int:
	var strength: int = PlayerState.stats.get_stat("STR")
	if attack == Attack.HAND:
		return maxi(1, roundi(rules.hand_base_damage + strength * rules.hand_damage_per_str))
	return maxi(1, roundi(rules.kick_base_damage + strength * rules.kick_damage_per_str))


func can_attack(attack: Attack) -> bool:
	return _active and state == State.CHARGING and attack != Attack.NONE and (attack != Attack.KICK or player_immobilized <= 0.0) and player_delay <= 0.0 and player_energy + 0.0001 >= get_attack_cost(attack)


func request_attack(attack: Attack) -> void:
	if not can_attack(attack):
		return
	var alive := get_alive_indices()
	if alive.is_empty():
		return
	pending_attack = attack
	pending_command = Command.ATTACK
	_return_menu = MenuKind.NONE
	_request_target_selection()


func cycle_target(direction: int) -> void:
	if not _active or state != State.TARGETING:
		return
	var alive := get_target_indices()
	if alive.is_empty():
		return
	var position := alive.find(selected_target)
	selected_target = alive[posmod(position + direction, alive.size())]
	_notify_changed()


func select_target(index: int) -> void:
	if _active and state == State.TARGETING and get_target_indices().has(index):
		selected_target = index
		_notify_changed()


func confirm_target() -> void:
	if _active and state == State.TARGETING:
		_execute_selected_action()


func cancel_target() -> void:
	if not _active or state != State.TARGETING:
		return
	var back := _return_menu
	_clear_pending()
	if back != MenuKind.NONE:
		menu_kind = back
		state = State.MENU
		_refresh_menu()
	else:
		state = State.CHARGING
	_notify_changed()


## Общая блокировка для засады, пика и оглушения.
## target_index: -1 — игрок, иначе индекс противника.
## Энергия в 0; новая задержка не складывается с оставшейся.
func interrupt_energy(target_index: int, seconds: float) -> void:
	if not _active:
		return
	var duration := maxf(0.0, seconds)
	if target_index == -1:
		player_energy = 0.0
		player_delay = maxf(player_delay, duration)
		if state == State.TARGETING or state == State.MENU:
			_clear_pending()
			menu_kind = MenuKind.NONE
			state = State.CHARGING
	elif target_index >= 0 and target_index < fighters.size() and fighters[target_index].hp > 0:
		fighters[target_index].energy = 0.0
		fighters[target_index].delay = maxf(float(fighters[target_index].delay), duration)
		_clear_plan(target_index, true)
		_refresh_intents()
	else:
		return
	_notify_changed()


func _process(delta: float) -> void:
	if not _active:
		return
	if state == State.DEFENDING:
		# Только часы мини-игры. Нет зарядки, эффектов, ИИ или кулдаунов.
		defense.advance(minf(maxf(delta, 0.0), 0.1))
		if defense.is_finished():
			_complete_defense(defense.grade)
		else:
			_notify_changed()
		return
	if state == State.RESOLVING:
		_action_remaining = maxf(0.0, _action_remaining - delta)
		if _action_remaining <= 0.0:
			if _escape_after_action:
				_finish_escape()
			elif _win_after_action:
				_finish(true)
			else:
				state = State.CHARGING
				_notify_changed()
		return
	if state != State.CHARGING:
		return

	# Не переносим большой скачок времени после зависания окна в очередь атак.
	var elapsed := minf(delta, 0.25)
	_advance_effects(elapsed)
	var charging_seconds := maxf(0.0, elapsed - player_delay)
	player_delay = maxf(0.0, player_delay - elapsed)
	player_energy = minf(100.0, player_energy + get_player_speed() * charging_seconds)
	for i in get_alive_indices():
		var enemy_charging := maxf(0.0, elapsed - float(fighters[i].delay))
		fighters[i].delay = maxf(0.0, float(fighters[i].delay) - elapsed)
		fighters[i].energy = minf(100.0, float(fighters[i].energy) + get_enemy_speed(i) * enemy_charging)
		var brain: EnemyBrain = fighters[i].brain
		if brain.advance(elapsed, float(PlayerState.get_attractiveness())):
			_clear_plan(i)
	_refresh_intents()

	# Один исполнитель за раз. Готовые союзники ждут конца его действия;
	# после действия первого проверяем следующего, а не снова первого.
	for offset in range(fighters.size()):
		var index := (_next_enemy + offset) % fighters.size()
		if fighters[index].hp > 0 and fighters[index].delay <= 0.0 and fighters[index].energy >= 100.0 and fighters[index].supporting < 0:
			_next_enemy = (index + 1) % fighters.size()
			_execute_enemy_attack(index)
			return
	_notify_changed()


func _begin_action() -> void:
	defense = null
	_show_defense_feedback = false
	state = State.RESOLVING
	_action_remaining = maxf(0.05, rules.action_seconds)
	_win_after_action = false
	_escape_after_action = false
	menu_kind = MenuKind.NONE


func _execute_player_attack() -> void:
	var attack := pending_attack
	if attack == Attack.NONE or not get_alive_indices().has(selected_target):
		cancel_target()
		return
	if player_delay > 0.0 or (attack == Attack.KICK and player_immobilized > 0.0) or player_energy + 0.0001 < get_attack_cost(attack):
		cancel_target()
		return
	_begin_action()
	_clear_pending()
	player_energy = maxf(0.0, player_energy - get_attack_cost(attack))
	if attack == Attack.KICK:
		PlayerState.stats.spend_stamina(rules.kick_stamina)
	var damage := get_attack_damage(attack)
	var enemy: EnemyData = fighters[selected_target].data
	var attack_name := "Удар рукой" if attack == Attack.HAND else "Удар ногой"
	_log("%s → %s: %d урона." % [attack_name, enemy.display_name, damage])
	var attack_tag := "hand" if attack == Attack.HAND else "kick"
	_damage_enemy(selected_target, damage, PackedStringArray(["strike", attack_tag]), attack == Attack.KICK)
	_notify_changed()


func _execute_enemy_attack(index: int) -> void:
	var attack: EnemyAttack = fighters[index].intent
	if attack == null or not _is_plan_valid(index):
		_clear_plan(index)
		_refresh_intents()
		return
	var partner: int = fighters[index].partner
	_begin_action()
	fighters[index].energy = 0.0
	var brain: EnemyBrain = fighters[index].brain
	brain.mark_used(attack)
	if partner >= 0:
		fighters[partner].energy = maxf(0.0, float(fighters[partner].energy) - attack.partner_energy)
		var partner_brain: EnemyBrain = fighters[partner].brain
		partner_brain.mark_used(attack)
	_clear_plan(index)
	var enemy: EnemyData = fighters[index].data
	var damage := maxi(0, enemy.attack_damage if attack.damage < 0 else attack.damage)
	var participants := enemy.display_name
	if partner >= 0:
		var partner_enemy: EnemyData = fighters[partner].data
		participants += " + " + partner_enemy.display_name
	defense_title = "%s — %s" % [participants, attack.display_name]
	_pending_enemy_attack = {"index": index, "partner": partner, "attack": attack, "damage": damage}
	_emit_attack_reaction(attack, "attack", index)
	if partner >= 0:
		_emit_attack_reaction(attack, "attack", partner)
	var kind := _get_defense_kind(enemy, attack)
	if kind == CombatDefense.Kind.NONE:
		_apply_pending_enemy_attack(CombatDefense.Grade.FAIL, false)
		return
	var difficulty := _get_defense_difficulty(enemy, attack)
	var minigames: bool = bool(minigames_override) if minigames_override != null else rules.use_defense_minigames
	if not minigames:
		var grade := _roll_auto_defense(difficulty)
		_complete_defense(grade)
		return
	defense = CombatDefense.new()
	defense.configure(kind, rules, PlayerState.stats.get_stat("DEX"), difficulty)
	state = State.DEFENDING
	_log("Защита — %s." % attack.display_name)
	_notify_changed()


func is_defending() -> bool:
	return _active and state == State.DEFENDING and defense != null


func has_defense_feedback() -> bool:
	return _active and state == State.RESOLVING and _show_defense_feedback


func defense_press() -> void:
	if not is_defending():
		return
	defense.press()
	if defense.is_finished():
		_complete_defense(defense.grade)
	else:
		_notify_changed()


func defense_fail() -> void:
	if not is_defending():
		return
	defense.fail()
	_complete_defense(CombatDefense.Grade.FAIL)


func _clear_defense() -> void:
	defense = null
	_pending_enemy_attack.clear()
	_show_defense_feedback = false


func _get_defense_kind(enemy: EnemyData, attack: EnemyAttack) -> CombatDefense.Kind:
	if not rules.defense_enabled:
		return CombatDefense.Kind.NONE
	if attack.defense_kind != CombatDefense.Kind.AUTO:
		return attack.defense_kind
	if enemy.defense_kind == CombatDefense.Kind.NONE:
		return CombatDefense.Kind.NONE
	if attack.joint or attack.tags.has("grapple") or attack.tags.has("joint"):
		return CombatDefense.Kind.MASH
	if enemy.defense_kind != CombatDefense.Kind.AUTO:
		return enemy.defense_kind
	return CombatDefense.Kind.STOP_BAR if rules.default_defense_kind == CombatDefense.Kind.AUTO else rules.default_defense_kind


func _get_defense_difficulty(enemy: EnemyData, attack: EnemyAttack) -> float:
	var multiplier := enemy.defense_difficulty * attack.defense_difficulty
	if attack.joint:
		multiplier *= rules.defense_joint_difficulty
	return clampf(multiplier, 0.25, 4.0)


func _roll_auto_defense(difficulty: float) -> CombatDefense.Grade:
	var check_difficulty := maxi(0, rules.defense_auto_difficulty + roundi((difficulty - 1.0) * 5.0))
	var chance := PlayerState.stats.get_check_chance("DEX", check_difficulty)
	var roll := randf()  # Один бросок, не две независимые проверки.
	print("🛡 Автозащита DEX: идеально %d%% (сложность %d)." % [roundi(chance * 100), check_difficulty])
	if roll < chance:
		return CombatDefense.Grade.PERFECT
	if roll < chance + (1.0 - chance) * rules.defense_auto_partial_fraction:
		return CombatDefense.Grade.PARTIAL
	return CombatDefense.Grade.FAIL


func _complete_defense(grade: CombatDefense.Grade) -> void:
	# После перезапуска/поражения старая защита не может применить атаку.
	if not _active or _pending_enemy_attack.is_empty() or grade == CombatDefense.Grade.PENDING:
		return
	state = State.RESOLVING
	_show_defense_feedback = true
	last_defense_text = "Идеальная защита." if grade == CombatDefense.Grade.PERFECT else ("Частично — последствия ослаблены." if grade == CombatDefense.Grade.PARTIAL else "Провал — атака проходит полностью.")
	_log(last_defense_text)
	_apply_pending_enemy_attack(grade, true)
	defense_completed.emit(grade)


func _apply_pending_enemy_attack(grade: CombatDefense.Grade, defended: bool) -> void:
	if not _active or _pending_enemy_attack.is_empty():
		return
	# Снимаем пакет ДО сигналов и damage(): защита от повторной обработки.
	var pending := _pending_enemy_attack.duplicate()
	_pending_enemy_attack.clear()
	var index: int = pending.index
	var partner: int = pending.partner
	var attack: EnemyAttack = pending.attack
	var damage_multiplier := 1.0
	var effect_multiplier := 1.0
	if grade == CombatDefense.Grade.PERFECT:
		damage_multiplier = clampf(rules.defense_perfect_damage, 0.0, 1.0)
		effect_multiplier = clampf(rules.defense_perfect_effects, 0.0, 1.0)
	elif grade == CombatDefense.Grade.PARTIAL:
		damage_multiplier = clampf(rules.defense_partial_damage, 0.0, 1.0)
		effect_multiplier = clampf(rules.defense_partial_effects, 0.0, 1.0)
	var damage := ceili(int(pending.damage) * damage_multiplier)
	var arousal := ceili(attack.arousal * effect_multiplier)
	var stun := attack.stun_seconds * effect_multiplier
	var grapple := attack.immobilize_seconds * effect_multiplier
	_log("%s — %d урона, +%d возбуждения." % [defense_title, damage, arousal])
	if defended:
		var tags := PackedStringArray(["combat", "defense", "perfect" if grade == CombatDefense.Grade.PERFECT else ("partial" if grade == CombatDefense.Grade.PARTIAL else "failure")])
		for tag in attack.tags:
			if not tags.has(tag):
				tags.append(tag)
		reaction_requested.emit(tags, -1, index)
	if damage > 0 or arousal > 0 or stun > 0.0 or grapple > 0.0:
		_emit_attack_reaction(attack, "hit", index)
	PlayerState.stats.damage(damage)
	if not _active:
		return
	if stun > 0.0:
		stun_target(-1, stun)
	if grapple > 0.0:
		immobilize_player(grapple, index, partner)
	if arousal > 0:
		PlayerState.stats.add_arousal(arousal)
	if not _active:
		return
	_refresh_intents()
	_notify_changed()


func _emit_attack_reaction(attack: EnemyAttack, event_tag: String, actor: int) -> void:
	var tags := PackedStringArray(["combat", event_tag])
	for tag in attack.tags:
		if not tags.has(tag):
			tags.append(tag)
	if attack.joint and not tags.has("joint"):
		tags.append("joint")
	reaction_requested.emit(tags, actor, -1)


## Оглушение пользуется общей блокировкой энергии. Память и краткая
## невосприимчивость защищают от бесконечной цепочки оглушений в группе.
func stun_target(index: int, seconds: float) -> bool:
	if not _active or seconds <= 0.0:
		return false
	var chain := _player_stun_chain
	if index == -1:
		if _player_stun_guard > 0.0:
			_log("Повторное оглушение не прошло — временная защита.")
			return false
	elif get_alive_indices().has(index):
		var enemy_brain: EnemyBrain = fighters[index].brain
		if enemy_brain.stun_guard > 0.0:
			return false
		chain = enemy_brain.stun_chain
	else:
		return false
	var duration := maxf(0.1, seconds * pow(rules.repeated_stun_multiplier, chain))
	if index == -1:
		_player_stun_chain += 1
		_player_stun_memory = maxf(rules.stun_memory_seconds, duration + rules.stun_immunity_seconds)
		_player_stun_guard = duration + rules.stun_immunity_seconds
		player_stun_remaining = duration
	else:
		var enemy_brain: EnemyBrain = fighters[index].brain
		enemy_brain.stun_chain += 1
		enemy_brain.stun_memory = maxf(rules.stun_memory_seconds, duration + rules.stun_immunity_seconds)
		enemy_brain.stun_guard = duration + rules.stun_immunity_seconds
		enemy_brain.stun_remaining = duration
	interrupt_energy(index, duration)
	_log("Оглушение %s на %.1f с." % ["игрока" if index == -1 else "врага #%d" % (index + 1), duration])
	_notify_changed()
	return true


func immobilize_player(seconds: float, source: int, partner: int = -1) -> void:
	if not _active or not get_alive_indices().has(source) or seconds <= 0.0:
		return
	if seconds >= player_immobilized:
		player_immobilized = seconds
		_grapple_sources.assign([source])
		if partner >= 0:
			_grapple_sources.append(partner)
	if state == State.TARGETING and (pending_attack == Attack.KICK or (pending_command == Command.UNIQUE and _pending_unique != null and _pending_unique.requires_free_legs)):
		cancel_target()
	_log("Захват: %.1f с — нельзя ударить ногой, зарядка замедлена." % player_immobilized)
	_refresh_intents()
	_notify_changed()


func _release_grapple() -> void:
	if player_immobilized > 0.0:
		_log("Захват прекращён.")
	player_immobilized = 0.0
	_grapple_sources.clear()


func _advance_effects(seconds: float) -> void:
	player_immobilized = maxf(0.0, player_immobilized - seconds)
	if player_immobilized <= 0.0:
		_grapple_sources.clear()
	player_stun_remaining = maxf(0.0, player_stun_remaining - seconds)
	_player_stun_guard = maxf(0.0, _player_stun_guard - seconds)
	_player_stun_memory = maxf(0.0, _player_stun_memory - seconds)
	if _player_stun_memory <= 0.0:
		_player_stun_chain = 0


# ====================== МЕНЮ / ДЕЙСТВИЯ ======================

func get_inventory() -> Inventory:
	return inventory_override if inventory_override != null else PlayerState.backpack


func can_open_menu(kind: MenuKind) -> bool:
	if not _active or state != State.CHARGING or player_delay > 0.0:
		return false
	match kind:
		MenuKind.ITEMS:
			return player_energy + 0.0001 >= rules.item_energy and not _item_entries().is_empty()
		MenuKind.SKILLS:
			return player_energy + 0.0001 >= rules.skill_energy
		MenuKind.UNIQUE:
			for attack in rules.unique_attacks:
				if attack != null and _unique_reason(attack).is_empty():
					return true
	return false


func open_menu(kind: MenuKind) -> void:
	if not can_open_menu(kind):
		return
	_clear_pending()
	menu_kind = kind
	menu_selection = 0
	state = State.MENU
	_refresh_menu()
	_notify_changed()


func close_menu() -> void:
	if not _active or state != State.MENU:
		return
	_clear_pending()
	menu_kind = MenuKind.NONE
	state = State.CHARGING
	_notify_changed()


func cycle_menu(direction: int) -> void:
	if _active and state == State.MENU and not menu_entries.is_empty():
		menu_selection = posmod(menu_selection + direction, menu_entries.size())
		_notify_changed()


func choose_menu(index: int) -> void:
	if not _active or state != State.MENU:
		return
	if index < 0 or index >= menu_entries.size():
		return
	var key: String = menu_entries[index].key
	_refresh_menu()
	for i in range(menu_entries.size()):
		if menu_entries[i].key == key:
			menu_selection = i
			confirm_menu()
			return


func confirm_menu() -> void:
	if not _active or state != State.MENU or menu_entries.is_empty():
		return
	_refresh_menu()
	if menu_entries.is_empty():
		return
	var entry: Dictionary = menu_entries[menu_selection]
	if not entry.reason.is_empty():
		return
	_return_menu = menu_kind
	match menu_kind:
		MenuKind.ITEMS:
			_pending_item_slot = entry.slot
			_pending_item_token = get_inventory().get_slot(_pending_item_slot)
			pending_command = Command.ITEM
			var item := get_inventory().get_slot_item(_pending_item_slot)
			if _item_needs_target(item):
				_request_target_selection()
			else:
				_execute_item()
		MenuKind.SKILLS:
			if entry.key == "escape":
				_execute_escape()
			else:
				pending_command = Command.CHARM
				_request_target_selection()
		MenuKind.UNIQUE:
			_pending_unique = entry.attack
			pending_command = Command.UNIQUE
			_request_target_selection()


func get_target_indices() -> Array[int]:
	var alive := get_alive_indices()
	if pending_command == Command.ITEM:
		var item := get_inventory().get_slot_item(_pending_item_slot)
		var valid: Array[int] = []
		for index in alive:
			if _item_can_apply(item, index):
				valid.append(index)
		return valid
	return alive


func _request_target_selection() -> void:
	var targets := get_target_indices()
	if targets.is_empty():
		state = State.TARGETING
		cancel_target()
		return
	if not targets.has(selected_target):
		selected_target = targets[0]
	if targets.size() == 1:
		_execute_selected_action()
	else:
		state = State.TARGETING
		_notify_changed()


func _execute_selected_action() -> void:
	if not get_target_indices().has(selected_target):
		cancel_target()
		return
	match pending_command:
		Command.ATTACK: _execute_player_attack()
		Command.ITEM: _execute_item()
		Command.CHARM: _execute_charm()
		Command.UNIQUE: _execute_unique()


func _clear_pending() -> void:
	pending_attack = Attack.NONE
	pending_command = Command.NONE
	_return_menu = MenuKind.NONE
	_pending_item_slot = -1
	_pending_item_token.clear()
	_pending_unique = null


func _on_sources_changed() -> void:
	if not _active:
		return
	if state == State.MENU:
		_refresh_menu()
	elif state == State.TARGETING and pending_command == Command.ITEM:
		if get_inventory().get_slot(_pending_item_slot) != _pending_item_token:
			cancel_target()
	_notify_changed()


func _refresh_menu() -> void:
	var previous_key := ""
	if menu_selection >= 0 and menu_selection < menu_entries.size():
		previous_key = menu_entries[menu_selection].key
	menu_entries.clear()
	match menu_kind:
		MenuKind.ITEMS:
			menu_entries.assign(_item_entries())
		MenuKind.SKILLS:
			menu_entries.append({"key": "escape", "name": "Побег", "description": "Проверка DEX. Оглушение врагов облегчает побег; захват мешает. Успех — случайный выход, без опыта.", "reason": "Нет доступного выхода" if not escape_allowed else ""})
			menu_entries.append({"key": "charm", "name": "Отвлечь", "description": "Проверка CHA против выбранного врага. Успех снижает агрессию, раздражение и похоть; провал раздражает.", "reason": ""})
		MenuKind.UNIQUE:
			for attack in rules.unique_attacks:
				if attack != null:
					menu_entries.append({"key": attack.attack_id, "name": attack.display_name, "description": attack.description, "reason": _unique_reason(attack), "attack": attack})
	if menu_entries.is_empty():
		menu_selection = 0
		return
	menu_selection = clampi(menu_selection, 0, menu_entries.size() - 1)
	for i in range(menu_entries.size()):
		if menu_entries[i].key == previous_key:
			menu_selection = i
			break


func _unique_reason(attack: PlayerCombatAttack) -> String:
	if PlayerState.stats.level < attack.min_level:
		return "Нужен уровень %d" % attack.min_level
	if PlayerState.stats.get_stat("DEX") < attack.min_dex:
		return "Нужно DEX %d" % attack.min_dex
	if player_immobilized > 0.0 and attack.requires_free_legs:
		return "Нельзя выполнить в захвате"
	if player_energy + 0.0001 < attack.energy_cost:
		return "Недостаточно энергии"
	return ""


func _item_context(target: int = -1) -> Dictionary:
	return {"stats": PlayerState.stats, "combat": self, "in_combat": true, "target_index": target}


func _item_needs_target(item: ItemData) -> bool:
	if item == null:
		return false
	for effect in item.effects:
		if effect != null and effect.requires_combat_target():
			return true
	return false


func _item_can_apply(item: ItemData, target: int = -1) -> bool:
	if item == null or not item.usable_in_combat:
		return false
	var context := _item_context(target)
	context["item"] = item
	context["inventory"] = get_inventory()
	for effect in item.effects:
		if effect != null and effect.can_apply(context):
			return true
	return false


func _item_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var positions: Dictionary = {}
	var inventory := get_inventory()
	for slot in range(inventory.get_capacity()):
		var item := inventory.get_slot_item(slot)
		if item == null or not item.usable_in_combat:
			continue
		var key := item.item_id + (":%d" % slot if item.has_durability() else "")
		if positions.has(key):
			entries[int(positions[key])].count += inventory.get_slot_count(slot)
			continue
		positions[key] = entries.size()
		entries.append({"key": key, "name": item.display_name, "description": item.description, "slot": slot,
			"count": inventory.get_slot_count(slot), "durability": inventory.get_slot_durability(slot),
			"icon": item.icon, "reason": "" if _item_can_apply(item) else "Сейчас эффект не сработает"})
	return entries


func _execute_item() -> void:
	var inventory := get_inventory()
	var slot := _pending_item_slot
	var item := inventory.get_slot_item(slot)
	if player_delay > 0.0 or player_energy + 0.0001 < rules.item_energy or inventory.get_slot(slot) != _pending_item_token or not _item_can_apply(item, selected_target if _item_needs_target(item) else -1):
		if state != State.TARGETING:
			state = State.TARGETING
		cancel_target()
		return
	var context := _item_context(selected_target if _item_needs_target(item) else -1)
	_begin_action()
	player_energy = maxf(0.0, player_energy - rules.item_energy)
	var used := inventory.use_slot(slot, true, context)
	if not _active:
		return
	if not used:
		player_energy = minf(100.0, player_energy + rules.item_energy)
		state = State.MENU
		menu_kind = MenuKind.ITEMS
		_clear_pending()
		_refresh_menu()
		_log("Предмет не сработал — энергия и предмет не потрачены.")
	else:
		_log("Использован предмет — %s." % item.display_name)
		_clear_pending()
		reaction_requested.emit(PackedStringArray(["combat", "item", "use"]), -1, int(context.target_index))
	_notify_changed()


func get_escape_difficulty() -> int:
	var alive := get_alive_indices()
	var difficulty := rules.escape_base_difficulty + maxi(0, alive.size() - 1) * rules.escape_group_penalty
	for i in alive:
		var brain: EnemyBrain = fighters[i].brain
		var enemy: EnemyData = fighters[i].data
		if brain.stun_remaining > 0.0:
			difficulty -= rules.escape_stun_relief
		if enemy.lust_affects_escape and brain.lust <= rules.escape_low_lust_threshold:
			difficulty -= rules.escape_low_lust_relief
	if player_immobilized > 0.0:
		difficulty += rules.escape_grapple_penalty
	return maxi(1, difficulty)


func _execute_escape() -> void:
	if not escape_allowed or player_delay > 0.0 or player_energy + 0.0001 < rules.skill_energy:
		return
	var difficulty := get_escape_difficulty()
	_begin_action()
	_clear_pending()
	player_energy = maxf(0.0, player_energy - rules.skill_energy)
	_escape_after_action = PlayerState.stats.roll_check("DEX", difficulty)
	_log("Побег удался." if _escape_after_action else "Побег не удался — бой продолжается.")
	reaction_requested.emit(PackedStringArray(["combat", "escape", "success" if _escape_after_action else "failure"]), -1, -1)
	_notify_changed()


func _execute_charm() -> void:
	if not get_alive_indices().has(selected_target) or player_delay > 0.0 or player_energy + 0.0001 < rules.skill_energy:
		cancel_target()
		return
	var brain: EnemyBrain = fighters[selected_target].brain
	var difficulty := rules.charm_base_difficulty + floori(brain.aggression / 25.0) + floori(brain.irritation / 30.0)
	if brain.stun_remaining > 0.0:
		difficulty -= rules.charm_stun_relief
	_begin_action()
	_clear_pending()
	player_energy = maxf(0.0, player_energy - rules.skill_energy)
	var success := PlayerState.stats.roll_check("CHA", maxi(1, difficulty))
	if success:
		brain.set_emotions(brain.aggression - rules.charm_aggression_reduction, brain.irritation - rules.charm_irritation_reduction, brain.lust - rules.charm_lust_reduction)
	else:
		brain.set_emotions(brain.aggression, brain.irritation + rules.charm_failure_irritation, brain.lust)
	reconsider_intent(selected_target)
	_log("Противник отвлёкся — его настрой смягчился." if success else "Отвлечь не удалось — противник раздражён.")
	reaction_requested.emit(PackedStringArray(["combat", "charm", "success" if success else "failure"]), -1, selected_target)
	_notify_changed()


func _execute_unique() -> void:
	var attack := _pending_unique
	if attack == null or not _unique_reason(attack).is_empty() or player_delay > 0.0:
		cancel_target()
		return
	_begin_action()
	_clear_pending()
	player_energy = maxf(0.0, player_energy - attack.energy_cost)
	PlayerState.stats.spend_stamina(attack.stamina_cost)
	var damage := maxi(1, roundi(attack.base_damage + PlayerState.stats.get_stat("STR") * attack.damage_per_str))
	_log("%s: %d урона." % [attack.display_name, damage])
	_damage_enemy(selected_target, damage, attack.tags, true)
	if fighters[selected_target].hp > 0 and attack.stun_seconds > 0.0:
		stun_target(selected_target, attack.stun_seconds)
	_notify_changed()


func _damage_enemy(index: int, damage: int, attack_tags: PackedStringArray, is_kick: bool = false) -> void:
	if not get_alive_indices().has(index):
		return
	fighters[index].hp = maxi(0, int(fighters[index].hp) - maxi(0, damage))
	var brain: EnemyBrain = fighters[index].brain
	brain.react_to_player_attack(is_kick)
	_clear_plan(index)
	for event_tag in ["attack", "hit"]:
		var tags := PackedStringArray(["combat", event_tag])
		for tag in attack_tags:
			if not tags.has(tag):
				tags.append(tag)
		reaction_requested.emit(tags, -1, index)
	if fighters[index].hp <= 0:
		fighters[index].energy = 0.0
		if _grapple_sources.has(index):
			_release_grapple()
		var enemy: EnemyData = fighters[index].data
		_log("%s больше не участвует в бою." % enemy.display_name)
	_win_after_action = get_alive_indices().is_empty()
	_refresh_intents()


func can_apply_item_effect(index: int, damage: int, stun_seconds: float) -> bool:
	if not _active or not get_alive_indices().has(index):
		return false
	var brain: EnemyBrain = fighters[index].brain
	return damage > 0 or (stun_seconds > 0.0 and brain.stun_guard <= 0.0)


func apply_item_effect(index: int, damage: int, stun_seconds: float, tags: PackedStringArray) -> bool:
	if not can_apply_item_effect(index, damage, stun_seconds):
		return false
	if damage > 0:
		_damage_enemy(index, damage, tags)
	var applied := damage > 0
	if fighters[index].hp > 0 and stun_seconds > 0.0:
		applied = stun_target(index, stun_seconds) or applied
	if damage == 0 and applied:
		var reaction_tags := PackedStringArray(["combat", "item", "hit"])
		for tag in tags:
			if not reaction_tags.has(tag):
				reaction_tags.append(tag)
		reaction_requested.emit(reaction_tags, -1, index)
	_notify_changed()
	return applied


func _finish_escape() -> void:
	if not _active:
		return
	_clear_defense()
	encounter.saved_enemy_state.clear()
	for fighter in fighters:
		var brain: EnemyBrain = fighter.brain
		encounter.saved_enemy_state.append({"hp": fighter.hp, "aggression": brain.aggression, "irritation": brain.irritation, "lust": brain.lust})
	_active = false
	state = State.FINISHED
	_clear_pending()
	menu_kind = MenuKind.NONE
	player_immobilized = 0.0
	player_stun_remaining = 0.0
	_grapple_sources.clear()
	remove_from_group("active_combat")
	_notify_changed()
	combat_escaped.emit()


# ====================== НАМЕРЕНИЯ ======================

func get_intent_text(index: int) -> String:
	var fighter: Dictionary = fighters[index]
	if fighter.hp <= 0:
		return "Выбыл из боя"
	if fighter.supporting >= 0:
		return "Помогает врагу #%d" % (int(fighter.supporting) + 1)
	var intent: EnemyAttack = fighter.intent
	if intent == null:
		return "Выбирает действие"
	var text := intent.display_name
	if fighter.partner >= 0:
		text += " + #%d" % (int(fighter.partner) + 1)
	return text


func get_intent_tags(index: int) -> String:
	if fighters[index].hp <= 0:
		return "—"
	if fighters[index].supporting >= 0:
		return "joint / помощник"
	var intent: EnemyAttack = fighters[index].intent
	return ", ".join(intent.tags) if intent != null else "—"


func reconsider_intent(index: int) -> void:
	if not _active or not get_alive_indices().has(index):
		return
	_clear_plan(index)
	_refresh_intents()
	_notify_changed()


func _clear_plan(index: int, change_attack: bool = false) -> void:
	var fighter: Dictionary = fighters[index]
	var partner: int = fighter.partner
	var leader: int = fighter.supporting
	if fighter.intent != null:
		fighter.previous = fighter.intent
		fighter.avoid_previous = change_attack
	fighter.intent = null
	fighter.partner = -1
	fighter.supporting = -1
	if partner >= 0 and partner < fighters.size():
		fighters[partner].supporting = -1
		fighters[partner].intent = null
	if leader >= 0 and leader < fighters.size():
		fighters[leader].previous = fighters[leader].intent
		fighters[leader].intent = null
		fighters[leader].partner = -1


func _find_partner(index: int, attack: EnemyAttack) -> int:
	for other in get_alive_indices():
		if other == index:
			continue
		var fighter: Dictionary = fighters[other]
		var enemy: EnemyData = fighter.data
		if enemy.can_assist_joint and fighter.delay <= 0.0 and fighter.energy >= attack.partner_energy and fighter.partner < 0 and fighter.supporting < 0:
			return other
	return -1


func _is_plan_valid(index: int) -> bool:
	var fighter: Dictionary = fighters[index]
	var intent: EnemyAttack = fighter.intent
	var brain: EnemyBrain = fighter.brain
	if intent == null or not brain.is_available(intent, player_immobilized > 0.0):
		return false
	if not intent.joint:
		return true
	var partner: int = fighter.partner
	return partner >= 0 and partner < fighters.size() and fighters[partner].hp > 0 and fighters[partner].delay <= 0.0 and fighters[partner].energy >= intent.partner_energy and fighters[partner].supporting == index


func _refresh_intents() -> void:
	if not _active:
		return
	for i in get_alive_indices():
		if fighters[i].supporting < 0 and not _is_plan_valid(i):
			_clear_plan(i)
	for i in get_alive_indices():
		if fighters[i].supporting < 0 and fighters[i].intent == null:
			_choose_intent(i)


func _choose_intent(index: int) -> void:
	var fighter: Dictionary = fighters[index]
	var brain: EnemyBrain = fighter.brain
	var enemy: EnemyData = fighter.data
	var candidates: Array[EnemyAttack] = []
	for attack in enemy.attacks:
		if not brain.is_available(attack, player_immobilized > 0.0) or brain.get_weight(attack) <= 0.0:
			continue
		if attack.joint and (fighter.delay > 0.0 or not enemy.can_assist_joint or _find_partner(index, attack) < 0):
			continue
		candidates.append(attack)
	# После срыва/изменения условий меняем намерение, если есть альтернатива.
	if fighter.avoid_previous and candidates.size() > 1 and candidates.has(fighter.previous):
		candidates.erase(fighter.previous)
	fighter.avoid_previous = false
	var intent := brain.choose(candidates)
	if intent == null:
		intent = _fallback_attack
	_set_plan(index, intent)


func _set_plan(index: int, intent: EnemyAttack) -> void:
	fighters[index].intent = intent
	if not intent.joint:
		return
	var partner := _find_partner(index, intent)
	if partner < 0:
		fighters[index].intent = _fallback_attack
		return
	_clear_plan(partner)
	fighters[index].partner = partner
	fighters[partner].supporting = index


## Только для тестовой сцены: принудительное намерение, но не обход
## условий/наличия помощника. В обычном бою используется взвешенный выбор.
func debug_force_intent(index: int, intent: EnemyAttack) -> bool:
	if not OS.is_debug_build() or not _active or not get_alive_indices().has(index) or intent == null:
		return false
	var brain: EnemyBrain = fighters[index].brain
	if not brain.is_available(intent, player_immobilized > 0.0):
		return false
	_clear_plan(index)
	if intent.joint and _find_partner(index, intent) < 0:
		_refresh_intents()
		return false
	_set_plan(index, intent)
	_notify_changed()
	return true


func _on_player_died() -> void:
	if _active:
		_finish(false)


func _on_arousal_peaked() -> void:
	if not _active:
		return
	interrupt_energy(-1, rules.peak_delay_seconds)
	_log("Пик возбуждения: зарядка остановлена на %.1f с." % rules.peak_delay_seconds)
	reaction_requested.emit(PackedStringArray(["combat", "arousal_peak"]), -1, -1)
	_notify_changed()


func _finish(won: bool) -> void:
	if not _active:
		return
	_clear_defense()
	_active = false
	state = State.FINISHED
	_clear_pending()
	menu_kind = MenuKind.NONE
	player_immobilized = 0.0
	player_stun_remaining = 0.0
	_grapple_sources.clear()
	remove_from_group("active_combat")
	_log("Победа." if won else "Поражение.")
	_notify_changed()
	combat_finished.emit(won)


func _log(text: String) -> void:
	message = text
	recent_messages.append(text)
	while recent_messages.size() > 6:
		recent_messages.remove_at(0)
	print("⚔ %s" % text)


func _notify_changed() -> void:
	if _active and state == State.MENU:
		_refresh_menu()
	changed.emit()
