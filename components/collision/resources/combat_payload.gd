class_name CombatPayload
extends Resource


@export_group("Static Combat Math")
## Active elemental/lifecycle tags bundled with this specific strike (e.g., FIRE, DOT)
@export var final_damage: float = 0.0
@export var damage_tags: Array[Tags.Type] = []
## True when THIS hit's crit roll succeeded. The roll happens per hit in HurtboxComponent.take_hit, so the
## shared cast payload always has false and only the resolved copy a critting hit uses has true.
@export var is_critical_hit: bool = false
## Cast-time snapshots of CRIT_CHANCE, CRIT_MULTIPLIER and CRIT_DOT_SHARE, read when each hit rolls its crit.
@export var crit_chance_snapshot: float = 0.0
@export var crit_multiplier_snapshot: float = 0.0
@export var crit_dot_share_snapshot: float = 0.0
## Indirect damage scale applied once to this cast's hit damage and DoT snapshot (1.0 = none). Copies keep it
## and never apply it again.
@export var damage_scale: float = 1.0

@export_group("Static Status Integration")
## Status effects that this hit applies to the target on impact
@export var status_effects_to_apply: Array[StatusEffect] = []
## Source DOT_DAMAGE (damage per second) snapshotted when the hit was generated.
@export var dot_damage_snapshot: float = 0.0
## Source STATUS_DURATION (seconds added to an effect's base duration), snapshotted likewise.
@export var status_duration_snapshot: float = 0.0
## Source STATUS_RAMP_CAP (added to a ramping status's cap), snapshotted likewise.
@export var status_ramp_cap_snapshot: float = 0.0
## Source STATUS_MAGNITUDE_BONUS (scales magnitude-scaling statuses such as Chill), snapshotted likewise.
@export var status_magnitude_snapshot: float = 0.0

@export_group("Impact Bursts")
## Bursts chosen at cast time; each fires on a qualifying hit (see ImpactBurstDefinition.Trigger).
@export var impact_bursts: Array[ImpactBurstDefinition] = []
## True on the payload a burst delivers to its targets. Such a payload never starts another burst.
@export var is_burst: bool = false
## Identifies the cast that made this payload (0 = none). Copies of the payload keep it.
@export var cast_id: int = 0
## Per-cast spend counters, shared (never copied) by every duplicate of this payload. Null means unlimited.
@export var cast_budget: CastBudget = null

@export_group("Dynamic Strategy Core Targets")
## Injected by the spawning Ability: Points to the live Enemy Node2D locked by the hotbar strategy
@export var caster_instance_id: int = 0
@export var stats_container_id: int = 0

@export_group("Trajectory Strategy Overrides")
## Injected by the spawner card: the specific physics component used to steer this projectile
@export var trajectory_movement_scene: PackedScene
@export var base_texture: Texture2D
