extends Node
class_name UIManager

var health_bar: ProgressBar
var dialogue_box: CanvasLayer = null

# Menus
var pause_menu_scene: PackedScene = preload("res://ui/menus/gameplay/pause_menu/pause_menu.tscn")
var game_over_menu_scene: PackedScene = preload("res://ui/menus/gameplay/game_over_menu/game_over_menu.tscn")
var pause_menu_instance: Node = null
var game_over_menu_instance: Node = null

func initialize_UI(hud_node: Node) -> void:
	# Get references to health bars
	health_bar = hud_node.get_node("PlayerHUD/Health")
	
	dialogue_box = preload("res://ui/hud/dialogue/dialoguebox.tscn").instantiate()
	hud_node.add_child(dialogue_box)
	dialogue_box.hide()

func update_health(health: int, max_health: int = 50) -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health

func start_dialogue(dialogue_data: Array):
	if dialogue_box:
		dialogue_box.show()
		dialogue_box.start_dialogue(dialogue_data)

func is_dialogue_active() -> bool:
	return dialogue_box.visible if dialogue_box else false

func handle_pause_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(game_over_menu_instance) and game_over_menu_instance.visible:
			return
			
		if is_instance_valid(pause_menu_instance) and pause_menu_instance.visible:
			hide_pause_menu()
		else:
			show_pause_menu()

func show_pause_menu() -> void:
	if !is_instance_valid(pause_menu_instance):
		pause_menu_instance = pause_menu_scene.instantiate()
		add_child(pause_menu_instance)
	
	pause_menu_instance.show_menu()
	pause_menu_instance.visible = true
	get_tree().paused = true

func hide_pause_menu() -> void:
	if is_instance_valid(pause_menu_instance):
		pause_menu_instance.visible = false
	get_tree().paused = false

func show_game_over_menu(message: String = "") -> void:
	if !is_instance_valid(game_over_menu_instance):
		game_over_menu_instance = game_over_menu_scene.instantiate()
		add_child(game_over_menu_instance)
	
	game_over_menu_instance.call("show_menu", message)
	game_over_menu_instance.visible = true
	get_tree().paused = true

func hide_game_over_menu() -> void:
	if is_instance_valid(game_over_menu_instance):
		game_over_menu_instance.visible = false
	get_tree().paused = false

func trigger_game_over(message: String) -> void:
	if is_instance_valid(pause_menu_instance):
		pause_menu_instance.queue_free()
		pause_menu_instance = null
	
	show_game_over_menu(message)
