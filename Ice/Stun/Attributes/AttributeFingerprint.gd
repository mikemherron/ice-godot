extends StunAttribute

class_name StunAttributeFingerprint

const TYPE = 0x8028
const NAME = "FINGERPRINT"

var fingerprint: int

func _init():
  super(TYPE, NAME)

func _to_string() -> String:
  return str(fingerprint)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  fingerprint = buffer.get_u32()

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  buffer.put_u16(4)
  buffer.put_u32(fingerprint)