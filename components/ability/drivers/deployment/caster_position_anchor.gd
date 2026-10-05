# res://components/ability/drivers/deployment/caster_position_anchor.gd
class_name CasterPositionAnchor
extends DeploymentAnchor

func get_anchor_position(caster: Node2D) -> Vector2:
	return super(caster)
