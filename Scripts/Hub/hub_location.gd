class_name HubLocation
extends Resource
## Одна точка хаба: Квартира, Улица, Магазин, Станция метро и т.д.

@export var location_id: String = ""          # уникальный ключ, например "apartment"
@export var display_name: String = ""         # для UI/дебага, например "Квартира"

@export_group("Отображение")
@export var background: Texture2D
## Фоны по времени суток — необязательные: не задан -> обычный background.
## Днём всегда background.
@export var background_dawn: Texture2D
@export var background_dusk: Texture2D
@export var background_night: Texture2D
@export_multiline var intro_text: String = "Описание сцены..."

@export_group("Навигация")
@export var choices: Array[HubChoice] = []

@export_group("Часы работы")
## Когда на локацию можно зайти (магазин ночью закрыт). Закрыто — пункты,
## ведущие сюда, видны, но неактивны, с припиской [closed_text].
@export_flags("Рассвет", "День", "Закат", "Ночь") var open_phases: int = 15
@export var closed_text: String = "Закрыто"

@export_group("Персонажи")
## Кто может быть на локации. Кто виден прямо сейчас — решает расписание
## самого NPC (NPCData.present_phases), см. get_present_npcs().
@export var npcs: Array[NPCData] = []

@export_group("Неприятности")
## Что может случиться при входе (максимум одно за вход), см. HubEvent.
@export var events: Array[HubEvent] = []


## Можно ли сейчас зайти (по времени суток).
func is_open() -> bool:
	return (open_phases & PlayerState.clock.phase_bit()) != 0


func get_background(phase: GameClock.Phase) -> Texture2D:
	var by_phase: Texture2D = null
	match phase:
		GameClock.Phase.DAWN:
			by_phase = background_dawn
		GameClock.Phase.DUSK:
			by_phase = background_dusk
		GameClock.Phase.NIGHT:
			by_phase = background_night
	return by_phase if by_phase != null else background


func get_present_npcs() -> Array[NPCData]:
	var result: Array[NPCData] = []
	for npc in npcs:
		if npc != null and npc.is_present():
			result.append(npc)
	return result


## Бросить неприятности при входе. Подходящие (фаза, откат) проверяются
## в случайном порядке, срабатывает первая выпавшая — или никакая (null).
func roll_event() -> HubEvent:
	var pool := events.filter(func(e): return e != null and e.is_available())
	pool.shuffle()
	for e in pool:
		var chance: float = e.get_chance()
		if randf() < chance:
			print("⚠ Неприятность '%s' (шанс был %d%%)" % [e.title, roundi(chance * 100)])
			return e
	return null
