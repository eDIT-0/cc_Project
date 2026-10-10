class_name DialogueBox
extends Control
## Общий проигрыватель .dialogue-файлов (аддон Dialogue Manager,
## res://addons/dialogue_manager) — один и тот же узел используется и в
## хабе, и в лабиринте, чтобы диалог выглядел и вёл себя ОДИНАКОВО в обеих
## сценах. Раньше это была почти одна и та же логика, продублированная
## отдельно в HubUI и в DebugMazeView — свели сюда, в один источник правды.
##
## Выбор варианта работает ОДНОВРЕМЕННО двумя способами — кликом по кнопке
## и цифрой 1-9 на клавиатуре (по порядку сверху вниз) — так проще
## тестировать, не отрываясь от клавиатуры. Долистать обычную реплику без
## вариантов — тоже можно и кликом по панели, и Пробелом/Enter.
##
## Публичный интерфейс для вызывающей сцены: play()/cancel()/is_active().
## Сигнал finished — диалог дочитан до конца сам (не отменён извне).

signal finished

@onready var _panel: Panel = %DialoguePanel
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _text_label: RichTextLabel = %DialogueText
@onready var _choices_container: VBoxContainer = %DialogueChoicesContainer

## Ресурс/реплика, которые сейчас проигрываются — нужно хранить самим,
## потому что get_next_dialogue_line() просто функция, а не сигнал: каждый
## следующий вызов требует и resource, и extra_game_states заново.
var _current_resource: Resource = null
var _current_line: DialogueLine = null
var _current_extra_game_states: Array = []
var _awaiting_choice: bool = false


func _ready() -> void:
	# По группе другие системы узнают, идёт ли сейчас диалог, не зная, в
	# какой сцене и где именно лежит DialogueBox (см. InventoryScreen).
	add_to_group("dialogue_box")
	_panel.visible = false
	_choices_container.visible = false
	_panel.gui_input.connect(_on_panel_gui_input)


## Идёт ли сейчас диалог — вызывающая сцена опрашивает это, чтобы знать,
## можно ли, например, двигать игрока (см. DebugMazeView._unhandled_input).
func is_active() -> bool:
	return _current_line != null


func play(resource: Resource, cue: String = "start", extra_game_states: Array = []) -> void:
	_current_resource = resource
	_current_extra_game_states = extra_game_states
	_current_line = await DialogueManager.get_next_dialogue_line(resource, cue, extra_game_states)
	_show_current_line()


## Принудительно закрыть диалог извне (например, при смене локации в хабе —
## если прошлый диалог не был дочитан, панель не должна "уехать" вместе со
## сценой). finished НЕ эмитится — это отмена, а не естественный конец.
func cancel() -> void:
	_current_resource = null
	_current_line = null
	_current_extra_game_states = []
	_awaiting_choice = false
	_panel.visible = false
	_choices_container.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_active() or not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if _awaiting_choice:
		# event.keycode — Key (enum), не int: разность двух Key операторный
		# вывод типа через := взять не может, поэтому аннотация явно.
		var index: int = event.keycode - KEY_1
		if index < 0 or index >= _choices_container.get_child_count():
			return
		var button := _choices_container.get_child(index) as Button
		# set_input_as_handled() — ДО emit(), а не после: у ответа может
		# быть мутация вроде GameManager.return_to_hub(), которая меняет
		# сцену. Если пометить событие обработанным уже после emit(), к
		# этому моменту узел может оказаться вне дерева (сцена сменилась),
		# и get_viewport() вернёт null — отсюда и был краш.
		get_viewport().set_input_as_handled()
		button.pressed.emit()
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	_current_line = await DialogueManager.get_next_dialogue_line(
		_current_resource, _current_line.next_id, _current_extra_game_states
	)
	_show_current_line()


## Клик по панели вне кнопок выбора — то же самое, что Пробел/Enter.
func _on_panel_gui_input(event: InputEvent) -> void:
	if _awaiting_choice or _current_line == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _show_current_line() -> void:
	if _current_line == null:
		var was_visible := _panel.visible
		cancel()
		if was_visible:
			finished.emit()
		return

	_panel.visible = true
	_speaker_label.text = _current_line.character
	_speaker_label.visible = not _current_line.character.is_empty()
	_text_label.text = _current_line.text

	if _current_line.responses.size() > 0:
		_show_responses(_current_line.responses)
	else:
		_awaiting_choice = false
		_choices_container.visible = false


func _show_responses(responses: Array[DialogueResponse]) -> void:
	_awaiting_choice = true

	for child in _choices_container.get_children():
		child.queue_free()

	var index := 0
	for response in responses:
		if not response.is_allowed:
			continue
		var button := Button.new()
		# focus_mode = FOCUS_NONE — иначе клик по кнопке заберёт клавиатурный
		# фокус, и следующий Пробел/Enter уйдёт сфокусированной кнопке как
		# ui_accept (= повторный клик по НЕЙ), а не в _unhandled_input сюда.
		# Клавиатуру мы обрабатываем сами через цифры — встроенный фокус
		# Control'ов тут только мешает.
		button.focus_mode = Control.FOCUS_NONE
		# Префикс цифрой — не просто подпись: именно по порядку этих кнопок
		# считает индекс и обработчик клавиш выше (1-9 = N-я видимая кнопка).
		button.text = "%d. %s" % [index + 1, response.text]
		button.pressed.connect(_on_response_pressed.bind(response))
		_choices_container.add_child(button)
		index += 1

	_choices_container.visible = true


func _on_response_pressed(response: DialogueResponse) -> void:
	_current_line = await DialogueManager.get_next_dialogue_line(
		_current_resource, response.next_id, _current_extra_game_states
	)
	_show_current_line()
