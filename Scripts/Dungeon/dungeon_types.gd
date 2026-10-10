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
