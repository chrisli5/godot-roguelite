class_name HealthComponent
extends Node


signal health_changed(current_health: float, max_health: float)
signal health_depleted

var current_health: float = 0.0
var max_health: float = 10.0


## Called exclusively by the parent node during initialization or stat updates.
func update_max_health(new_max: float, should_heal_difference: bool = false) -> void:
	if new_max <= 0.0:
		return
		
	var previous_max = max_health
	max_health = new_max
	
	if should_heal_difference and max_health > previous_max:
		current_health += (max_health - previous_max)
		
	current_health = clamp(current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)


## Parent commands this when resetting a life pool (e.g., spawn/respawn)
func set_to_full() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Process health reductions programmatically.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
		
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0.0:
		health_depleted.emit()


## Process healing programmatically.
func heal(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
		
	current_health = clamp(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
