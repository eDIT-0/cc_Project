class_name DungeonTypes
extends RefCounted

## Аналог TileType из Unity-версии
enum TileType {
	WALL,
	FLOOR,
}

## Аналог EventType из Unity-версии
enum EventType {
	EMPTY,
	RANDOM_EVENT,
	ENEMY,
	REWARD,
	QUEST,
	MERCHANT,
	EXIT,
	SIDE_QUEST,
}

## Аналог Direction из Unity-версии
enum Direction {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

## Что игрок видит перед собой (фон от первого лица, см. MazeViewSet).
## Определяется тремя сторонами относительно взгляда: впереди / слева / справа.
enum ViewKind {
	CORRIDOR,        ## впереди проход, по бокам стены
	CORRIDOR_RIGHT,  ## впереди проход + проход направо
	CORRIDOR_LEFT,   ## впереди проход + проход налево
	CROSSROADS,      ## проходы во все три стороны
	DEAD_END,        ## стены со всех трёх сторон
	CORNER_RIGHT,    ## стена впереди, проход направо
	CORNER_LEFT,     ## стена впереди, проход налево
	T_JUNCTION,      ## стена впереди, проходы в обе стороны
}

const VIEW_KIND_NAMES := [
	"Коридор", "Коридор, проход направо", "Коридор, проход налево", "Развилка",
	"Тупик", "Угол направо", "Угол налево", "Стена, проходы в обе стороны",
]


## Вид по трём сторонам.
static func view_kind_for(front: bool, left: bool, right: bool) -> ViewKind:
	if front:
		if left and right:
			return ViewKind.CROSSROADS
		if left:
			return ViewKind.CORRIDOR_LEFT
		if right:
			return ViewKind.CORRIDOR_RIGHT
		return ViewKind.CORRIDOR
	if left and right:
		return ViewKind.T_JUNCTION
	if left:
		return ViewKind.CORNER_LEFT
	if right:
		return ViewKind.CORNER_RIGHT
	return ViewKind.DEAD_END
