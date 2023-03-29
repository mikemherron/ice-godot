extends StunAttribute

class_name StunAttributeUnknown 

const NAME = 'UNKNOWN'

var data: PackedByteArray

func _init(type: int):
  super(type, NAME)

func _to_string() -> String:
  return str(data)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  data = buffer.get_data(size)[1]
  _skip_padding(buffer, size)

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  buffer.put_u16(data.size())
  buffer.put_data(data)
  _write_padding(buffer, data.size())