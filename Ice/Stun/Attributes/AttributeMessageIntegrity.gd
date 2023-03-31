extends StunAttribute

class_name StunAttributeMessageIntegrity

const TYPE = 0x0008
const NAME = "MESSAGE-INTEGRITY"
	
var hmac : PackedByteArray

func _init():
  super(TYPE, NAME)
	
func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  hmac = buffer.get_data(size)[1]
  
func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  buffer.put_u16(hmac.size())
  buffer.put_data(hmac)

func _to_string() -> String:
  return '%s (%04x): %s' % [name, type, hmac]