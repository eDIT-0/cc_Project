class_name CombatDiamondButton
extends Button
## Кнопка с ромбовидной областью клика и заливкой снизу вверх.
## Заполнение = текущая энергия / цена действия, а не общая шкала 0..100.

var caption: String = ""
var key_caption: String = ""
var energy_cost: float = 30.0
var energy: float = 0.0
var accent: Color = Color("5e9fe8")
var compact: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_charge(value: float, cost: float, available: bool) -> void:
	energy = maxf(0.0, value)
	energy_cost = maxf(0.01, cost)
	disabled = not available
	queue_redraw()


func get_fill_ratio() -> float:
	return clampf(energy / energy_cost, 0.0, 1.0)


func _has_point(point: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var p := point - size / 2.0
	return absf(p.x) / (size.x / 2.0) + absf(p.y) / (size.y / 2.0) <= 1.0


func _gui_input(event: InputEvent) -> void:
	# Касание работает и без глобальной эмуляции мыши.
	if event is InputEventScreenTouch and event.pressed and not disabled:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var inset := 3.0
	var points := PackedVector2Array([
		Vector2(size.x / 2.0, inset), Vector2(size.x - inset, size.y / 2.0),
		Vector2(size.x / 2.0, size.y - inset), Vector2(inset, size.y / 2.0)])
	draw_colored_polygon(points, Color("171e29"))
	var fill := _clip_below(points, lerpf(size.y - inset, inset, get_fill_ratio()))
	if fill.size() >= 3:
		var fill_color := accent
		fill_color.a = 0.26 if disabled else (0.75 if is_pressed() else 0.56)
		draw_colored_polygon(fill, fill_color)
	var border := Color("455268") if disabled else accent.lightened(0.25)
	if not disabled and is_hovered():
		border = Color.WHITE
	var outline := points.duplicate()
	outline.append(points[0])
	if not disabled:
		var glow := accent
		glow.a = 0.18
		draw_polyline(outline, glow, 7.0, true)
	draw_polyline(outline, border, 1.5 if disabled else 2.0, true)
	var font := get_theme_default_font()
	var font_size := 12 if compact else 14
	var ink := Color("aab6c8") if disabled else Color("f4f7fc")
	_draw_centered(font, key_caption, font_size - 1, size.y / 2.0 - 13.0, ink)
	_draw_centered(font, caption, font_size, size.y / 2.0 + 3.0, ink)
	_draw_centered(font, "%.0f%%" % energy_cost, font_size - 1, size.y / 2.0 + 18.0, ink)


func _draw_centered(font: Font, line: String, font_size: int, baseline: float, color: Color) -> void:
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) / 2.0, baseline), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _clip_below(polygon: PackedVector2Array, y: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var previous := polygon[polygon.size() - 1]
	for current in polygon:
		var previous_inside := previous.y >= y
		var current_inside := current.y >= y
		if previous_inside != current_inside:
			var t := (y - previous.y) / (current.y - previous.y)
			result.append(previous.lerp(current, t))
		if current_inside:
			result.append(current)
		previous = current
	return result
