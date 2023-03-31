extends StunAttributeString

class_name StunAttributeNonce

const TYPE = 0x0015
const NAME = "NONCE"

func _init(nonce : String = ""):
  super(TYPE, NAME)
  value = nonce
