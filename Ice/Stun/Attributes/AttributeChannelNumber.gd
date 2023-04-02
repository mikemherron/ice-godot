extends StunAttribute

class_name StunAttributeChannelNumber

const TYPE = 0x000C
const NAME = "CHANNEL-NUMBER"
const SIZE = 4

const CHANNEL_MIN = 0x4000
const CHANNEL_MAX = 0x4FFF

var channel : int

func _init(_channel : int = -1):
  super(TYPE, NAME)
  channel = _channel

func _to_string() -> String:
  return "%s: %d" % [name, channel]

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
  channel = buffer.get_u16()
  # reserved or future use and must be 0 according to spec 
  buffer.get_u16()

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
  buffer.put_u16(TYPE)
  buffer.put_u16(SIZE)
  buffer.put_u16(channel)
  # reserved or future use and must be 0 according to spec 
  buffer.put_16(0)
