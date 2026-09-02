@abstract
class_name Entity
extends CharacterBody2D

signal died

@export_group("Components")
@export var ability_container: AbilityContainer
@export var stats_container: StatsContainer
@export var movement_component: MovementComponent
@export var status_effect_component: StatusEffectComponent
@export var tag_component: TagComponent

@export_group("Stats Profile")
@export var stats_profile: StatsProfile


func _ready() -> void:
	var components_valid: bool = true
	
	if not stats_container:
		push_error("Entity '%s' is missing a StatsContainer!" % name)
		components_valid = false
	if not stats_profile:
		push_error("Entity '%s' is missing a StatsProfile!" % name)
		components_valid = false
	if not movement_component:
		push_error("Entity '%s' is missing a MovementComponent!" % name)
		components_valid = false
	
	if not components_valid:
		return
			
	stats_container.initialize_profile(stats_profile)


@abstract
func _handle_movement_physics() -> void
