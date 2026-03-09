extends MapObject2D
class_name ForestStandObject

@export var canopy_color := Color(0.10, 0.36, 0.16, 1.0)
@export var canopy_color_2 := Color(0.16, 0.48, 0.20, 1.0)
@export var trunk_color := Color(0.34, 0.24, 0.12, 1.0)
@export var scale_factor := 1.0
@export var tropical_mix := 0.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var trunk_w := 4.0 * scale_factor
	var trunk_h := 10.0 * scale_factor
	var canopy_r1 := 8.0 * scale_factor
	var canopy_r2 := 6.0 * scale_factor

	var trunk_rect := Rect2(Vector2(-trunk_w * 0.5, -trunk_h * 0.2), Vector2(trunk_w, trunk_h))
	draw_rect(trunk_rect, trunk_color)

	var c1 := canopy_color.lerp(canopy_color_2, tropical_mix)
	var c2 := canopy_color_2.lerp(Color(0.18, 0.60, 0.24, 1.0), tropical_mix)

	draw_circle(Vector2(-4.0 * scale_factor, -8.0 * scale_factor), canopy_r2, c2)
	draw_circle(Vector2(4.0 * scale_factor, -8.0 * scale_factor), canopy_r2, c2)
	draw_circle(Vector2(0.0, -12.0 * scale_factor), canopy_r1, c1)
