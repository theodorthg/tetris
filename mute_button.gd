class_name MuteButton
extends Control

## Frosted-glass round mute button next to the pause button (same look as
## PauseButton). The speaker is hand-drawn (cone + sound waves, or a diagonal
## cross when muted) - no font glyph. The Control rect is the generous hit
## area; the disc is drawn PAD px smaller per side.

signal tapped

const PAD := 9.0
var muted := false:
	set(v):
		muted = v
		queue_redraw()
var _down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	var release: bool = (event is InputEventScreenTouch and not event.pressed) \
		or (event is InputEventMouseButton and not event.pressed)
	if press:
		_down = true
		queue_redraw()
		tapped.emit()
		accept_event()
	elif release:
		_down = false
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - PAD
	draw_circle(c, r, Color(0.85, 0.9, 1.0, 0.24 if _down else 0.14))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.24), 1.5)
	var s := r * 0.42
	var col := Color(1, 1, 1, 0.9)
	var cone_x := c.x - s * 0.55
	var body_w := s * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(cone_x - body_w, c.y - s * 0.38),
		Vector2(cone_x, c.y - s * 0.38),
		Vector2(cone_x + s * 0.7, c.y - s),
		Vector2(cone_x + s * 0.7, c.y + s),
		Vector2(cone_x, c.y + s * 0.38),
		Vector2(cone_x - body_w, c.y + s * 0.38),
	]), col)
	if muted:
		var d := s * 0.75
		var x0 := c.x + s * 0.75
		draw_line(Vector2(x0 - d * 0.3, c.y - d), Vector2(x0 + d, c.y + d), col, 2.0, true)
		draw_line(Vector2(x0 - d * 0.3, c.y + d), Vector2(x0 + d, c.y - d), col, 2.0, true)
	else:
		for i in [1, 2]:
			var rad: float = s * (0.6 + i * 0.5)
			draw_arc(Vector2(cone_x + s * 0.7, c.y), rad, -PI * 0.32, PI * 0.32, 10, col, 2.0, true)
