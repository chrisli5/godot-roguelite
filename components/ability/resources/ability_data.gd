class_name AbilityData
extends Resource

enum AbilityRole { 
	PRIMARY_WEAPON = 1,   # Hotbar Slot 1 (Dictionary Key 1)
	MOVEMENT_UTILITY = 2,  # Hotbar Slot 2 (Dictionary Key 2)
	DEFENSIVE_SPELL = 3,   # Hotbar Slot 3 (Dictionary Key 3)
	ULTIMATE_CORE = 4      # Hotbar Slot 4 (Dictionary Key 4)
}

@export var display_name: String = ""
@export var slot_index: AbilityRole = AbilityRole.PRIMARY_WEAPON
@export var ability_scene: PackedScene
@export var stats_profile: StatsProfile
