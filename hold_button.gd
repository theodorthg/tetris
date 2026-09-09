class_name HoldButton
extends Control

## Frosted-glass round HOLD button (a "swap" glyph). Same as PauseButton: the
## Control rect is a generous hit area, the glyph is drawn smaller, and it fires
## on press so a near-miss never becomes a game tap.

signal tapped

const PAD := 9.0
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

	var col := Color(1, 1, 1, 0.9)
	var w := r * 0.92
	var gap := r * 0.30
	var head := r * 0.24
	var ty := c.y - gap
	draw_line(Vector2(c.x - w * 0.5, ty), Vector2(c.x + w * 0.5, ty), col, 2.0)
	draw_line(Vector2(c.x - w * 0.5, ty), Vector2(c.x - w * 0.5 + head, ty - head), col, 2.0)
	draw_line(Vector2(c.x - w * 0.5, ty), Vector2(c.x - w * 0.5 + head, ty + head), col, 2.0)
	var by := c.y + gap
	draw_line(Vector2(c.x - w * 0.5, by), Vector2(c.x + w * 0.5, by), col, 2.0)
	draw_line(Vector2(c.x + w * 0.5, by), Vector2(c.x + w * 0.5 - head, by - head), col, 2.0)
	draw_line(Vector2(c.x + w * 0.5, by), Vector2(c.x + w * 0.5 - head, by + head), col, 2.0)
