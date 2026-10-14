class_name EventPictures
extends RefCounted
## Картинки-вставки события (поверх фона, над диалогом): дыра в стене,
## кошелёк на земле, персонаж лезет в дыру... У события их сколько угодно —
## от одной до десятка, сменяются по ходу диалога.
##
## Кто запускает диалог, передаёт в extra_game_states {"pics": EventPictures.new(...)},
## DialogueBox находит его и показывает. Если не передали — DialogueBox
## подставляет пустой, так что команды ниже в любом диалоге не ломаются.
##
## В .dialogue:
##   do pics.show(1)    — показать картинку №1 (счёт с 0)
##   do pics.next()     — следующую (на последней — остаётся последняя)
##   do pics.hide()     — убрать вставку
## Команда срабатывает, когда диалог до неё дошёл, — т.е. картинка
## меняется вместе со следующей репликой.
##
## Пока это только фундамент: как именно выглядит вставка, решит будущий UI
## (сейчас — простая рамка в DialogueBox). Анимации, переходы — потом.

## Сменилась картинка (null — вставку спрятать).
signal changed(texture: Texture2D)

var images: Array[Texture2D] = []
## Какая сейчас показана (-1 — никакая).
var current: int = -1


## show_first — сразу показать картинку №0 при начале диалога.
func _init(event_images: Array[Texture2D] = [], show_first: bool = true) -> void:
	images = event_images
	if show_first and not images.is_empty():
		current = 0


func get_texture() -> Texture2D:
	return images[current] if current >= 0 and current < images.size() else null


func show(index: int) -> void:
	if index < 0 or index >= images.size():
		push_warning("EventPictures.show(%d): у события всего %d картинок." % [index, images.size()])
		return
	current = index
	changed.emit(get_texture())


func next() -> void:
	if images.is_empty():
		return
	show(mini(current + 1, images.size() - 1))


func hide() -> void:
	current = -1
	changed.emit(null)
