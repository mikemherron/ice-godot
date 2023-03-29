extends StunAttribute

class_name StunAttributeMessageIntegrity

const TYPE = 0x0008
const NAME = "MESSAGE-INTEGRITY"
	
var hmac : PackedByteArray

func _init(_hmac : PackedByteArray):
  super(TYPE, NAME)
  hmac = _hmac
	
func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  hmac = buffer.get_data(size)[1]
  _skip_padding(buffer, size)
  
func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  buffer.put_u16(hmac.size())
  buffer.put_data(hmac)
  _write_padding(buffer, hmac.size())

func _to_string() -> String:
  return '%s (%04x): %s' % [name, type, hmac]