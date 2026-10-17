class_name UpgradeBlueprintProfile
extends Resource

@export_group("Blueprint Configuration Bundle")
## The list of upgrade definitions managed by this profile tracker family.
## For single-line progression lines (like Movement Speed), simply add one definition template here.
@export var definition_bundle: Array[UpgradeDefinition] = []

@export_group("Gating & Ceiling Metrics")
## The total purchase ceiling allowed for each card family in this bundle.
## Set this to 1 for unique items like first-time skill unlocks or evolutions.
@export var total_tiers: int = 5
@export var initial_unlock_level: int = 1
@export var levels_per_tier: int = 1
