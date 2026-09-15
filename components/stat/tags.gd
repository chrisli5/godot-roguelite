class_name Tags
extends Node

# Grouped logically by function for easy inspector assignment
enum Type {
	NONE,
	
	# Core Archetypes
	MARTIAL,
	METAMAGIC,
	HAZARD,
	INFUSION,
	OVERCLOCK,
	
	# Delivery Mechanics
	MELEE,
	PROJECTILE,
	AOE,
	
	# Elements
	FIRE,
	FROST,
	LIGHTNING,
	WIND,
	EARTH,
	
	# Lifecycle / Triggers
	ON_HIT,
	ON_DASH,
	DOT,
	CROWD_CONTROL,
}

## UNIVERSAL TRANSLATOR INDEX MAPPER
## Maps both generic elements and specialized tracking sockets to their deterministic array slots.
## Position 0=Fire, 1=Frost, 2=Lightning, 3=Wind, 4=Earth.
static func get_index_from_element(element_tag: Tags.Type) -> int:
	match element_tag:
		Tags.Type.FIRE: 
			return 0
		Tags.Type.FROST: 
			return 1
		Tags.Type.LIGHTNING: 
			return 2
		Tags.Type.WIND: 
			return 3
		Tags.Type.EARTH: 
			return 4
		_: 
			return -1

# Helper to turn an array of Enums into scannable bitwise flags if maximum performance is needed
static func get_tag_name(tag_type: Type) -> String:
	return Type.keys()[tag_type].to_lower()
