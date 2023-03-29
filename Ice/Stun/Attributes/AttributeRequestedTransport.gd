extends StunAttribute

class_name StunAttributeRequestedTransport

# See: https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
const UDP = 17

const TYPE = 0x0019
const NAME = "REQUESTED-TRANSPORT"

func _init():
  super(TYPE, NAME)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  buffer.get_u32()

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_16(type)
  buffer.put_16(4)
  buffer.put_u8(UDP)
  buffer.put_u16(0)
  buffer.put_u8(0)
