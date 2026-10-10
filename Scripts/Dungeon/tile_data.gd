class_name DungeonTile
extends RefCounted
## Аналог TileData из Unity-версии (переименован в DungeonTile —
## в Godot имя TileData занято встроенным движковым классом системы TileMap).
## RefCounted вместо Resource — не нужно сериализовать в инспекторе,
## как и [NonSerialized] у sideQuestData в оригинале.

var position: Vector2i
var type: DungeonTypes.TileType = DungeonTypes.TileType.WALL
var event_type: DungeonTypes.EventType = DungeonTypes.EventType.EMPTY
var visited: bool = false

## Данные квеста храним только для тайлов SIDE_QUEST / QUEST соответственно
var side_quest_data: SideQuestEvent = null
var main_quest_data: MainQuestEvent = null

func _init(p_position: Vector2i = Vector2i.ZERO) -> void:
	position = p_position
