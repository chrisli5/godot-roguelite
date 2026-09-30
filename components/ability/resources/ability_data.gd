class_name AbilityData
extends Resource

enum Role { 
	PRIMARY_WEAPON = 1,   # Hotbar Slot 1 (Automatic Engine)
	MOVEMENT_UTILITY = 2,  # Hotbar Slot 2 (Catalyst Grouping)
	DEFENSIVE_SPELL = 3,   # Hotbar Slot 3 (Payload Finisher)
	ULTIMATE_CORE = 4      # Hotbar Slot 4 (Dash Utility)
}

enum CastOrigin {
	CASTER_POSITION,
	MOUSE_POSITION,
	TARGET_POSITION,
}

enum QueryOrigin {
	CASTER_POSITION,
	MOUSE_POSITION,
}

@export_group("Identification")
@export var display_name: String = ""
@export var texture_prefab: Texture2D
@export var slot_index: Role = Role.PRIMARY_WEAPON
@export var structural_tags: Array[Tags.Type] = []
@export var is_overclock_evolution: bool = false

@export_group("Core Blueprint Packages")
@export var stats_profile: StatsProfile
@export var upgrade_blueprints: Array[UpgradeBlueprintProfile] = [] 

@export_group("Spatial Deployment Settings")
@export var cast_origin: CastOrigin = CastOrigin.CASTER_POSITION
@export var query_origin: QueryOrigin = QueryOrigin.CASTER_POSITION

@export_group("Unified Wrapper Architecture Strategy Prefabs")
@export var base_ability_scene: PackedScene
@export var geometry_driver_scene: PackedScene
@export var payload_driver_scene: PackedScene
@export var targeting_strategy_scene: PackedScene 
