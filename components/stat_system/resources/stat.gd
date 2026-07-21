class_name Stat
extends Resource

signal value_changed(new_value: float)

enum Type {
	MAX_HEALTH,
	MANA,
	ATTACK,
	SPEED,
	DAMAGE,
	COOLDOWN,
	ACCELERATION,
	FRICTION,
}

@export var type: Type = Type.MAX_HEALTH
@export var base_value: float = 0.0:
	set(value):
		base_value = value
		update_value()

@export var max_value: float = 9999.0:
	set(value):
		max_value = value
		update_value()
		
var current_value: float = 0.0
var modifiers: Array[StatModifier] = []


func add_modifier(modifier: StatModifier) -> void:
	remove_modifier(modifier.id)
	modifiers.append(modifier)
	update_value()


func remove_modifier(modifier_id: String) -> void:
	for i in range(modifiers.size()):
		if modifiers[i].id == modifier_id:
			modifiers.remove_at(i)
			update_value()
			break


func update_value() -> void:
	var flat_total: float = base_value
	var percent_total: float = 0.0
	
	for modifier in modifiers:
		if modifier.type == StatModifier.Type.FLAT:
			flat_total += modifier.value
		elif modifier.type == StatModifier.Type.PERCENT:
			percent_total += modifier.value
	
	var final_value: float = flat_total * (1.0 + percent_total)
	current_value = clamp(final_value, 0.0, max_value)
	value_changed.emit(current_value)


func get_stat_name() -> String:
	return Type.keys()[type].to_lower()
