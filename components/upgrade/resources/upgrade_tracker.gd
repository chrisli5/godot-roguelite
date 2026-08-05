class_name UpgradeTracker
extends Resource

@export var definition: UpgradeDefinition
@export var required_level: int = 1
@export var prerequisite_upgrade_ids: Array[String] = []
@export var max_purchases: int = 3
@export var current_purchases: int = 0
