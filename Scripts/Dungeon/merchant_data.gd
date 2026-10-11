class_name MerchantData
extends Resource
## Торговец: и странствующий в лабиринте (тайл MERCHANT, LocationData.merchants),
## и продавец в хабе (NPCData.merchant). Сам торг — TradeManager / экран
## торговли; здесь только данные: что продаёт и по каким ценам.

## Уникальный ключ: по нему TradeManager хранит текущий ассортимент и
## сюжетный множитель цен. Пусто — используется путь к .tres.
@export var merchant_id: String = ""
@export var title: String = "Торговец"  ## Внутренний ярлык — игрок не видит
## Заголовок экрана торговли.
@export var display_name: String = "Торговец"
## Вес при выборе торговца на тайле MERCHANT (для хаба не важен).
@export_range(1, 100) var weight: int = 30

@export_group("Диалог")
## Только для лабиринта (в хабе диалог — у NPC, NPCData.dialogue).
## Нужна секция ~ start. В диалог передаётся {"merchant": <этот ресурс>},
## торговля открывается строкой:  do TradeManager.open(merchant)
@export var dialogue: DialogueResource

@export_group("Товары")
## Из чего собирается ассортимент. Каждый товар — ОДИН полный стак
## (патроны .45 — 20 шт., нож — 1 шт.). Раскупили — до перебора товара нет.
@export var stock_pool: Array[ItemData] = []
## Сколько товаров разыгрывать из stock_pool (без повторов, чистый рандом).
## 0 — продаётся весь список.
@export_range(0, 50) var offers_count: int = 0
## Перебирать ассортимент в начале каждого забега (торговцы лабиринта).
## TODO (хаб): обновление каждый игровой день — ~10 товаров из пула, в
## идеале с весом по редкости — когда появится смена дней.
@export var restock_each_run: bool = false

@export_group("Цены")
## Наценка: цена покупки = base_price * price_multiplier * сюжетный
## множитель (TradeManager.set_price_factor). Лабиринт — ~1.5.
@export_range(0.1, 10.0, 0.05) var price_multiplier: float = 1.0
## Сколько от base_price торговец платит при скупке. Изношенное —
## ещё и пропорционально оставшейся прочности. Ключевые не скупает.
@export_range(0.0, 1.0, 0.05) var sell_ratio: float = 0.5


func get_id() -> String:
	return merchant_id if not merchant_id.is_empty() else resource_path
