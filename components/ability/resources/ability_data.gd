class_name AbilityData
extends Resource

enum AbilityRole { 
	PRIMARY_WEAPON = 1,   # Hotbar Slot 1 (Automatic Engine)
	MOVEMENT_UTILITY = 2,  # Hotbar Slot 2 (Catalyst Grouping)
	DEFENSIVE_SPELL = 3,   # Hotbar Slot 3 (Payload Finisher)
	ULTIMATE_CORE = 4      # Hotbar Slot 4 (Dash Utility)
}

@export_group("Identification")
@export var display_name: String = ""
@export var slot_index: AbilityRole = AbilityRole.PRIMARY_WEAPON
@export var structural_tags: Array[Tags.Type] = []
@export var is_overclock_evolution: bool = false

@export_group("Core Blueprint Packages")
## Points to a single, completely uniform BaseAbility.tscn template
@export var base_ability_scene: PackedScene
@export var stats_profile: StatsProfile

@export_group("Unified Wrapper Architecture Strategy Prefabs")
## The spatial/delivery strategy component to inject (e.g., ProjectileLineDriver, AuraVortexDriver)
@export var geometry_driver_scene: PackedScene
## The secondary status modification layer to apply during execution ticks
@export var payload_driver_scene: PackedScene
