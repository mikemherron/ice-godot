extends Panel

func set_data(channel : int, data : String) -> void:
	$Channel.text = "[%d]" % [channel]
	$Bytes.text = data
	
func _on_mouse_entered():
	modulate.a = 1

func _on_mouse_exited():
	modulate.a = 0.8
