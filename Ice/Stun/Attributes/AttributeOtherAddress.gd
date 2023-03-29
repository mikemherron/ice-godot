extends StunAttributeAddress

class_name StunAttributeOtherAddress

const TYPE = 0x802c
const NAME = "OTHER-ADDRESS"

func _init():
  super(TYPE, NAME)