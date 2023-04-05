extends Panel

func set_data(channel : int, data : PackedByteArray) -> void:
	$Channel.text = "[%d]" % [channel]
	var string = data.get_string_from_utf8()
	if string.is_empty():
		string = "[raw] %s" % [data]
	else:
		string = "[string] " + string
	$Bytes.text = data

func _on_mouse_entered():
	modulate.a = 1

func _on_mouse_exited():
	modulate.a = 0.8
