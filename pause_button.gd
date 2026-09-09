class_name PauseButton
extends Control

## Small frosted-glass round pause button for the HUD (mirrors pacman's).
## Emits `tapped` on a press-release; works with touch and mouse.

signal tapped

var _down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	var release: bool = (event is InputEventScreenTouch and not event.pressed) \
		or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if press:
		_down = true
		queue_redraw()
		accept_event()
	elif release and _down:
		_down = false
		queue_redraw()
		tapped.emit()
		accept_event()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# frosted disc
	draw_circle(c, r, Color(0.85, 0.9, 1.0, 0.14 if not _down else 0.22))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 1.5)
	# two bars
	var bw := r * 0.26
	var bh := r * 0.86
	var off := r * 0.30
	var col := Color(1, 1, 1, 0.9)
	draw_rect(Rect2(c.x - off - bw, c.y - bh * 0.5, bw, bh), col)
	draw_rect(Rect2(c.x + off, c.y - bh * 0.5, bw, bh), col)
