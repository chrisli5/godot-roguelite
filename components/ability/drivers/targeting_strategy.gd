@abstract
class_name TargetingStrategy
extends Node

## Virtual Method: Called by the parent wrapper's core timer loop execution pass.
## Returns a normalized directional vector representing where the geometry driver should aim.
@abstract
## { "direction": Vector2, "target_node": Node2D }
func get_targeting_data(global_origin: Vector2, query_radius: float) -> Dictionary
