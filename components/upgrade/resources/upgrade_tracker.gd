class_name UpgradeTracker
extends Resource

@export var definition: UpgradeDefinition

@export_group("Gating Constraints")
## The absolute minimum character level required to draft the FIRST tier of this card.
@export var required_character_level: int = 1
## The minimum level of component infusions required to trigger an evolution recipe.
@export var required_infusion_level: int = 1

@export_group("Purchase Tracking & Limits")
## The absolute purchase ceiling allowed for this card family (e.g., 5 tiers).
@export var max_purchases: int = 5
## The live running integer tally of how many times this card has been chosen.
@export var current_purchases: int = 0

## The active display tier numeral compiled on the fly for UI presentation cards (e.g., 2 for Tier II).
var tier_index: int = 1:
	get:
		return current_purchases + 1


## Utility helper check ensuring standard state boundary parameters are verified safely.
func has_remaining_tiers() -> bool:
	return current_purchases < max_purchases
