class_name HealthBarComponent
extends Node2D
## A small health bar drawn in code above an enemy. It shows only while the enemy is damaged.
## It knows nothing about HealthComponent: the entity calls set_health from health_changed.
## It is a top-level node that follows its parent's position, so the parent's rotation or flip never turns it.

@export var bar_size: Vector2 = Vector2(24, 3)
## Distance from the parent's origin to the bar's centre (negative y is above).
@export var offset: Vector2 = Vector2(0, -16)
@export var fill_color: Color = Color(0.85, 0.15, 0.15)
@export var low_health_color: Color = Color(1.0, 0.8, 0.1)
@export var background_color: Color = Color(0.08, 0.08, 0.08, 0.85)
## At or below this ratio the fill uses low_health_color.
@export_range(0.0, 1.0) var low_health_ratio: float = 0.3
@export var show_when_full: bool = false

var _ratio: float = 1.0


func _ready() -> void:
	top_level = true
	z_index = 10
	visible = false
	_follow_parent()


func _process(_delta: float) -> void:
	if visible:
		_follow_parent()


## Stores the health ratio and updates visibility. Redraws only when the ratio or visibility changed.
func set_health(current: float, maximum: float) -> void:
	var new_ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	var new_visible := _should_show(new_ratio)
	var changed := not is_equal_approx(new_ratio, _ratio) or new_visible != visible
	_ratio = new_ratio
	visible = new_visible
	if visible:
		_follow_parent()
	if changed:
		queue_redraw()


## The stored health ratio, 0..1.
func get_ratio() -> float:
	return _ratio


## True when the fill uses low_health_color.
func is_low() -> bool:
	return _ratio <= low_health_ratio


## The colour the fill is drawn with right now.
func get_fill_color() -> Color:
	return low_health_color if is_low() else fill_color


func _should_show(ratio: float) -> bool:
	if ratio <= 0.0:
		return false
	return ratio < 1.0 or show_when_full


func _follow_parent() -> void:
	var parent_node := get_parent() as Node2D
	if parent_node != null:
		global_position = parent_node.global_position + offset


func _draw() -> void:
	var top_left := -bar_size * 0.5
	draw_rect(Rect2(top_left, bar_size), background_color)
	if _ratio > 0.0:
		draw_rect(Rect2(top_left, Vector2(bar_size.x * _ratio, bar_size.y)), get_fill_color())
