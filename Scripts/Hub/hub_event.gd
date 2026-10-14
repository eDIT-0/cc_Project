class_name HubEvent
extends Resource
## "Неприятность" в хабе: может случиться при входе на локацию
## (HubLocation.events). Максимум одна за вход; если случилась — её диалог
## играется ВМЕСТО intro_text локации (пусть сам и описывает, куда пришёл).
##
## Шанс = base_chance + бонус текущей фазы суток
##        + chance_per_attractiveness × привлекательность (пока заглушка)
##        + chance_per_drunk_stage × стадия опьянения (0–3)
##        + chance_per_arousal_stage × стадия возбуждения (0–3)
## Всё в долях: 0.05 = 5%. Итог зажимается в 0–100%.
## Похоть (LEW) на шанс НЕ влияет — она про варианты действий персонажа.
##
## В диалог передаются {"event": этот ресурс, "location": HubLocation,
## "pics": EventPictures} — картинки: do pics.show(1) и т.д.

@export var event_id: String = ""      ## уникальный ключ (для отката); пусто — путь к файлу
@export var title: String = "Неприятность"  ## внутренний ярлык для логов

@export_group("Диалог")
@export var dialogue: DialogueResource
## С какой секции начинать. НЕ называть "*dialogue_cue*" — см. npc_data.gd.
@export var start_from: String = "start"

@export_group("Картинки")
## Вставки поверх фона, как у RandomEvent (см. EventPictures).
@export var images: Array[Texture2D] = []
@export var show_first_image: bool = true

@export_group("Когда возможно")
## В какие фазы суток событие вообще может случиться.
@export_flags("Рассвет", "День", "Закат", "Ночь") var phases: int = 15
## Откат после срабатывания, в игровых часах. 0 — без отката.
@export var cooldown_hours: int = 18

@export_group("Шанс")
@export_range(0.0, 1.0, 0.01) var base_chance: float = 0.0
@export_range(-1.0, 1.0, 0.01) var chance_dawn: float = 0.0
@export_range(-1.0, 1.0, 0.01) var chance_day: float = 0.0
@export_range(-1.0, 1.0, 0.01) var chance_dusk: float = 0.05
@export_range(-1.0, 1.0, 0.01) var chance_night: float = 0.15
## За единицу привлекательности (PlayerState.get_attractiveness()).
@export_range(-0.1, 0.1, 0.001) var chance_per_attractiveness: float = 0.0
## За стадию опьянения (1 лёгкое ... 3 сильное).
@export_range(-1.0, 1.0, 0.01) var chance_per_drunk_stage: float = 0.0
## За стадию возбуждения (пороги 25 / 50 / 75).
@export_range(-1.0, 1.0, 0.01) var chance_per_arousal_stage: float = 0.0


func get_id() -> String:
	return event_id if not event_id.is_empty() else resource_path


## Сейчас подходящая фаза и прошёл откат.
func is_available() -> bool:
	if (phases & PlayerState.clock.phase_bit()) == 0:
		return false
	if cooldown_hours <= 0:
		return true
	var key := _cooldown_key()
	if not PlayerState.has_value(key):
		return true
	return PlayerState.clock.minutes - PlayerState.value(key) >= cooldown_hours * 60


## Итоговый шанс прямо сейчас (0..1).
func get_chance() -> float:
	var st: CharacterStats = PlayerState.stats
	var phase_bonus: float = [chance_dawn, chance_day, chance_dusk, chance_night][PlayerState.clock.phase]
	var chance := base_chance + phase_bonus \
		+ chance_per_attractiveness * PlayerState.get_attractiveness() \
		+ chance_per_drunk_stage * st.get_group_stage("drunk") \
		+ chance_per_arousal_stage * st.get_group_stage("arousal")
	return clampf(chance, 0.0, 1.0)


## Запомнить срабатывание (для отката). Хранится в счётчиках PlayerState —
## попадёт и в будущие сохранения.
func mark_triggered() -> void:
	PlayerState.set_value(_cooldown_key(), PlayerState.clock.minutes)


func _cooldown_key() -> String:
	return "hub_event_last:" + get_id()
