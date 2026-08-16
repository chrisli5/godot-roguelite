class_name UpgradeTracker
extends Resource

@export var definition: UpgradeDefinition

@export_group("Gating Constraints")
@export var required_character_level: int = 1
## The minimum level of component infusions required to trigger an evolution recipe.
@export var required_infusion_level: int = 1

@export_group("Numerical Tier Sequencing")
## The specific tier index of this card instance (e.g., 1 for Tier I, 2 for Tier II)
@export var tier_index: int = 1
## The minimum tier index required from this same base upgrade family before unlocking
@export var prerequisite_tier: int = 0

@export_group("Purchase Limits")
@export var max_purchases: int = 3
@export var current_purchases: int = 0
