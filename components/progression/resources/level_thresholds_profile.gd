# res://components/progression_system/resources/level_thresholds_profile.gd
class_name LevelThresholdsProfile
extends Resource

## Static mapping of specific level caps to their total required experience.
@export var custom_thresholds: Dictionary = {}

## Fallback formula coefficients if a specific level isn't in custom_thresholds.
@export var base_xp_requirement: float = 20.0
@export var exponent_multiplier: float = 1.2

## Calculates the required total XP needed to reach a specific level target.
func get_required_xp_for_level(target_level: int) -> float:
	if custom_thresholds.has(target_level):
		return custom_thresholds[target_level]
	
	# Exponential curve calculation formula: Base * (Level ^ Multiplier)
	return floor(base_xp_requirement * pow(target_level, exponent_multiplier))
