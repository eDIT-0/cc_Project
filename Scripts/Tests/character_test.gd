extends Node
## Самопроверка CharacterStats / StatusEffect без UI. Запуск: открыть
## res://Scenes/Tests/character_test.tscn и нажать F6. Результат — в консоли.
## Пороги возбуждения и изнурение берутся из Data/Status (как в игре),
## остальные эффекты создаются прямо в коде.

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_start()
	_test_pools()
	_test_effects_and_time()
	_test_stages()
	_test_arousal()
	_test_exhaustion()
	_test_con_clamps_hp()
	_test_checks()
	_test_levels()

	print("\n==== ИТОГ: %d пройдено, %d провалено ====" % [_passed, _failed])
	if _failed > 0:
		push_error("CharacterTest: есть проваленные проверки — см. консоль.")


func _make_effect(id: String, mods: Dictionary, minutes: int, group := "", stage := 1) -> StatusEffect:
	var e := StatusEffect.new()
	e.effect_id = id
	e.display_name = id
	e.duration_minutes = minutes
	e.group = group
	e.stage = stage
	e.str_mod = mods.get("STR", 0)
	e.dex_mod = mods.get("DEX", 0)
	e.con_mod = mods.get("CON", 0)
	e.int_mod = mods.get("INT", 0)
	e.cha_mod = mods.get("CHA", 0)
	e.lew_mod = mods.get("LEW", 0)
	return e


func _test_start() -> void:
	print("\n-- Старт --")
	var st := CharacterStats.new()
	_check(st.get_stat("STR") == 4 and st.get_stat("DEX") == 6 and st.get_stat("CON") == 5 \
		and st.get_stat("INT") == 3 and st.get_stat("CHA") == 4 and st.get_stat("LEW") == 0, "стартовые характеристики 4/6/5/3/4/0")
	_check(st.get_max_hp() == 40 and st.hp == 40, "здоровье 40/40")
	_check(st.get_max_stamina() == 100 and st.stamina == 100, "выносливость 100/100")
	_check(st.arousal == 0, "возбуждение 0")


func _test_pools() -> void:
	print("\n-- Здоровье / выносливость --")
	var st := CharacterStats.new()
	_check(st.heal(10) == 0, "на полном здоровье лечение не срабатывает")
	st.damage(15)
	_check(st.hp == 25 and st.heal(10) == 10 and st.hp == 35, "урон 15, лечение 10 -> 35")
	_check(st.heal(100) == 5 and st.hp == 40, "лечение не выше максимума")
	st.spend_stamina(30)
	_check(st.stamina == 70 and st.restore_stamina(50) == 30, "выносливость тратится и восстанавливается до максимума")


func _test_effects_and_time() -> void:
	print("\n-- Эффекты и время --")
	var st := CharacterStats.new()
	var buff := _make_effect("buff", {"DEX": 2, "INT": -5}, 30)
	st.apply_effect(buff)
	_check(st.get_stat("DEX") == 8 and st.get_modifier("DEX") == 2, "бафф DEX +2")
	_check(st.get_stat("INT") == 0, "характеристика не уходит ниже 0 (INT 3 - 5)")
	st.advance_time(20)
	_check(st.has_effect("buff"), "через 20 мин из 30 эффект ещё висит")
	st.apply_effect(buff)
	st.advance_time(20)
	_check(st.has_effect("buff"), "повторное наложение продлило эффект")
	st.advance_time(10)
	_check(not st.has_effect("buff") and st.get_stat("DEX") == 6, "эффект закончился — DEX снова 6")


func _test_stages() -> void:
	print("\n-- Стадии (опьянение) --")
	var st := CharacterStats.new()
	var d3 := _make_effect("d3", {"STR": 3}, 180, "drunk", 3)
	var d2 := _make_effect("d2", {"STR": 2}, 120, "drunk", 2)
	var d1 := _make_effect("d1", {"STR": 1}, 60, "drunk", 1)
	d1.next_stage = d2
	d2.next_stage = d3

	st.apply_effect(d1, 1)  # пиво
	_check(st.has_effect("d1") and st.get_stat("STR") == 5, "пиво трезвому — слабое (STR +1)")
	st.apply_effect(d1, 1)
	_check(st.has_effect("d2") and not st.has_effect("d1") and st.get_stat("STR") == 6, "ещё пиво — среднее, слабое сменилось (не сложилось)")
	st.apply_effect(d2, 2)  # самогон
	_check(st.has_effect("d3") and st.get_stat("STR") == 7, "самогон на среднем — сильное")
	st.apply_effect(d1, 1)
	_check(st.has_effect("d3"), "выше сильного не растёт")
	st.advance_time(180)
	_check(not st.has_group("drunk"), "через 3 часа протрезвел")

	var st2 := CharacterStats.new()
	st2.apply_effect(d2, 2)
	_check(st2.has_effect("d2"), "самогон трезвому — сразу среднее")


func _test_arousal() -> void:
	print("\n-- Возбуждение --")
	var st := CharacterStats.new()
	var peaked := [false]
	st.arousal_peaked.connect(func(): peaked[0] = true)
	st.add_arousal(24)
	_check(st.get_stat("DEX") == 6, "24 — без штрафа")
	st.add_arousal(1)
	_check(st.get_stat("DEX") == 5 and st.get_stat("INT") == 2, "25 — DEX -1, INT -1")
	st.add_arousal(25)
	_check(st.get_stat("DEX") == 4, "50 — DEX -2")
	st.add_arousal(25)
	_check(st.get_stat("DEX") == 3 and st.get_stat("STR") == 3, "75 — DEX -3, STR -1")
	st.add_arousal(25)
	_check(st.arousal == 0 and peaked[0] and st.get_stat("DEX") == 6, "100 — сброс в 0, сигнал, штрафы сняты")
	_check(st.hp == 28 and st.stamina == 70, "пик: -30% здоровья (40 -> 28) и выносливости (100 -> 70)")
	var st2 := CharacterStats.new()
	var died := [false]
	st2.died.connect(func(): died[0] = true)
	st2.damage(30)
	st2.add_arousal(100)
	_check(st2.hp == 0 and died[0], "пик при 10 здоровья — поражение")


func _test_exhaustion() -> void:
	print("\n-- Изнурение --")
	var st := CharacterStats.new()
	st.spend_stamina(999)
	_check(st.stamina == 0 and st.has_effect("exhausted") and st.get_stat("STR") == 2, "выносливость 0 — изнурение (STR -2)")
	st.restore_stamina(10)
	_check(not st.has_effect("exhausted") and st.get_stat("STR") == 4, "отдохнул — изнурение снято")


func _test_con_clamps_hp() -> void:
	print("\n-- Телосложение и максимумы --")
	var st := CharacterStats.new()
	st.apply_effect(_make_effect("weak", {"CON": -1}, 60))
	_check(st.get_max_hp() == 36 and st.hp == 36, "CON -1: максимум здоровья 36, текущее подрезано")
	_check(st.get_max_stamina() == 90 and st.stamina == 90, "CON -1: максимум выносливости 90")


func _test_checks() -> void:
	print("\n-- Проверки характеристик --")
	var st := CharacterStats.new()   # DEX 6
	_check(is_equal_approx(st.get_check_chance("DEX", 6), 0.5), "DEX 6 против 6 — 50%")
	_check(is_equal_approx(st.get_check_chance("DEX", 4), 0.7), "DEX 6 против 4 — 70%")
	_check(is_equal_approx(st.get_check_chance("DEX", 20), 0.05), "невозможная сложность — не ниже 5%")
	_check(is_equal_approx(st.get_check_chance("DEX", 0), 0.95), "лёгкая — не выше 95%")
	_check(not st.is_check_hopeless("DEX", 9) and st.is_check_hopeless("DEX", 10), "предупреждение — с 10% (DEX 6 против 10)")
	st.apply_effect(_make_effect("drunk", {"DEX": -3}, 60))
	_check(is_equal_approx(st.get_check_chance("DEX", 6), 0.2), "пьяный (DEX 3) — 20%: проверка смотрит на итоговое значение")


func _test_levels() -> void:
	print("\n-- Опыт и уровни --")
	_check(CharacterStats.xp_to_next(1) == 100 and CharacterStats.xp_to_next(2) == 280 and CharacterStats.xp_to_next(10) == 3160, "кривая: 100 / 280 / ... / 3160")
	var st := CharacterStats.new()
	var levels := [0]
	st.leveled_up.connect(func(_l): levels[0] += 1)
	st.add_xp(90)
	_check(st.level == 1 and st.xp == 90, "90 опыта — ещё 1 уровень")
	st.add_xp(300)
	_check(st.level == 3 and st.xp == 10 and st.stat_points == 2 and levels[0] == 2, "+300 — сразу два уровня (390 = 100 + 280 + 10), 2 очка")
	_check(not st.can_raise_stat("LEW") and not st.raise_stat("LEW"), "LEW очками не поднимается")
	st.damage(10)
	_check(st.raise_stat("CON") and st.get_stat("CON") == 6 and st.get_max_hp() == 44 and st.hp == 34, "CON +1: максимум 44, текущее здоровье тоже +4")
	_check(st.raise_stat("DEX") and st.stat_points == 0 and not st.raise_stat("DEX"), "очки кончились — дальше не поднять")
	for i in range(100):
		st.add_xp(100000)
	_check(st.level == CharacterStats.MAX_LEVEL and st.xp == 0, "потолок уровня %d" % CharacterStats.MAX_LEVEL)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("✅ ", label)
	else:
		_failed += 1
		print("❌ ", label)
