# res://components/stat/resources/stat.gd
class_name Stat
extends Resource

signal value_changed(new_value: float)

enum Type {
	MAX_HEALTH,
	MOVEMENT_SPEED,
	ACCELERATION,
	FRICTION,
	
	BASE_DAMAGE,
	COOLDOWN,
	CRIT_CHANCE,
	CRIT_MULTIPLIER,
	DURATION,
	
	AOE_RADIUS,
	CHAIN_RADIUS,
	ORBIT_RADIUS,
	QUERY_RADIUS,
	
	PROJECTILE_MOVEMENT_SPEED,
	ORBIT_ROTATION_SPEED,
	
	PROJECTILE_AMOUNT,
	MAX_TARGETS,
}

@export var type: Type = Type.MAX_HEALTH
@export var base_value: float = 0.0
@export var max_value: float = 9999.0

## The active computed value for the frame pass
var current_value: float = 0.0
var is_dirty: bool = true

## The transient pool: Houses temporary buffs, debuffs, dots, and gear modifiers
var transient_modifiers: Array[StatModifier] = []


func add_transient_modifier(modifier: StatModifier) -> void:
	remove_transient_modifier(modifier.id)
	transient_modifiers.append(modifier)
	is_dirty = true # Flag as dirty instantly when a temporary buff hits us


func remove_transient_modifier(modifier_id: String) -> void:
	for i in range(transient_modifiers.size()):
		if transient_modifiers[i].id == modifier_id:
			transient_modifiers.remove_at(i)
			is_dirty = true # Flag as dirty instantly when a status effect expires
			break


## Core Math Layer: Executed ONLY when the dirty flag is true and a read request arrives
func recalculate_runtime_value(ledger_progression_value: float) -> float:
	var flat_total: float = ledger_progression_value
	var percent_total: float = 0.0
	
	for modifier in transient_modifiers:
		if modifier.type == StatModifier.Type.FLAT:
			flat_total += modifier.value
		elif modifier.type == StatModifier.Type.PERCENT:
			percent_total += modifier.value
	
	var final_value: float = flat_total * (1.0 + percent_total)
	current_value = clamp(final_value, 0.0, 9999.0)
	
	is_dirty = false # Cache is now clean!
	value_changed.emit(current_value)
	return current_value


## Utility helper converting the Enum value back into a clean string identifier
func get_stat_name() -> String:
	return Type.keys()[type].to_lower()
