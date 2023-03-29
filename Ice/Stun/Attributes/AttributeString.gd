extends StunAttribute

class_name StunAttributeString

var value : String
	
func _init(type, name):
  super(type, name)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  # TODO check for errors returned from get_data
  value = buffer.get_data(size)[1].get_string_from_utf8()
  _skip_padding(buffer, size)
  
func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  var bytes : PackedByteArray = value.to_utf8_buffer()
  buffer.put_u16(bytes.size())
  buffer.put_data(bytes)
  _write_padding(buffer, bytes.size())

func _to_string() -> String:
  return '%s (%04x): %s' % [name, type, value]