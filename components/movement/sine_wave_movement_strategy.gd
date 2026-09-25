class_name SineWaveMovementStrategy
extends MovementStrategy

@export var wave_amplitude: float = 25.0
@export var wave_frequency: float = 16.0


func calculate_velocity(
	_current_velocity: Vector2,
	target_direction: Vector2,
	max_speed: float,
	_current_global_position: Vector2,
	time_elapsed: float,
	_target_node: Node2D = null
) -> Vector2:
	
	var forward_velocity := target_direction * max_speed
	var perpendicular_direction := target_direction.orthogonal()
	var cosine_wave := cos(time_elapsed * wave_frequency)
	var sideways_sway := perpendicular_direction * cosine_wave * wave_amplitude * wave_frequency
	
	return forward_velocity + sideways_sway
