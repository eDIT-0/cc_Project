extends Node
## Автозагружаемый синглтон (Project Settings -> Autoload -> имя "GameManager").
## В Unity-версии Instance/DontDestroyOnLoad собирались вручную —
## в Godot автозагрузка уже даёт то же самое из коробки, без лишнего кода.
##
## ХЭНДОВЕР МЕЖДУ СЦЕНАМИ: хаб и генератор лабиринта — РАЗНЫЕ сцены.
## В момент, когда игрок ещё в хабе, сцена с DungeonGenerator физически не
## загружена — вызывать generate_dungeon() отсюда напрямую нельзя, объекта
## просто не существует. Поэтому порядок такой:
##   1. Хаб вызывает GameManager.prepare_run(location, difficulty) —
##      это только КЛАДЁТ данные, ничего не генерирует.
##   2. Хаб сам делает get_tree().change_scene_to_file("res://.../dungeon.tscn")
##   3. Новая сцена загружается, DungeonGenerator._ready() регистрирует себя
##      и сам видит, что current_location уже выставлена — сам стартует генерацию.

var current_location: LocationData
var current_difficulty: Difficulty.Level = Difficulty.Level.NORMAL

## Пока есть только одна тестовая сцена лабиринта. Когда появится несколько
## типов зон/сцен — вынесем в параметр, сейчас плодить лишнее рано.
const DUNGEON_SCENE_PATH := "res://Scenes/Levels/dungeon_test.tscn"
const HUB_SCENE_PATH := "res://hub_ui.tscn"

var _dungeon_generator: DungeonGenerator

# ====================== РЕГИСТРАЦИЯ (вызывается системами при их _ready()) ======================

func register_dungeon_generator(generator: DungeonGenerator) -> void:
	_dungeon_generator = generator
	# Если данные для забега уже подготовлены хабом — стартуем сразу.
	if current_location != null:
		_dungeon_generator.generate_dungeon()

# ====================== ПОДГОТОВКА ЗАБЕГА (вызывается из хаба ДО смены сцены) ======================

## Кладёт данные о выбранной локации и сложности. Ничего не генерирует —
## только готовит хэндовер. Смену сцены выполняет вызывающий код (хаб).
func prepare_run(location: LocationData, difficulty: Difficulty.Level) -> void:
	if location == null:
		push_error("GameManager: передана пустая LocationData!")
		return

	current_location = location
	current_difficulty = difficulty

	# Основной квест — состояние ЭТОГО забега, а не глобальное. Без сброса
	# завершённый в одном заходе квест считался бы завершённым и во всех
	# следующих, и сайд-квесты сразу предлагали бы выход.
	if QuestManager:
		QuestManager.reset_main_quest_completion()

	print("📍 Подготовлен забег: %s | Сложность: %s" % [
		location.location_name, Difficulty.Level.keys()[difficulty]
	])

## Сбросить данные забега — вызывать при возврате в хаб после смерти/выхода,
## чтобы случайно не унести старые данные в следующий заход.
func clear_run() -> void:
	current_location = null
	_dungeon_generator = null

# ====================== НАСТОЯЩИЙ ВХОД В ОПАСНУЮ ЗОНУ (вызывается из хаба) ======================

## Единая точка входа: готовит данные и сразу меняет сцену. Хаб (или что
## угодно ещё в будущем — карта города, быстрый переход по квесту) должен
## дёргать именно этот метод, а не prepare_run() и change_scene по отдельности.
func enter_dungeon(location: LocationData, difficulty: Difficulty.Level) -> void:
	prepare_run(location, difficulty)
	get_tree().change_scene_to_file(DUNGEON_SCENE_PATH)

# ====================== ВЫХОД ИЗ ЛАБИРИНТА ОБРАТНО В ХАБ ======================

## Симметричный партнёр enter_dungeon(). Вызывается, когда игрок выбрал
## "Уйти" в диалоге возврата (основной квест / сайд-квест / стартовая
## клетка — см. DungeonRun._start_return_choice()).
##
## Раньше здесь была защитная DialogueManager.cancel() — свой DialogueManager
## был автозагрузкой и переживал смену сцены, так что незакрытый диалог
## хаба мог "протечь" в дунжен и заблокировать там ввод. После перехода на
## аддон Dialogue Manager стейт диалога живёт локально в HubUI/DebugMazeView
## (см. их комментарии), а не в глобальном синглтоне — течь стало нечему,
## поэтому и страховка больше не нужна.
func return_to_hub() -> void:
	clear_run()
	get_tree().change_scene_to_file(HUB_SCENE_PATH)

# ====================== МОСТ ДЛЯ МУТАЦИЙ В .dialogue-ФАЙЛАХ ======================

## Мутации ($> ...) в аддоне Dialogue Manager резолвятся только против
## синглтонов/автозагрузок по имени — голые глобальные функции Godot
## (print и т.п.) им не видны, отсюда "Method print not found". Пока исходы
## ивентов/диалогов — просто текстовые заглушки в консоль (денег, инвентаря,
## боёвки ещё нет), нужен один такой мост, а не для каждого global-метода.
func log_stub(text: String) -> void:
	print(text)
