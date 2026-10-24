class_name IndirectEffectDefinition
extends Resource
## The level-gated indirect effect of an infusion card. Direct effects (stat modifiers, statuses) are never gated;
## an indirect effect is active for a slot only while the card's level in that slot is at least `unlock_level`.
## Kinds that convert a direct stat into a cast-time damage scale are computed by IndirectScaling.

## Append-only: stored as integers in .tres files.
enum Kind { NONE, COOLDOWN_DAMAGE, SPEED_DAMAGE }

@export var kind: Kind = Kind.NONE
## Card level (in the slot) from which this effect is active.
@export var unlock_level: int = 2

@export_group("Cooldown damage (Frost)")
## Seconds shaved off the default cooldown that earn one `per_step` of bonus.
@export var step_seconds: float = 0.1
## Damage bonus per `step_seconds` shaved.
@export var per_step: float = 0.04
## The effective cooldown never counts as lower than this (this calculation only; the real cooldown is untouched).
@export var cooldown_floor: float = 0.25

@export_group("Speed damage (Wind)")
## Damage bonus per point of SPEED_BONUS.
@export var speed_ratio: float = 0.5
