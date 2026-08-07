class_name Player
extends Entity

@export_group("Components")
@export var progression_component: ProgressionComponent
@export var collector_component: CollectorComponent
@export var upgrade_tree_component: UpgradeTreeComponent


func _ready() -> void:
	super()
	var components_valid: bool = true
	
	if not progression_component:
		push_error("Entity '%s' is missing a ProgressionComponent!" % name)
		components_valid = false
	if not collector_component:
		push_error("Entity '%s' is missing a CollectorComponent!" % name)
		components_valid = false
	if not upgrade_tree_component:
		push_error("Entity '%s' is missing a UpgradeTreeComponent!" % name)
		components_valid = false	

	if not components_valid:
		return
	
	collector_component.payload_collected.connect(_on_payload_collected)


func _enter_tree() -> void:
	EventBus.active_player = self


func _exit_tree() -> void:
	if EventBus.active_player == self:
		EventBus.active_player = null


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _handle_movement_physics() -> void:
	if not movement_component:
		return
	
	var max_speed: float = 10.0
	var acceleration: float = 1.0
	var friction: float = 1.0
	
	if stats_container:
		max_speed = stats_container.get_stat_value(Stat.Type.SPEED, max_speed)
		acceleration = stats_container.get_stat_value(Stat.Type.ACCELERATION, acceleration)
		friction = stats_container.get_stat_value(Stat.Type.FRICTION, friction)
		
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized()
	
	velocity = movement_component.calculate_velocity(velocity, target_velocity, max_speed, acceleration, friction)
	move_and_slide()


func _on_payload_collected(payload: PickupPayload) -> void:
	match payload.type:
		"experience":
			if is_instance_valid(progression_component):
				progression_component.gain_experience(payload.value)
