extends StunAttributeString

class_name StunAttributeRealm
  
const TYPE = 0x0014
const NAME = "REALM"

func _init(realm : String = ""):
  super(TYPE, NAME)
  value = realm
