class_name Difficulty
extends RefCounted

## 5 уровней сложности — отображаются игроку как "черепа" (1-5).
enum Level {
	EASY,
	NORMAL,
	HARD,
	VERY_HARD,
	EXTREME,
}

## Сколько черепов показывать для уровня — для UI
static func skull_count(level: Level) -> int:
	return level + 1

