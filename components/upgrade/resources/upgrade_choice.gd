class_name UpgradeChoice
extends RefCounted

var source_tracker: UpgradeTracker
## Destination lane mapping (0 for Player Character Core, 1-4 for hotbar weapon slot indices).
var target_slot_index: int = 0
## The scannable category name of the target being upgraded (e.g., "Character Core", "Arcane Missile").
var target_display_name: String = ""

var definition: UpgradeDefinition:
	get:
		return source_tracker.definition if is_instance_valid(source_tracker) else null

var display_name: String:
	get:
		return definition.display_name if is_instance_valid(definition) else ""

var is_infusion: bool:
	get:
		return definition.is_infusion() if is_instance_valid(definition) else false

var infusion_element: Tags.Type:
	get:
		return definition.get_infusion_element() if is_instance_valid(definition) else Tags.Type.NONE

var description: String:
	get:
		return definition.description if is_instance_valid(definition) else ""
