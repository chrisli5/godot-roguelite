class_name DeploymentAnchor
extends Node

func get_anchor_position(caster: Node2D) -> Vector2:
	if is_instance_valid(caster):
		return caster.global_position
	return Vector2.ZERO
