class_name CastEvents
extends Resource
## Per-cast shared state and signals, carried by reference by every copy of the cast's CombatPayload.
## A Resource for the same reason as CastBudget: Resource.duplicate copies exported properties only and keeps
## a sub-resource shared, which is what makes the per-cast refund cap hold across hits.

## Emitted by HurtboxComponent.take_hit when a critting hit is granted a cooldown refund. The Ability listens.
signal cooldown_refunded(seconds: float)

## Total cooldown seconds refunded so far by this cast.
var refunded: float = 0.0
