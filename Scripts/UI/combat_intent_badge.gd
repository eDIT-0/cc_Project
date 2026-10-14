class_name CombatIntentBadge
extends Control
## Иконка намерения. Геометрические символы не зависят от emoji-шрифта.
## У атаки можно назначить свою текстуру; без неё используется символ по тегам.

var kind: String = "wait"
var icon: Texture2D
var tint: Color = Color("5e9fe8")


func _ready() -> void:
	custom_minimum_size = Vector2(36, 36)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_intent(attack: EnemyAttack, helping: bool, alive: bool) -> void:
	icon = attack.intent_icon if attack != null else null
	kind = "wait"
	if not alive:
		kind = "out"
		icon = null
	elif helping or (attack != null and (attack.joint or attack.tags.has("joint"))):
		kind = "joint"
	elif attack != null:
		if attack.tags.has("stun") or attack.stun_seconds > 0.0:
			kind = "stun"
		elif attack.tags.has("grapple") or attack.immobilize_seconds > 0.0:
			kind = "grapple"
		elif attack.tags.has("lewd") or attack.arousal > 0:
			kind = "lewd"
		else:
			kind = "strike"
	match kind:
		"joint": tint = Color("bf8eda")
		"stun": tint = Color("eac26b")
		"grapple": tint = Color("de9255")
		"lewd": tint = Color("df84a8")
		"strike": tint = Color("e97366")
		_: tint = Color("8895a8")
	queue_redraw()


func _draw() -> void:
	var bg := tint
	bg.a = 0.12
	draw_style_box(_box(bg), Rect2(Vector2.ZERO, size))
	if icon != null:
		var texture_size := icon.get_size()
		if texture_size.x > 0 and texture_size.y > 0:
			var scale_factor := minf((size.x - 8.0) / texture_size.x, (size.y - 8.0) / texture_size.y)
			var fitted := texture_size * scale_factor
			draw_texture_rect(icon, Rect2((size - fitted) / 2.0, fitted), false)
		return
	var center := size / 2.0
	match kind:
		"strike":
			draw_colored_polygon(PackedVector2Array([center + Vector2(-2, 5), center + Vector2(8, -9), center + Vector2(10, -10), center + Vector2(9, -5), center + Vector2(2, 6)]), tint)
			draw_line(center + Vector2(-6, 2), center + Vector2(4, 10), tint, 2.0, true)
			draw_line(center + Vector2(-2, 6), center + Vector2(-8, 12), tint, 3.0, true)
		"stun":
			draw_colored_polygon(PackedVector2Array([center + Vector2(3, -12), center + Vector2(-8, 2), center + Vector2(-1, 2), center + Vector2(-4, 12), center + Vector2(9, -3), center + Vector2(2, -3)]), tint)
		"grapple":
			draw_arc(center + Vector2(-4, -2), 7, 0, TAU, 24, tint, 2.5, true)
			draw_arc(center + Vector2(4, 2), 7, 0, TAU, 24, tint, 2.5, true)
		"joint":
			draw_circle(center + Vector2(-6, -6), 4, tint)
			draw_circle(center + Vector2(6, -6), 4, tint)
			draw_line(center + Vector2(-6, 0), center + Vector2(-6, 8), tint, 4.0, true)
			draw_line(center + Vector2(6, 0), center + Vector2(6, 8), tint, 4.0, true)
			draw_line(center + Vector2(-6, 3), center + Vector2(6, 3), tint, 2.0, true)
		"lewd":
			draw_circle(center + Vector2(-5, -4), 6, tint)
			draw_circle(center + Vector2(5, -4), 6, tint)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-11, -2), center + Vector2(11, -2), center + Vector2(0, 12)]), tint)
		"out":
			draw_line(center + Vector2(-7, -7), center + Vector2(7, 7), tint, 2.0, true)
			draw_line(center + Vector2(7, -7), center + Vector2(-7, 7), tint, 2.0, true)
		_:
			draw_arc(center, 10, 0, TAU, 32, tint, 2.0, true)
			draw_line(center, center + Vector2(0, -6), tint, 2.0, true)
			draw_line(center, center + Vector2(5, 3), tint, 2.0, true)


func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	return box
