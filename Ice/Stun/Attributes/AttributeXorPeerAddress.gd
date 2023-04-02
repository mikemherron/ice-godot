extends StunAttributeXorAddress

class_name StunAttributeXorPeerAddress

const TYPE = 0x0012
const NAME = "XOR-PEER-ADDRESS"

func _init(_ip : String = "", _port : int = 0, _family : int = StunAttributeAddress.Family.IPV4):
  super(TYPE, NAME)
  ip = _ip
  port = _port
  family = _family