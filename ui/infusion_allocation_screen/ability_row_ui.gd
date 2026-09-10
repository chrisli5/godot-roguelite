class_name AbilityRowUI
extends Button

@export_group("Internal UI Labels Layout")
## Label display box rendering the target ability name (e.g., "Arcane Missile")
@export var weapon_name_label: Label
## Label display box rendering the level overview strings (e.g., "Fire: Lvl 3 | Frost: Lvl 1")
@export var level_details_label: Label


## Setup and render the row contents using the type-safe integer array sent by the allocation panel
func setup_row_display(ability_name: String, infusion_levels: Array[int], is_allowed: bool) -> void:
	# 1. Update the display name layout
	if is_instance_valid(weapon_name_label):
		weapon_name_label.text = ability_name
	else:
		text = ability_name # Fallback text format if nested labels are unassigned
		
	# 2. Compile active element levels text string via direct array indexing maps
	var status_fragments: Array[String] = []
	
	# Symmetrically extract element depth tracking metrics based on array slot positioning
	# (Index 0 = Fire, 1 = Frost, 2 = Lightning, 3 = Wind, 4 = Earth)
	if infusion_levels.size() >= 5:
		var fire_lvl: int = infusion_levels[0]
		var frost_lvl: int = infusion_levels[1]
		var lightning_lvl: int = infusion_levels[2]
		var wind_lvl: int = infusion_levels[3]
		var earth_lvl: int = infusion_levels[4]
		
		if fire_lvl > 0: status_fragments.append("Fire: Lvl %d" % fire_lvl)
		if frost_lvl > 0: status_fragments.append("Frost: Lvl %d" % frost_lvl)
		if lightning_lvl > 0: status_fragments.append("Lightning: Lvl %d" % lightning_lvl)
		if wind_lvl > 0: status_fragments.append("Wind: Lvl %d" % wind_lvl)
		if earth_lvl > 0: status_fragments.append("Earth: Lvl %d" % earth_lvl)
	else:
		push_error("WeaponRowUI: Received an improperly initialized or truncated infusion levels array.")
			
	# 3. Render the compiled text to the label box
	if is_instance_valid(level_details_label):
		if status_fragments.is_empty():
			level_details_label.text = "No Element Sockets Active"
		else:
			level_details_label.text = " | ".join(status_fragments)
			
	# 4. Dynamic Visual Gating: Disable and dim the button frame container node if the infusion is blocked
	disabled = not is_allowed
	
	if disabled:
		modulate = Color(0.4, 0.4, 0.4, 1.0) # Dimmed slate locked color
		tooltip_text = "Socket Soft Cap / Constraints Reached for this Ability Slot Index."
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0) # Full brightness default
		tooltip_text = "Click to allocate selected elemental infusion into this weapon slot DNA."
