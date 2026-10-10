class_name HubLocation
extends Resource
## Одна точка хаба: Квартира, Улица, Магазин, Станция метро и т.д.

@export var location_id: String = ""          # уникальный ключ, например "apartment"
@export var display_name: String = ""         # для UI/дебага, например "Квартира"

@export_group("Отображение")
@export var background: Texture2D
@export_multiline var intro_text: String = "Описание сцены..."

@export_group("Навигация")
@export var choices: Array[HubChoice] = []

@export_group("Персонажи")
## Кто присутствует на локации прямо сейчас. Пока просто статичный список —
## расписание/условия появления (способ 2 получения квеста: NPC на улице
## только 10:00-17:00) добавятся позже как отдельная логика поверх этого
## же поля, без изменений в HubUI/HubChoice.
@export var npcs: Array[NPCData] = []
