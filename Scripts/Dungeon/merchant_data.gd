class_name MerchantData
extends Resource
## Странствующий торговец на тайле MERCHANT. По образцу RandomEvent: свой
## .dialogue-файл у каждого, общий шаблон не используется.

@export var title: String = "Торговец"  ## Внутренний ярлык — игрок не видит
@export_range(1, 100) var weight: int = 30

@export_group("Диалог")
## Нужна секция ~ start. В диалог передаётся {"merchant": <этот ресурс>}.
## Ветка торговли пока заглушка ($> GameManager.log_stub), реальный
## товар/цены появятся вместе с инвентарём и экономикой — сюда же
## добавится список товаров.
@export var dialogue: DialogueResource
