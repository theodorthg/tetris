class_name PauseButton
extends Control

## Frosted-glass round pause button. The Control rect is the (generous) hit
## area; the glyph is drawn smaller and centred, so a slightly-off thumb tap
## still lands. Fires `tapped` the moment it is pressed (touch or mouse) so a
## near-miss never turns into a game tap.

signal tapped

const PAD := 9.0   ## hit area is this many px wider than the drawn disc, per side
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
	var bw := r * 0.26
	var bh := r * 0.86
	var off := r * 0.30
	var col := Color(1, 1, 1, 0.9)
	draw_rect(Rect2(c.x - off - bw, c.y - bh * 0.5, bw, bh), col)
	draw_rect(Rect2(c.x + off, c.y - bh * 0.5, bw, bh), col)
