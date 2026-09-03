class_name HitPayload
extends Resource

@export_group("Static Asset Tracking")
## The definition asset that created this hit (Safe to export because it's a Resource)
@export var source_definition: UpgradeDefinition

@export_group("Static Combat Math")
## Raw damage calculation value configured in files
@export var base_damage: float = 0.0
## Active elemental/lifecycle tags bundled with this specific strike (e.g., FIRE, DOT)
@export var damage_tags: Array[Tags.Type] = []

@export_group("Static Status Integration")
## Status effects that this hit applies to the target on impact
@export var status_effects_to_apply: Array[StatusEffect] = []

var caster: Node2D

## The final computed damage after applying critical hits, global card buffs, 
## or character strength multipliers in RAM.
var final_damage: float = 0.0
