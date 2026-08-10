class_name Tags
extends Node

# Grouped logically by function for easy inspector assignment
enum Type {
	# Core Archetypes
	MARTIAL,
	METAMAGIC,
	HAZARD,
	INFUSION,
	
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
	CROWD_CONTROL
}

# Helper to turn an array of Enums into scannable bitwise flags if maximum performance is needed
static func get_tag_name(tag_type: Type) -> String:
	return Type.keys()[tag_type].to_lower()
