class_name MainQuestEvent
extends Resource
## Основной квест локации — аналог SideQuestEvent по назначению (даёт
## квесту id/имя для журнала завершённых квестов и будущих цепочек), но
## ПРОЩЕ: основной квест не активируется/деактивируется через QuestManager,
## как сайд-квест — он просто есть, если назначен на LocationData, и тайл
## EventType.QUEST для него генератор кладёт всегда (см. DungeonGenerator).
## Если позже на одну локацию понадобится больше одного этапа основного
## квеста — усложнять придётся эту систему, а не городить новую.

@export_group("Основная информация")
@export var quest_id: String = ""
@export var quest_name: String = ""
## Опыт за ПЕРВОЕ прохождение (повторные забеги опыта не дают).
@export_range(0, 10000) var xp_reward: int = 100

@export_group("Нарратив")
@export_multiline var description: String = ""
