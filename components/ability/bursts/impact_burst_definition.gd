class_name ImpactBurstDefinition
extends Resource
## Design-time template for an impact burst: secondary area damage centered on a hit enemy.
## It may carry the cast's statuses (applies_statuses), require a tag on the primary target, or have no
## shape at all (an effect-only burst that just spawns its effect scene).
## Carried by an UpgradeDefinition and chosen at cast time, like a status effect.

## Append-only: stored as an integer in .tres files.
enum Trigger { ON_HIT, ON_CRIT }

## Used to deduplicate bursts the way effect_id deduplicates statuses.
@export var burst_id: StringName = &""
@export var trigger: Trigger = Trigger.ON_HIT
## If not NONE, the burst fires only when the primary target carries this tag at the moment of the hit, before the hit's own statuses apply.
@export var required_target_tag: Tags.Type = Tags.Type.NONE
## Null makes an effect-only burst: it spawns its effect scene at the hit origin and does nothing else.
@export var shape: BurstShape
## Share of the hit's final damage dealt to each enemy the burst catches.
@export var damage_fraction: float = 0.5
## Extra damage multiplier per enemy caught, capped by per_enemy_bonus_cap.
@export var per_enemy_bonus: float = 0.0
@export var per_enemy_bonus_cap: float = 0.0
## Keep the cast's statuses and their snapshots on the burst's hits. Off by default: a burst applies no status.
@export var applies_statuses: bool = false
## Optional visual spawned at the burst origin.
@export var effect_scene: PackedScene
