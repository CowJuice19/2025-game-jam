extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var ui_manager: UIManager

var tutorial_popup: Control = null
var is_popup_active = false
var current_tutorial_step = 0
var next_tutorial_timer: Timer = null
var movement_completed = false
var has_sprinted = false
var has_dashed = false


var is_tutorial_transitioning = false

enum TutorialStep {
	MOVEMENT,
	DASH_SPRINT,
	STAMINA_WARNING,
	COMPLETED
}

func _ready() -> void:
	if not _validate_scene_setup():
		push_error("Critical scene components missing. Tutorial cannot proceed.")
		return

	Audio.play_music("tutorial_theme")
	print("music playing")
	get_tree().paused = false
	
	setup_ui_manager()
	await get_tree().process_frame
	
	initialize_enemies()
	connect_signals()
	setup_movement_tutorial()

func _validate_scene_setup() -> bool:
	if not has_node("Player"):
		push_error("Player not found in scene")
		return false
	if not has_node("HUDCamera/HUD"):
		push_error("HUD not found in scene")
		return false
	if not has_node("Enemies"):
		push_error("Enemies node not found in scene")
		return false
	return true

func initialize_enemies() -> void:
	for enemy in $Enemies.get_children():
		if enemy.has_method("initialize_references"):
			if not is_instance_valid(player):
				push_error("Player references invalid during enemy initialization")
				continue
			enemy.player = player
			enemy.initialized = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): 
		# Don't allow pausing if game over menu is visible
		if is_instance_valid(ui_manager.game_over_menu_instance) and ui_manager.game_over_menu_instance.visible:
			return
			
		ui_manager.handle_pause_input(event)

func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_WINDOW_FOCUS_OUT 
		and (!is_instance_valid(ui_manager.game_over_menu_instance) or !ui_manager.game_over_menu_instance.visible)):
		ui_manager.show_pause_menu()

func setup_ui_manager() -> void:
	ui_manager = UIManager.new()
	add_child(ui_manager)
	if has_node("HUDCamera/HUD"):
		ui_manager.initialize_UI($HUDCamera/HUD)
	else:
		push_error("Missing HUD node in stage scene")
		print("Error: Missing HUD node in tutorial stage")

func connect_signals() -> void:
	if not _validate_signal_requirements():
		return

	player.health_changed.connect(func(new_health, max_health): 
		if is_instance_valid(ui_manager):
			ui_manager.update_player_health(new_health, max_health))
	player.player_died.connect(on_player_death)

func _validate_signal_requirements() -> bool:
	if not is_instance_valid(player):
		push_error("Player not valid for signal connection")
		return false
	if not is_instance_valid(ui_manager):
		push_error("UI Manager not valid for signal connection")
		return false
	return true

func on_player_death() -> void:
	if is_instance_valid(ui_manager):
		ui_manager.show_game_over_menu()
	get_tree().paused = true

func setup_movement_tutorial() -> void:
	if is_popup_active:
		return
	
	show_tutorial_popup("Use WASD to move", true)
	if player:
		player.connect("velocity_changed", _on_player_moved)

func setup_dashing_sprinting_tutorial() -> void:
	if is_popup_active:
		return
	
	has_sprinted = false
	has_dashed = false
	
	if player:
		# Ensure we're not double-connecting signals
		if player.sprint.is_connected(_on_player_sprinted):
			player.sprint.disconnect(_on_player_sprinted)
		if player.dash.is_connected(_on_player_dashed):
			player.dash.disconnect(_on_player_dashed)
		if player.is_connected("velocity_changed", _on_player_moved_sprint):
			player.disconnect("velocity_changed", _on_player_moved_sprint)
			
		player.sprint.connect(_on_player_sprinted)
		player.dash.connect(_on_player_dashed)
		player.connect("velocity_changed", _on_player_moved_sprint)
	
	show_tutorial_popup("Press SHIFT to sprint and SPACE to dash", false)

func _on_player_moved_sprint(velocity: Vector2) -> void:
	if player and Input.is_action_pressed("sprint") and velocity.length() > 0:
		_on_player_sprinted()

func _on_player_sprinted() -> void:
	if not has_sprinted and current_tutorial_step == TutorialStep.DASH_SPRINT:
		has_sprinted = true
		check_sprint_dash_completion()

func _on_player_dashed() -> void:
	if not has_dashed and current_tutorial_step == TutorialStep.DASH_SPRINT:
		has_dashed = true
		check_sprint_dash_completion()

func check_sprint_dash_completion() -> void:
	if (has_sprinted or has_dashed) and is_instance_valid(tutorial_popup):
		# If either action is completed, disconnect its signal to prevent re-triggering
		if has_sprinted and player.sprint.is_connected(_on_player_sprinted):
			player.sprint.disconnect(_on_player_sprinted)
		if has_dashed and player.dash.is_connected(_on_player_dashed):
			player.dash.disconnect(_on_player_dashed)
		
		# If both actions are completed, finish the tutorial
		if has_sprinted and has_dashed:
			if player.is_connected("velocity_changed", _on_player_moved_sprint):
				player.disconnect("velocity_changed", _on_player_moved_sprint)
			tutorial_popup.tutorial_completed.emit()
			tutorial_popup.fade_out()

func complete_tutorial() -> void:
	if is_popup_active:
		return
	show_tutorial_popup("Tutorial completed!")
	# After showing completion message, wait 3 seconds then go to controls menu
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://ui/menus/main_menu/controls_menu/controls_menu.tscn")
	Audio.play_music("main_menu_theme")

func _on_tutorial_completed() -> void:
	if is_tutorial_transitioning:
		return
	
	# Check if we're in movement tutorial and it's not completed
	if current_tutorial_step == TutorialStep.MOVEMENT and not movement_completed:
		return
		
	# Check if we're in sprint/dash tutorial and it's not completed
	if current_tutorial_step == TutorialStep.DASH_SPRINT and not (has_sprinted and has_dashed):
		return
		
	is_tutorial_transitioning = true
	is_popup_active = false
	
	if is_instance_valid(next_tutorial_timer):
		next_tutorial_timer.queue_free()
		next_tutorial_timer = null
	
	# For helper messages (stamina warning), show next step immediately
	if current_tutorial_step == TutorialStep.STAMINA_WARNING:
		show_next_tutorial()
		is_tutorial_transitioning = false
		return
	
	# For main tutorial steps, use a delay
	next_tutorial_timer = Timer.new()
	add_child(next_tutorial_timer)
	next_tutorial_timer.wait_time = 3.0
	next_tutorial_timer.one_shot = true
	next_tutorial_timer.timeout.connect(func(): 
		show_next_tutorial()
		if is_instance_valid(next_tutorial_timer):
			next_tutorial_timer.queue_free()
			next_tutorial_timer = null
		is_tutorial_transitioning = false
	)
	next_tutorial_timer.start()

func show_tutorial_popup(message: String, is_movement: bool = false) -> void:
	if is_instance_valid(tutorial_popup):
		tutorial_popup.fade_out()
		await tutorial_popup.fade_completed
		tutorial_popup = null
	
	await get_tree().create_timer(0.1).timeout  # Small delay to ensure cleanup
	
	is_popup_active = true
	var popup_scene = load("res://ui/tutorial/tutorial_popup.tscn")
	if not popup_scene:
		push_error("Failed to load tutorial popup scene")
		return
		
	tutorial_popup = popup_scene.instantiate()
	$HUDCamera/HUD.add_child(tutorial_popup)
	tutorial_popup.set_message(message, is_movement)
	tutorial_popup.tutorial_completed.connect(_on_tutorial_completed, CONNECT_ONE_SHOT)  # Only allow one completion
	tutorial_popup.fade_in()

func _on_player_moved(velocity: Vector2) -> void:
	if velocity.length() == 0 or not is_instance_valid(tutorial_popup):
		return
		
	var direction = ""
	if abs(velocity.y) > abs(velocity.x):
		direction = "up" if velocity.y < 0 else "down"
	else:
		direction = "left" if velocity.x < 0 else "right"
	
	tutorial_popup.register_movement(direction)
	movement_completed = true

func show_next_tutorial() -> void:
	current_tutorial_step += 1
	
	match current_tutorial_step:
		TutorialStep.MOVEMENT:
			setup_movement_tutorial()
		TutorialStep.DASH_SPRINT:
			setup_dashing_sprinting_tutorial()
		TutorialStep.STAMINA_WARNING:
			setup_stamina_warning()
		TutorialStep.COMPLETED:
			complete_tutorial()
		_:
			push_error("Invalid tutorial step encountered")

func setup_stamina_warning() -> void:
	if is_popup_active:
		return
	show_tutorial_popup("Watch your stamina wheel! If it don't, you'll become exhausted.", false)
	
	# Create a timer to auto-complete this step
	var auto_complete_timer = Timer.new()
	add_child(auto_complete_timer)
	auto_complete_timer.wait_time = 3.0  # Show the message for 3 seconds
	auto_complete_timer.one_shot = true
	auto_complete_timer.timeout.connect(func():
		if is_instance_valid(tutorial_popup):
			tutorial_popup.tutorial_completed.emit()
		auto_complete_timer.queue_free()
	)
	auto_complete_timer.start()

func _on_tutorial_complete() -> void:	
	# Wait 3 seconds before transitioning
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://ui/menus/main_menu/controls_menu/controls_menu.tscn")
