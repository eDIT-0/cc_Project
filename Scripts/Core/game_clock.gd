class_name GameClock
extends RefCounted
## Игровые часы: дни, дни недели, время суток. Живёт в PlayerState.clock,
## время двигает только PlayerState.advance_time() (шаги, переходы, сон...).
##
## Отсчёт — в минутах от полуночи дня 1. Игра начинается в понедельник
## дня 1 в 8:00 (START_MINUTES).
##
## Фазы суток (жаркое лето):
##   рассвет 4:00–7:00, день 7:00–19:00, закат 19:00–22:00, ночь 22:00–4:00.
##
## В диалогах:
##   if PlayerState.clock.is_night()
##   if PlayerState.clock.phase == GameClock.Phase.DUSK   (или is_phase(...))
##   Сейчас {{PlayerState.clock.get_time_text()}}

## Сменилась фаза суток. При большом скачке (сон) — один раз, уже с итоговой.
signal phase_changed(phase: Phase)
## Наступил новый день (при скачке через несколько дней — один раз).
signal day_changed(day: int)
## Время сдвинулось (для экранов).
signal time_changed

enum Phase { DAWN, DAY, DUSK, NIGHT }

const PHASE_NAMES := ["рассвет", "день", "закат", "ночь"]
const WEEKDAY_NAMES := ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]

## Начало фаз (часы). Ночь — с 22:00 до 4:00 следующего дня.
const DAWN_START := 4
const DAY_START := 7
const DUSK_START := 19
const NIGHT_START := 22

const MINUTES_PER_DAY := 24 * 60
## Старт игры: день 1, 8:00. День 1 — понедельник.
const START_MINUTES := 8 * 60

## Минуты от полуночи дня 1.
var minutes: int = START_MINUTES
var phase: Phase = Phase.DAY


func _init() -> void:
	phase = _phase_for(minutes)


## Сдвинуть время (зовёт только PlayerState.advance_time).
func advance(amount: int) -> void:
	if amount <= 0:
		return
	var old_day := get_day()
	var old_phase := phase
	minutes += amount
	phase = _phase_for(minutes)
	time_changed.emit()
	if get_day() != old_day:
		print("📅 Новый день: %s" % get_date_text())
		day_changed.emit(get_day())
	if phase != old_phase:
		print("🌗 Время суток: %s" % PHASE_NAMES[phase])
		phase_changed.emit(phase)


# ====================== ЧТЕНИЕ ======================

## Номер дня, с 1.
func get_day() -> int:
	return minutes / MINUTES_PER_DAY + 1


## 0 = понедельник ... 6 = воскресенье.
func get_weekday() -> int:
	return (get_day() - 1) % 7


func get_hour() -> int:
	return (minutes % MINUTES_PER_DAY) / 60


func get_minute() -> int:
	return minutes % 60


## Сколько прошло с начала игры.
func get_elapsed_minutes() -> int:
	return minutes - START_MINUTES


func is_phase(p: Phase) -> bool:
	return phase == p


func is_night() -> bool:
	return phase == Phase.NIGHT


## Бит фазы для полей-флажков (NPCData.present_phases и т.п.):
## рассвет 1, день 2, закат 4, ночь 8.
func phase_bit() -> int:
	return 1 << phase


func get_phase_name() -> String:
	return PHASE_NAMES[phase]


func get_weekday_name() -> String:
	return WEEKDAY_NAMES[get_weekday()]


## "08:05"
func get_time_text() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


## "День 3, среда, 14:20 (день)"
func get_date_text() -> String:
	return "День %d, %s, %s (%s)" % [get_day(), get_weekday_name(), get_time_text(), get_phase_name()]


static func _phase_for(total_minutes: int) -> Phase:
	var hour := (total_minutes % MINUTES_PER_DAY) / 60
	if hour >= NIGHT_START or hour < DAWN_START:
		return Phase.NIGHT
	if hour < DAY_START:
		return Phase.DAWN
	if hour < DUSK_START:
		return Phase.DAY
	return Phase.DUSK
