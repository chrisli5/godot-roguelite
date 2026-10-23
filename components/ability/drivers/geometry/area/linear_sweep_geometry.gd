# res://components/ability/drivers/geometry/linear_sweep_geometry.gd
class_name LinearSweepGeometry
extends AreaGeometry

@export_group("Sweep Geometry Parameters")
@export var strike_length: float = 120.0
@export var cone_angle_degrees: float = 60.0


## Override Hook: Generates a custom procedural wedge directly facing the player's vector
func get_query_shape(stats: StatsContainer) -> Shape2D:
	var target_direction := Vector2.RIGHT
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(player):
		target_direction = player.velocity.normalized() if player.velocity != Vector2.ZERO else Vector2.RIGHT

	var half_arc_rad := deg_to_rad(cone_angle_degrees / 2.0)
	var base_angle := target_direction.angle()

	var reach := _get_area_radius(stats, strike_length)
	var vertex_left := Vector2.from_angle(base_angle - half_arc_rad) * reach
	var vertex_right := Vector2.from_angle(base_angle + half_arc_rad) * reach

	var wedge_shape := ConvexPolygonShape2D.new()
	wedge_shape.points = PackedVector2Array([Vector2.ZERO, vertex_left, vertex_right])
	return wedge_shape
