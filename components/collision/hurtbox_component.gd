# res://components/collision/hurtbox_component.gd
class_name HurtboxComponent
extends Area2D

signal hit_received(payload: CombatPayload)

var owner_entity: Entity = null
var is_player_hurtbox: bool:
	get:
		return owner_entity is Player


func take_hit(payload: CombatPayload) -> void:
	if not is_instance_valid(payload):
		return

	hit_received.emit(payload)
	# A burst's own payload (is_burst) never starts another burst.
	if payload.impact_bursts.is_empty() or payload.is_burst:
		return
	_queue_impact_bursts(payload)


## Captures where this hit landed and queues the payload's qualifying bursts for one frame later.
## take_hit can run inside a physics callback, where spatial queries may not be allowed, so the burst
## runs deferred. Only the position and instance id are kept; the enemy itself is never referenced.
func _queue_impact_bursts(payload: CombatPayload) -> void:
	var origin := global_position
	var own_instance_id := get_instance_id()
	var world := get_world_2d()
	for definition in payload.impact_bursts:
		if definition == null:
			continue
		if definition.trigger == ImpactBurstDefinition.Trigger.ON_CRIT and not payload.is_critical_hit:
			continue
		ImpactBurst.run.call_deferred(definition, payload, origin, own_instance_id, world)
