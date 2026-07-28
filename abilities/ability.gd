@abstract
class_name Ability
extends Node

@export_group("Components")
@export var stats_container: StatsContainer

var id: int:
	get: return get_instance_id()


@abstract
func cast(caster: Entity, target: Entity) -> void
