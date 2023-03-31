extends StunAttribute

class_name StunAttributeLifetime

const TYPE = 0x000D
const NAME = "LIFETIME"
const SIZE = 4

var lifetime: int

func _init():
  super(TYPE, NAME)

func _to_string() -> String:
  return str(lifetime)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  lifetime = buffer.get_u32()

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(TYPE)
  buffer.put_u16(SIZE)
  buffer.put_u32(lifetime)