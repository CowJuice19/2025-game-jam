extends Node2D

@onready var ui_manager: UIManager

func _ready() -> void:
	setup_ui_manager()
	Audio.play_music("test2")
	$DialogueBox.load_and_start_dialogue("test", "test")

func setup_ui_manager() -> void:
	ui_manager = UIManager.new()
	add_child(ui_manager)
	ui_manager.initialize_UI($HUDCamera/HUD)

func _on_dialogue_finished():
	print("Dialogue complete!")
	# Handle post-dialogue logic here

func _unhandled_input(event: InputEvent) -> void:
	# Block pause menu during dialogues
	if ui_manager.is_dialogue_active():
		return
	
	if event.is_action_pressed("ui_cancel"): 
		if is_instance_valid(ui_manager.game_over_menu_instance) and ui_manager.game_over_menu_instance.visible:
			return
			
		if is_instance_valid(ui_manager.pause_menu_instance) and ui_manager.pause_menu_instance.visible:
			ui_manager.hide_pause_menu()
		else:
			ui_manager.show_pause_menu()
