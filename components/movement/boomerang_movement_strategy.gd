class_name BoomerangMovementStrategy
extends MovementStrategy

enum BoomerangPhase { PHASE_OUTWARD, PHASE_RETURNING }

@export_group("Boomerang Physics Constants")
## The total rate of deceleration applied to the projectile during its outward flight path.
@export var deceleration_rate: float = 850.0
## The maximum acceleration rate used to reel the projectile back toward its caster target.
@export var return_acceleration: float = 1200.0
## The absolute time cutoff parameter in seconds when the projectile automatically forces a turn-around.
@export var maximum_outward_duration: float = 0.6

var _current_phase: BoomerangPhase = BoomerangPhase.PHASE_OUTWARD


func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	current_global_position: Vector2,
	time_elapsed: float,
	target_node: Node2D = null
) -> Vector2:
	
	var active_velocity := current_velocity if current_velocity != Vector2.ZERO else target_direction * max_speed
	var frame_delta := get_process_delta_time()

	match _current_phase:
		# --- PHASE 1: THE OUTWARD DECLINE ---
		BoomerangPhase.PHASE_OUTWARD:
			var forward_direction := active_velocity.normalized()
			var speed_reduction := deceleration_rate * frame_delta
			var next_speed := active_velocity.length() - speed_reduction
			
			if next_speed <= 5.0 or time_elapsed >= maximum_outward_duration:
				_current_phase = BoomerangPhase.PHASE_RETURNING
				return Vector2.ZERO
				
			return forward_direction * next_speed

		# --- PHASE 2: THE POLYMORPHIC CASTER RETURN ---
		BoomerangPhase.PHASE_RETURNING:
			var return_heading := target_direction
			
			# If the target node is valid, compute real-time vectors straight home to the caller
			if is_instance_valid(target_node):
				return_heading = (target_node.global_position - current_global_position).normalized()
				
			var approach_speed := active_velocity.length() + (return_acceleration * frame_delta)
			var clamped_speed := minf(approach_speed, max_speed * 1.5)
			
			return return_heading * clamped_speed
			
	return active_velocity
