extends StunAttributeString

class_name StunAttributeSoftware
  
const TYPE = 0x8022
const NAME = "SOFTWARE"

func _init():
  super(TYPE, NAME)