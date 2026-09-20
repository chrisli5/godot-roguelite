class_name BoomerangMovementStrategy
extends MovementStrategy

enum BoomerangPhase { PHASE_OUTWARD, PHASE_RETURNING }

@export_group("Boomerang Physics Constants")
## The total rate of deceleration applied to the projectile during its outward flight path
@export var deceleration_rate: float = 850.0
## The maximum acceleration rate used to reel the projectile back toward the character core
@export var return_acceleration: float = 1200.0
## The absolute time cutoff parameter in seconds when the projectile automatically forces a turn-around
@export var maximum_outward_duration: float = 0.6

# Local tracking registers managing phase step transitions in volatile RAM memory
var _current_phase: BoomerangPhase = BoomerangPhase.PHASE_OUTWARD
var _has_halted: bool = false


## Computes the composite trajectory vector purely through injected data arguments.
## Bypasses all scene tree lookups or object-casting dependencies completely.
func calculate_velocity(
	current_velocity: Vector2,
	target_direction: Vector2, # Dynamically provided vector context [pdf_5yV4_t.pdf]
	max_speed: float, 
	acceleration: float, 
	friction: float,
	time_elapsed: float
) -> Vector2:
	
	# Determine initial orientation vector defaults if current registers are flat
	var active_velocity := current_velocity if current_velocity != Vector2.ZERO else target_direction * max_speed
	var frame_delta := get_process_delta_time()

	match _current_phase:
		# --- PHASE 1: THE OUTWARD DECLINE ---
		BoomerangPhase.PHASE_OUTWARD:
			# Subtract linear velocity metrics along the active heading trajectory direction
			var forward_direction := active_velocity.normalized()
			var speed_reduction := deceleration_rate * frame_delta
			
			var next_speed := active_velocity.length() - speed_reduction
			
			# Safety Gate: If forward velocity zeroes out, or timeline thresholds expire, flip state
			if next_speed <= 5.0 or time_elapsed >= maximum_outward_duration:
				print("PHASE_RETURNING")
				_current_phase = BoomerangPhase.PHASE_RETURNING
				return Vector2.ZERO
				
			return forward_direction * next_speed

		# --- PHASE 2: THE CASTER TRACKING RETURN ---
		BoomerangPhase.PHASE_RETURNING:
			# target_direction behaves symmetrically as the real-time vector pointing 
			# straight from the projectile to the player character position coordinates [pdf_5yV4_t.pdf]
			var approach_speed := active_velocity.length() + (return_acceleration * frame_delta)
			var clamped_speed := minf(approach_speed, max_speed * 1.5) # Allow a small extra speed punch on return
			
			# Direct steering lock: Guide the velocity vector straight home [pdf_5yV4_t.pdf]
			return -(target_direction * clamped_speed)
			
	return active_velocity
