class_name StatusEffect
extends Resource
## Design-time TEMPLATE for a status effect. Never mutated at runtime: per-application state
## lives in StatusEffectInstance. Magnitudes (DoT damage, duration bonus) come from the source's
## stats, never from this resource.

enum StackingPolicy { REFRESH, STACK }

@export_group("Identification")
@export var effect_id: String = ""

@export_group("Lifetime")
## Base seconds. The source's STATUS_DURATION stat is added on top at application time.
@export var base_duration: float = 3.0
@export var stacking: StackingPolicy = StackingPolicy.REFRESH
## Only used by STACK.
@export var max_stacks: int = 1

@export_group("Ticking")
## Seconds between ticks. 0 = this effect does not tick.
@export_range(0.0, 10.0, 0.05) var tick_interval: float = 0.0
## Tick damage grows by this fraction per second the effect has been active...
@export var ramp_bonus_per_second: float = 0.0
## ...up to this total bonus (0.5 = at most +50% tick damage).
@export var ramp_max_bonus: float = 0.0

@export_group("While Active")
## Applied to the afflicted entity's own stats while the effect lasts.
@export var stat_modifiers: Array[StatModifier] = []
## Temporary tags granted to the afflicted entity while the effect lasts.
@export var granted_tags: Array[Tags.Type] = []
