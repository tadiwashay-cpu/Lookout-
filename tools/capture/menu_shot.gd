extends Node
func _ready() -> void:
	var menu: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/menu_a.png")
	menu.call("_mode_menu", Game.Mode.RACE)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/menu_b.png")
	get_tree().quit()
