class_name AbilityRowUI
extends Button

@export_group("Internal UI Labels Layout")
## Label display box rendering the target ability name (e.g., "Arcane Missile")
@export var weapon_name_label: Label
## Label display box rendering the level overview strings (e.g., "Fire: Lvl 3 | Frost: Lvl 0")
@export var level_details_label: Label


## Setup and render the row contents using the data dictionaries sent by the main screen
func setup_row_display(ability_name: String, purchase_levels: Dictionary[String, int], is_allowed: bool) -> void:
	# 1. Update the display name layout
	if is_instance_valid(weapon_name_label):
		weapon_name_label.text = ability_name
	else:
		text = ability_name # Fallback text format if nested labels are unassigned
		
	# 2. Compile and format active element levels text string cleanly on the fly
	var status_fragments: Array[String] = []
	
	for key in purchase_levels.keys():
		if key.begins_with("inf_"):
			# Format string matching: "inf_fire" -> "Fire"
			var element_clean_name = key.replace("inf_", "").capitalize()
			var current_level_num = purchase_levels[key]
			
			if current_level_num > 0:
				status_fragments.append("%s: Lvl %d" % [element_clean_name, current_level_num])
				
	if is_instance_valid(level_details_label):
		if status_fragments.is_empty():
			level_details_label.text = "No Element Sockets Active"
		else:
			level_details_label.text = " | ".join(status_fragments)
			
	# 3. Dynamic Visual Gating: Disable and dim the button frame container node if the infusion is blocked
	disabled = not is_allowed
	
	if disabled:
		modulate = Color(0.4, 0.4, 0.4, 1.0) # Dimmed slate locked color
		tooltip_text = "Socket Soft Cap / Constraints Reached for this Ability Slot Index."
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0) # Full brightness default
		tooltip_text = "Click to allocate selected elemental infusion into this weapon slot DNA."
