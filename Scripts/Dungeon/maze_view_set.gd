class_name MazeViewSet
extends Resource
## Набор фонов "от первого лица" для ОДНОГО типа локации (трущобы, завод...)
## и одного времени суток. Подключается в LocationData (views_day и т.д.).
## Уровни сложности его не меняют.
##
## Какой фон показать, решает DungeonRun.get_view_kind() по трём сторонам
## относительно взгляда игрока — см. DungeonTypes.ViewKind.

@export_group("Впереди проход")
@export var corridor: Texture2D        ## по бокам стены
@export var corridor_right: Texture2D  ## + проход направо
@export var corridor_left: Texture2D   ## + проход налево
@export var crossroads: Texture2D      ## проходы во все три стороны

@export_group("Впереди стена")
@export var dead_end: Texture2D        ## тупик
@export var corner_right: Texture2D    ## проход направо
@export var corner_left: Texture2D     ## проход налево
@export var t_junction: Texture2D      ## проходы в обе стороны

@export_group("Запасной вариант")
## Нет картинки для "налево" — взять "направо", отразив по горизонтали
## (и наоборот). Перспектива при этом сместится в другую сторону — для
## черновиков сойдёт, потом можно дорисовать честные.
@export var mirror_missing_sides: bool = true


## { "texture": Texture2D или null, "flip": bool }
func get_view(kind: DungeonTypes.ViewKind) -> Dictionary:
	var texture := _texture_for(kind)
	if texture != null or not mirror_missing_sides:
		return { "texture": texture, "flip": false }
	var mirrored := _mirror_of(kind)
	if mirrored != kind:
		texture = _texture_for(mirrored)
		if texture != null:
			return { "texture": texture, "flip": true }
	return { "texture": null, "flip": false }


func _texture_for(kind: DungeonTypes.ViewKind) -> Texture2D:
	match kind:
		DungeonTypes.ViewKind.CORRIDOR: return corridor
		DungeonTypes.ViewKind.CORRIDOR_RIGHT: return corridor_right
		DungeonTypes.ViewKind.CORRIDOR_LEFT: return corridor_left
		DungeonTypes.ViewKind.CROSSROADS: return crossroads
		DungeonTypes.ViewKind.DEAD_END: return dead_end
		DungeonTypes.ViewKind.CORNER_RIGHT: return corner_right
		DungeonTypes.ViewKind.CORNER_LEFT: return corner_left
		DungeonTypes.ViewKind.T_JUNCTION: return t_junction
	return null


## Зеркальная пара (лево <-> право). Симметричные виды — сами себе пара.
func _mirror_of(kind: DungeonTypes.ViewKind) -> DungeonTypes.ViewKind:
	match kind:
		DungeonTypes.ViewKind.CORRIDOR_RIGHT: return DungeonTypes.ViewKind.CORRIDOR_LEFT
		DungeonTypes.ViewKind.CORRIDOR_LEFT: return DungeonTypes.ViewKind.CORRIDOR_RIGHT
		DungeonTypes.ViewKind.CORNER_RIGHT: return DungeonTypes.ViewKind.CORNER_LEFT
		DungeonTypes.ViewKind.CORNER_LEFT: return DungeonTypes.ViewKind.CORNER_RIGHT
	return kind
