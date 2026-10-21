class_name TestBurstEffect
extends BurstEffect
## Test-only burst effect: records every instance and the payload copy it was configured with.

static var instances: Array[Node2D] = []
static var received: Array[CombatPayload] = []


func configure(source_payload: CombatPayload) -> void:
	received.append(source_payload)


func _ready() -> void:
	instances.append(self)
