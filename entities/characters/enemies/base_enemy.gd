extends CharacterBody2D

@export_group("Movement")
@export var base_speed: float = 600.0
@export var dash_speed: float = 1200.0
@export var dash_duration: float = 0.2
@export var dodge_speed: float = 800.0
@export var dodge_duration: float = 0.2
@export var dodge_cooldown: float = 0.5
@export var dodge_detection_range: float = 300.0
@export var repositioning_distance: float = 150.0
@export var blocked_time_limit: float = 2.0

@export_group("Combat")
@export var health: float = 60.0
@export var detection_radius: float = 150.0
@export var hit_stun_duration: float = 0.4
@export var attack_range: float = 120.0
@export var attack_cooldown: float = 0.6
@export var stun_duration: float = 0.2

# Enemy States
enum EnemyState {
	IDLE,
	CHASE,
	ATTACK,
	STUNNED
}
var current_state: int = EnemyState.IDLE

# Core
var initialized: bool = false
var human: Node2D = null
var sprite: Node2D = null
var original_color: Color = Color.WHITE
var trail: CPUParticles2D = null

# Obstacle Avoidance
var blocked_timer: float = 0.0
var obstacle_check_timer: float = 0.0
var feeler_angles: Array = []
var feelers: Array[RayCast2D] = []
var cached_obstacle_direction: Vector2 = Vector2.ZERO
var last_valid_position: Vector2 = Vector2.ZERO

# Movement
var is_chasing: bool = false

# Combat
var dodge_chance: float = 0.3
var is_stunned: bool = false
var stun_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_decay: float = 1500.0
var impact_scale: float = 1.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var can_damage: bool = true
var cooldown_timer: float = 0.0
var is_attacking: bool = false
var attack_target: Node2D = null
var can_attack: bool = true
var has_hit_target: bool = false
var last_hit_position: Vector2
var last_hit_time: int = 0

# Dodge State
var can_dodge: bool = true
var dodge_direction: Vector2 = Vector2.ZERO
var dodge_timer: float = 0.0
var is_dodging: bool = false
var dodge_success_count: int = 0

# Positioning State
var seeking_position: bool = false
var target_position: Vector2 = Vector2.ZERO

# Visual Effects
var sweat_particles: CPUParticles2D
var rage_particles: CPUParticles2D

### Core Functions ###
func _ready() -> void:
	# Initialize core components
	sprite = $Sprite2D
	if sprite:
		original_color = sprite.modulate
	
	# Trail effect is optional
	trail = get_node_or_null("CPUParticles2D")
	
	setup_obstacle_avoidance()
	initialize_references()
	initialized = true

func initialize_references() -> void:
	if !initialized:
		human = get_tree().root.get_node_or_null("Main/Player")
	
	reset_state()

func reset_state() -> void:
	# Reset all state variables to default values
	is_dashing = false
	is_stunned = false
	can_damage = true
	dash_timer = 0.0
	cooldown_timer = 0.0
	stun_timer = 0.0
	can_dodge = true
	dodge_direction = Vector2.ZERO
	dodge_timer = 0.0
	is_dodging = false
	blocked_timer = 0.0
	seeking_position = false
	target_position = Vector2.ZERO
	velocity = Vector2.ZERO
	if sprite:
		sprite.modulate = original_color

func setup_obstacle_avoidance() -> void:
	# Create raycasts in a circle for obstacle detection
	feeler_angles = [-60, -30, 0, 30, 60]  # Angles for obstacle detection
	
	for angle in feeler_angles:
		var ray = RayCast2D.new()
		ray.target_position = Vector2.RIGHT.rotated(deg_to_rad(angle)) * 100
		ray.collision_mask = 1  # Collide with world
		ray.enabled = true
		add_child(ray)
		feelers.append(ray)
	
	last_valid_position = global_position

func setup_attack_area() -> void:
	var attack_area = $AttackArea
	if attack_area:
		attack_area.collision_mask = 4  # Set appropriate collision mask
		attack_area.call_deferred("set_monitorable", true)
		attack_area.call_deferred("set_monitoring", true)
		
		if not attack_area.area_entered.is_connected(_on_attack_area_area_entered):
			attack_area.area_entered.connect(_on_attack_area_area_entered)

### State Management ###
func update_timers(delta: float) -> void:
	cooldown_timer = max(0, cooldown_timer - delta)
	dodge_timer = max(0, dodge_timer - delta)
	obstacle_check_timer = max(0.0, obstacle_check_timer - delta)

func handle_stunned_state(delta: float) -> void:
	if stun_timer <= 0:
		reset_state()
	else:
		stun_timer -= delta
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * knockback_decay)
		if sprite:
			sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red tint

func handle_dash(delta: float) -> void:
	if !trail.emitting:
		trail.emitting = true
	
	dash_timer -= delta
	
	if dash_timer <= 0:
		# Successful dodge if we didn't get hit during the dash
		if is_dodging:
			dodge_success_count += 1
		end_dash()
		return
	elif get_slide_collision_count() > 0:
		end_dash()
		return
		
	# Maintain the dash velocity
	velocity = dodge_direction * (dodge_speed * (1.0 + (dodge_success_count * 0.1)))

func end_dash() -> void:
	is_dashing = false
	is_dodging = false
	dodge_direction = Vector2.ZERO
	velocity = Vector2.ZERO
	trail.emitting = false

### Movement and Combat ###
# Virtual function for child classes to override
func handle_movement(delta: float) -> Vector2:
	return Vector2.ZERO  # Base implementation returns no movement

func get_target() -> Node2D:
	if !is_instance_valid(human):
		initialize_references()  # Try to get fresh references
		if !human:
			return null
			
	return human  # Always target human for consistency

func _on_hit(is_overheated: bool = false) -> void:
	if !can_damage:
		return
	
	Audio.play_sfx("enemy_hurt")
	
	# Apply proper damage based on overheated state
	var damage = 20.0 if is_overheated else 10.0
	health -= damage
	
	flash_hit()
	apply_hit_stun()
	
	# Reset adaptation on hit
	last_hit_time = 0.0
	dodge_success_count = max(0, dodge_success_count - 1)  # Lose dodge experience
	
	if health <= 0:
		die()

func flash_hit() -> void:
	if !sprite:
		return
		
	# Flash red
	sprite.modulate = Color(1, 0, 0, 1)
	
	# Reset color after a short delay
	var timer = get_tree().create_timer(0.1)
	timer.timeout.connect(func(): 
		if sprite and is_instance_valid(sprite):
			sprite.modulate = original_color
	)

func apply_hit_stun() -> void:
	is_stunned = true
	stun_timer = hit_stun_duration
	velocity = Vector2.ZERO
	# Reset all movement states
	is_dashing = false
	is_dodging = false
	cooldown_timer = 0.0
	dash_timer = 0.0
	dodge_timer = 0.0

func take_knockback(knockback_force: Vector2) -> void:
	knockback_velocity = knockback_force * 1.2 
	velocity = knockback_velocity
	impact_scale = 0.7
	apply_hit_stun()

func take_damage(amount: float) -> void:
	if !can_damage:
		return
		
	Audio.play_sfx("enemy_hurt")
	
	health -= amount
	flash_hit()
	apply_hit_stun() 
	
	# Reset adaptation like in _on_hit
	last_hit_time = 0.0
	dodge_success_count = max(0, dodge_success_count - 1)
	
	if health <= 0:
		die()

### Death and Effects ###
func die() -> void:
	Audio.play_sfx("enemy_death")
	
	# Visual effects
	if sprite:
		sprite.modulate = Color(1, 0.3, 0.3)  # Red flash
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0), 0.3)
	
	# Stop all particles
	if sweat_particles:
		sweat_particles.emitting = false
	if rage_particles:
		rage_particles.emitting = false
	if trail:
		trail.emitting = false
	
	# Safely disable collision shapes
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.call_deferred("set_disabled", true)
		elif child is Area2D:
			child.call_deferred("set_monitoring", false)
			child.call_deferred("set_monitorable", false)
	
	# Create simple death particles
	var death_particles = CPUParticles2D.new()
	death_particles.emitting = false
	death_particles.amount = 16
	death_particles.lifetime = 0.5
	death_particles.explosiveness = 0.8
	death_particles.spread = 180.0
	death_particles.gravity = Vector2.ZERO
	death_particles.initial_velocity_min = 100.0
	death_particles.initial_velocity_max = 150.0
	death_particles.scale_amount_min = 4.0
	death_particles.scale_amount_max = 6.0
	death_particles.color = Color(1.0, 0.3, 0.3, 0.8)
	add_child(death_particles)
	death_particles.emitting = true
	
	# Remove enemy after particles finish
	await get_tree().create_timer(0.5).timeout
	queue_free()

### Dodging and Repositioning ###
func check_obstacles(desired_velocity: Vector2) -> Vector2:
	if obstacle_check_timer <= 0:
		cached_obstacle_direction = Vector2.ZERO
		var total_weight = 0.0
		
		for i in range(feelers.size()):
			var feeler = feelers[i]
			if feeler.is_colliding():
				var collision_point = feeler.get_collision_point()
				var to_obstacle = collision_point - global_position
				var distance = to_obstacle.length()
				var weight = 1.0 - (distance / 100.0) 
				cached_obstacle_direction += -to_obstacle.normalized() * weight
				total_weight += weight
		
		if total_weight > 0:
			cached_obstacle_direction /= total_weight
			blocked_timer += 0.1
		else:
			blocked_timer = max(0, blocked_timer - 0.1)
		
		#obstacle_check_timer = obstacle_check_interval
	
	if cached_obstacle_direction != Vector2.ZERO:
		# Blend between desired velocity and obstacle avoidance
		var blend_factor = min(blocked_timer, 1.0)
		return desired_velocity.lerp(cached_obstacle_direction * desired_velocity.length(), blend_factor)
	
	return desired_velocity

func move_and_avoid(desired_velocity: Vector2, delta: float) -> void:
	var final_velocity = check_obstacles(desired_velocity)
	velocity = velocity.move_toward(final_velocity, base_speed * delta)
	move_and_slide()
	
	# Update position tracking
	if !get_slide_collision_count():
		last_valid_position = global_position

func _physics_process(delta: float) -> void:
	if !initialized or !human:
		initialize_references()
		return

	if is_stunned:
		handle_stunned_state(delta)
		return

	# Update timers and state
	update_timers(delta)
	
	# Handle movement and combat based on state
	match current_state:
		EnemyState.IDLE:
			handle_idle_state(delta)
		EnemyState.CHASE:
			handle_chase_state(delta)
		EnemyState.ATTACK:
			handle_attack_state(delta)
		EnemyState.STUNNED:
			handle_stunned_state(delta)
	
	# Update visual effects
	if impact_scale != 1.0:
		impact_scale = move_toward(impact_scale, 1.0, delta * 5.0)
		scale = Vector2.ONE * impact_scale
	
	if sprite and abs(velocity.x) > 0:
		sprite.flip_h = velocity.x < 0
	
	move_and_avoid(velocity, delta)

func handle_idle_state(_delta: float) -> void:
	velocity = Vector2.ZERO
	if human and is_instance_valid(human):
		current_state = EnemyState.CHASE

func handle_chase_state(_delta: float) -> void:
	# Virtual function to be implemented by child classes
	pass

func handle_attack_state(_delta: float) -> void:
	# Virtual function to be implemented by child classes
	pass

func _on_timeout_can_attack() -> void:
	can_attack = true

func _on_timeout_reset_dodge() -> void:
	can_dodge = true

func _on_timeout_reset_stun() -> void:
	is_stunned = false
	if sprite:
		sprite.modulate = original_color

func _on_timeout_reset_attack() -> void:
	is_attacking = false
	can_attack = false
	attack_target = null
	if sprite:
		sprite.modulate = original_color
	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(_on_timeout_can_attack)

# Virtual function for child classes to override
func _on_attack_area_area_entered(_area: Area2D) -> void:
	pass  # Implement in child classes
