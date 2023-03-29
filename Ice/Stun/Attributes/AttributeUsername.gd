extends StunAttributeString

class_name StunAttributeUsername
  
const TYPE = 0x0006
const NAME = "USERNAME"

func _init(username = ""):
  super(TYPE, NAME)
  value = username
