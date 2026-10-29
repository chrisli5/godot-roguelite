class_name StatusEffect
extends Resource
## Design-time TEMPLATE for a status effect. Never mutated at runtime: per-application state
## lives in StatusEffectInstance. Magnitudes (DoT damage, duration bonus) come from the source's
## stats, never from this resource.

@export_group("Identification")
@export var effect_id: String = ""

@export_group("Lifetime")
## Base seconds. The source's STATUS_DURATION stat is added on top at application time.
@export var base_duration: float = 3.0

@export_group("Ticking")
## Seconds between ticks. 0 = this effect does not tick.
@export_range(0.0, 10.0, 0.05) var tick_interval: float = 0.0
## Tick damage grows by this fraction per second the effect has been active...
@export var ramp_bonus_per_second: float = 0.0
## ...up to this total bonus (0.5 = at most +50% tick damage).
@export var ramp_max_bonus: float = 0.0

@export_group("Magnitude")
## True = this status's stat_modifiers values are scaled by the source's STATUS_MAGNITUDE_BONUS (value * (1 + bonus)).
@export var magnitude_scales: bool = false
## Cap on the magnitude bonus applied to this status (0.5 = at most +50%). Placeholder.
@export var max_magnitude_bonus: float = 0.5

@export_group("Buildup")
## Meter added by each application. 0 = this status has no meter (and no Frozen phase).
@export var buildup_per_application: float = 0.0
## Meter value that starts the Frozen phase.
@export var buildup_threshold: float = 1.0
## Meter lost per second while not Frozen.
@export var buildup_drain_per_second: float = 0.0
## Seconds the Frozen phase lasts.
@export var freeze_duration: float = 1.0
## Seconds after the Frozen phase during which the meter cannot build.
@export var freeze_immunity: float = 3.0
## The value every runtime modifier takes while Frozen (-1.0 on a percent speed modifier = full stop).
@export var frozen_modifier_value: float = -1.0
## Temporary tags granted to the afflicted entity while Frozen (in addition to granted_tags).
@export var frozen_granted_tags: Array[Tags.Type] = []

@export_group("While Active")
## Applied to the afflicted entity's own stats while the effect lasts.
@export var stat_modifiers: Array[StatModifier] = []
## Temporary tags granted to the afflicted entity while the effect lasts.
@export var granted_tags: Array[Tags.Type] = []
