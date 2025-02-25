extends "res://entities/enemies/base_enemy.gd"

@export var attack_windup_time: float = 0.2
@export var attack_lunge_speed: float = 1500.0
@export var attack_lunge_duration: float = 0.15
@export var knockback_force: float = 800.0
@export var melee_damage: int = 15

# Melee specific variables
var melee_attack_direction: Vector2 = Vector2.ZERO
var melee_attack_timer: float = 0.0
var melee_lunge_timer: float = 0.0
var is_in_attack_lunge: bool = false

func _ready() -> void:
	max_health = 80
	health = max_health
	super._ready()
	$AttackArea.collision_mask = 4
	setup_attack_area()

func handle_chase_state(delta: float) -> void:
	if !human or !is_instance_valid(human):
		current_state = EnemyState.IDLE
		return
		
	var direction = (human.global_position - global_position).normalized()
	var target_velocity = direction * base_speed
	velocity = velocity.move_toward(target_velocity, base_speed * 4 * delta)
	
	if human and is_instance_valid(human):
		var distance = global_position.distance_to(human.global_position)
		if distance <= attack_range and can_attack:
			attack_target = human
			current_state = EnemyState.ATTACK

func handle_attack_state(delta: float) -> void:
	if !attack_target or !is_instance_valid(attack_target):
		reset_attack_state()
		return
		
	if !is_attacking:
		if can_attack:
			start_attack()
		else:
			reset_attack_state()
		return
		
	if melee_attack_timer > 0:
		melee_attack_timer -= delta
		melee_attack_direction = (attack_target.global_position - global_position).normalized()
		velocity = velocity.move_toward(Vector2.ZERO, base_speed * 2 * delta)
		
	elif is_in_attack_lunge:
		melee_lunge_timer -= delta
		velocity = melee_attack_direction * attack_lunge_speed
		
		if !has_hit_target:
			check_for_hit()
		
		if melee_lunge_timer <= 0 or has_hit_target:
			reset_attack_state()
	else:
		is_in_attack_lunge = true
		melee_lunge_timer = attack_lunge_duration
		velocity = melee_attack_direction * attack_lunge_speed
		check_for_hit()

func check_for_hit() -> void:
	var attack_area = $AttackArea
	if !attack_area:
		return
		
	var overlapping = attack_area.get_overlapping_areas()
	
	for area in overlapping:
		if area.get_parent() == attack_target and area.name == "HitBox":
			register_hit()
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(melee_damage)
			if attack_target.has_method("apply_knockback"):
				attack_target.apply_knockback(melee_attack_direction * knockback_force)
			return

func start_attack() -> void:
	is_attacking = true
	is_in_attack_lunge = false
	has_hit_target = false
	melee_attack_timer = attack_windup_time
	melee_lunge_timer = 0.0
	last_hit_position = attack_target.global_position
	last_hit_time = Time.get_ticks_msec()
	can_attack = false
	
	if sprite:
		sprite.modulate = Color(1.5, 1.0, 1.0)

func reset_attack_state() -> void:
	is_attacking = false
	is_in_attack_lunge = false
	has_hit_target = false
	melee_attack_timer = 0.0
	melee_lunge_timer = 0.0
	current_state = EnemyState.CHASE
	if sprite:
		sprite.modulate = original_color
	
	var timer = get_tree().create_timer(attack_cooldown)
	timer.timeout.connect(func(): can_attack = true)

func register_hit() -> void:
	has_hit_target = true

func is_in_lunge_state() -> bool:
	return current_state == EnemyState.ATTACK and is_in_attack_lunge

func _on_attack_area_area_entered(area: Area2D) -> void:
	if is_in_attack_lunge and !has_hit_target:
		if area.get_parent() == attack_target and area.name == "HitBox":
			register_hit()
			if attack_target.has_method("take_damage"):
				attack_target.take_damage(melee_damage)
			if attack_target.has_method("apply_knockback"):
				attack_target.apply_knockback(melee_attack_direction * knockback_force)

func take_damage(amount: float) -> void:
	super.take_damage(amount)
	hits_taken += 1
	maybe_change_personality()
	
	current_state = EnemyState.STUNNED
	stun_timer = stun_duration
	
	var knockback_direction = -velocity.normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = Vector2.RIGHT.rotated(randf() * TAU)
	knockback_velocity = knockback_direction * 500
	
	if sprite:
		sprite.modulate = Color(1.0, 0.5, 0.5)

func _on_hit(is_overheated: bool = false) -> void:
	super._on_hit(is_overheated)
	
	# Reset attack state when hit
	if is_attacking or is_in_attack_lunge:
		reset_attack_state()

func _physics_process(delta: float) -> void:
	# Handle knockback first if it exists
	if knockback_velocity.length() > 0:
		velocity = knockback_velocity * 1.2  
		# Check for wall impacts during knockback
		if monitoring_wall_impact and get_slide_collision_count() > 0:
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				if collision and velocity.length() >= wall_impact_speed_threshold:
					take_damage(wall_impact_damage_amount)
					monitoring_wall_impact = false
					break
		# Gradually reduce knockback
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
		# Scale effect during impact
		var impact_amount = min(knockback_velocity.length() / 1200.0, 1.0)
		scale = Vector2.ONE * (1.0 + impact_amount * 0.2)
	else:
		scale = Vector2.ONE  # Reset scale when not in knockback
		# Normal state machine processing
		match current_state:
			EnemyState.IDLE:
				velocity = Vector2.ZERO
				if human and is_instance_valid(human):
					current_state = EnemyState.CHASE
			
			EnemyState.CHASE:
				handle_chase_state(delta)
			
			EnemyState.ATTACK:
				handle_attack_state(delta)
			
			EnemyState.STUNNED:
				handle_stunned_state(delta)
				if !is_stunned:  # If stun ended, return to chase
					current_state = EnemyState.CHASE
		
		if sprite and abs(velocity.x) > 0:
			sprite.flip_h = velocity.x < 0
	
	move_and_slide()

func handle_stunned_state(delta: float) -> void:
	if stun_timer <= 0:
		current_state = EnemyState.CHASE
		if sprite:
			sprite.modulate = original_color
	else:
		stun_timer -= delta
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, delta * 1500)

func take_knockback(knockback: Vector2) -> void:
	# Reduce knockback force significantly for melee enemies since they're bigger/tougher
	knockback_velocity = knockback * 0.3 
	
	# Apply a stun effect
	current_state = EnemyState.STUNNED
	is_stunned = true
	stun_timer = 1.0  # 1 second stun duration
	if sprite:
		sprite.modulate = Color(1.5, 1.5, 1.5)  # Flash white to indicate stun

func initialize_personality() -> void:
	var roll = randf()
	if roll < 0.55: 
		set_personality("aggressive")
	elif roll < 0.60: 
		set_personality("cautious")
	else: 
		set_personality("neutral")

func maybe_change_personality() -> void:
	# Calculate chance based on hits taken
	var change_chance = min(PERSONALITY_CHANGE_BASE_CHANCE + (hits_taken * 0.05), MAX_PERSONALITY_CHANGE_CHANCE)
	
	if randf() < change_chance:
		var roll = randf()
		if roll < 0.7: 
			set_personality("aggressive")
		elif roll < 0.8: 
			set_personality("cautious")
		else: 
			set_personality("neutral")
