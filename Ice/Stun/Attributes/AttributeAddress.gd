extends StunAttribute

class_name StunAttributeAddress

enum Family {
	UNKNOWN = 0x00,
	IPV4    = 0x01,
	IPV6    = 0x02,
}

var family: int
var port: int
var ip: String

func _init(type: int, name: String):
  super(type, name)

func _to_string() -> String:
  var fs: String
  match family:
    Family.IPV4:
      fs = 'IPv4'
    Family.IPV6:
      fs = 'IPv6'
    _:
      fs = 'UNKNOWN'
  return '%s:%s (%s)' % [ip, port, fs]

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  family = buffer.get_u16()
  port = buffer.get_u16()
  if family == Family.IPV4:
    ip = "%d.%d.%d.%d" % [
      buffer.get_u8(),
      buffer.get_u8(),
      buffer.get_u8(),
      buffer.get_u8(),
    ]
  elif family == Family.IPV6:
    ip = "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x" % [
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
      buffer.get_u16(),
    ]

func _parse_ipv4() -> int:
  var parts := ip.split('.')
  if parts.size() != 4:
    return 0
  
  var bytes := []
  for part in parts:
    bytes.append(part.to_int() & 0xff)
  return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[2]

# Returns two 64-bit numbers.
func _parse_ipv6() -> Array:
  # @todo IPv6 can omit parts - handle that!
  var parts := ip.split(':')
  if parts.size() != 8:
    return [0, 0]
  
  var byte_pairs := []
  for part in parts:
    byte_pairs.append(("0x" + part).hex_to_int() & 0xffff)
  
  var high_value = (byte_pairs[0] << 48) | (byte_pairs[1] << 32) | (byte_pairs[2] << 16) | (byte_pairs[3])
  var low_value = (byte_pairs[4] << 48) | (byte_pairs[5] << 32) | (byte_pairs[6] << 16) | (byte_pairs[7])
  return [high_value, low_value]

func _write_type_and_size(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(type)
  var size := 0
  if family == Family.IPV4:
    size = 4
  elif family == Family.IPV6:
    size = 16
  buffer.put_u16(size + 2)

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  _write_type_and_size(buffer, msg)
  buffer.put_u16(family)
  buffer.put_u16(port)
  if family == Family.IPV4:
    buffer.put_u32(_parse_ipv4())
  elif family == Family.IPV6:
    for value in _parse_ipv6():
      buffer.put_u64(value)