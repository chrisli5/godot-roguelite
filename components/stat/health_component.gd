class_name HealthComponent
extends Node


signal health_changed(current_health: float, max_health: float)
signal health_depleted
## Emitted for damage-over-time ticks only, so damage numbers and hit effects can tell them
## apart from hits. Hits do not emit this.
signal dot_damage_taken(amount: float)

var current_health: float = 0.0
var max_health: float = 10.0


func bind_to_stats(stats: StatsContainer) -> void:
	var has_stats := is_instance_valid(stats)
	if has_stats:
		stats.stat_updated.connect(_on_stat_updated)
	
	var initial_max = stats.get_final_stat_value(Stat.Type.MAX_HEALTH) if has_stats else 1.0
	update_max_health(initial_max)
	set_to_full()


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


## Restores a saved life total (clamped to the current maximum). Use after max health is final.
func restore_current_health(saved_health: float) -> void:
	current_health = clamp(saved_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)


## Process health reductions programmatically.
func take_damage(amount: float) -> void:
	_reduce_health(amount)


## Damage-over-time path: bypasses the hurtbox/hit pipeline and emits dot_damage_taken.
func take_dot_damage(amount: float) -> void:
	if _reduce_health(amount):
		dot_damage_taken.emit(amount)


## Applies the reduction. Returns false if nothing was applied (non-positive amount or already dead).
func _reduce_health(amount: float) -> bool:
	if amount <= 0.0 or current_health <= 0.0:
		return false

	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		health_depleted.emit()
	return true


## Process healing programmatically.
func heal(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
		
	current_health = clamp(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.MAX_HEALTH:
		update_max_health(new_value)
