class_name ImpactBurstDefinition
extends Resource
## Design-time template for an impact burst: secondary area damage centered on a hit enemy.
## Carried by an UpgradeDefinition and chosen at cast time, like a status effect.

## Append-only: stored as an integer in .tres files.
enum Trigger { ON_HIT, ON_CRIT }

## Used to deduplicate bursts the way effect_id deduplicates statuses.
@export var burst_id: StringName = &""
@export var trigger: Trigger = Trigger.ON_HIT
@export var shape: BurstShape
## Share of the hit's final damage dealt to each enemy the burst catches.
@export var damage_fraction: float = 0.5
## Extra damage multiplier per enemy caught, capped by per_enemy_bonus_cap.
@export var per_enemy_bonus: float = 0.0
@export var per_enemy_bonus_cap: float = 0.0
## Optional visual spawned at the burst origin.
@export var effect_scene: PackedScene
