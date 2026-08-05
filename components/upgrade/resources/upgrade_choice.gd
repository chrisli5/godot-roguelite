class_name UpgradeChoice
extends Object

var source_tracker: UpgradeTracker
var target_ability_id: int = 0

## The display name of the target being upgraded
var target_display_name: String = ""

# --- Clean Definition Proxies ---
var definition: UpgradeDefinition:
	get:
		return source_tracker.definition if is_instance_valid(source_tracker) else null

var display_name: String:
	get:
		return definition.display_name if is_instance_valid(definition) else ""

var description: String:
	get:
		return definition.description if is_instance_valid(definition) else ""
