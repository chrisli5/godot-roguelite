# res://components/utility/validation_utility.gd
class_name ValidationUtility
extends RefCounted

## Validates an array of property names on a given target object.
## Returns true if ALL properties are valid, false if any are missing.
static func validate_components(target: Node, property_names: Array[String]) -> bool:
	var missing_components: Array[String] = []
	
	for prop in property_names:
		# Dynamically retrieve the property value from the target node
		var value = target.get(prop)
		
		# If the slot is empty or points to a freed node wrapper, flag it
		if not is_instance_valid(value):
			missing_components.append(prop)
			
	if not missing_components.is_empty():
		push_error("CONFIGURATION ERROR: '%s' is missing required assignments for: %s" % [
			target.name, 
			", ".join(missing_components)
		])
		return false
		
	return true
