extends Panel

var attribute_scene = preload("res://Attribute.tscn")

func set_message(msg : StunMessage) -> void:
	$Type.text = StunMessage.Type.find_key(msg.type)
	$Txn.text = msg.txn_id.to_string()
	
	for attribute in msg.attributes:
		var attribute_display = attribute_scene.instantiate()
		$ScrollContainer/Attributes.add_child(attribute_display)
		attribute_display.set_attribute(attribute)
				
	if 0x110 & msg.type == 0x110:
		$Status/InError.visible = true
	elif 0x100 & msg.type == 0x100:
		$Status/InOK.visible = true
	else:
		$Status/Out.visible = true


func _on_mouse_entered():
	modulate.a = 1

func _on_mouse_exited():
	modulate.a = 0.8
