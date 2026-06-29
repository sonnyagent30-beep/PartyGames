@tool
extends EditorScript

# Programmatically triggers "Install Android Build Template" via the menu action,
# then quits the editor.
#
# Usage:
#   godot4 --editor --path PROJECT --script res://install_android.gd

func _run() -> void:
	print("[install_android] starting")

	# The Project menu has an action "install_android_build_template".
	# We invoke it through the input system which routes to the menu handler.
	var ev := InputEventAction.new()
	ev.action = "install_android_build_template"
	ev.pressed = true
	Input.parse_input_event(ev)

	# Yield a few frames so the install can run, then quit.
	var main_screen := EditorInterface.get_editor_main_screen()
	print("[install_android] main screen = ", main_screen)

	for i in 60:
		await main_screen.get_tree().process_frame

	print("[install_android] done")
	# Quit cleanly
	EditorInterface.get_base_control().get_window().close()