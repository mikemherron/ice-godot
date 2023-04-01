extends Panel

func set_attribute(attribute : StunAttribute) -> void:
	$Desc.text = attribute.to_string()
