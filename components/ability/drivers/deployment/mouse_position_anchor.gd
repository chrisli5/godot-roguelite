# res://components/ability/drivers/deployment/mouse_position_anchor.gd
class_name MousePositionAnchor
extends DeploymentAnchor

func get_anchor_position(_caster: Node2D) -> Vector2:
	return _caster.get_global_mouse_position()
