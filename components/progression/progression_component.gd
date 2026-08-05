class_name ProgressionComponent
extends Node

signal experience_gained(gained_amount: float, total_xp: float)

@export var thresholds_profile: LevelThresholdsProfile

var current_level: int = 1
var current_xp: float = 0.0
var total_accumulated_xp: float = 0.0

## Adds raw experience points and iteratively handles multi-level ups.
func gain_experience(amount: float) -> void:
	if amount <= 0.0:
		return
		
	current_xp += amount
	total_accumulated_xp += amount
	experience_gained.emit(amount, current_xp)
	
	_evaluate_progression_loop()

func _evaluate_progression_loop() -> void:
	if not thresholds_profile:
		push_warning("ProgressionComponent: Missing LevelThresholdsProfile configuration resource.")
		return

	var required_xp: float = thresholds_profile.get_required_xp_for_level(current_level + 1)
	
	# Check if current XP can clear the next level tier threshold
	while current_xp >= required_xp:
		current_xp -= required_xp
		current_level += 1
		
		EventBus.player_leveled_up.emit(current_level)
		print("level: ", current_level)
		# Fetch next evaluation target tier ceiling dynamically
		required_xp = thresholds_profile.get_required_xp_for_level(current_level + 1)
