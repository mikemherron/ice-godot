extends StunAttribute

class_name StunAttributeErrorCode

const TYPE = 0x0009
const NAME = "ERROR-CODE"
const CODE_SIZE = 4

var code : int 
var reason : String

func _init():
	super(TYPE, NAME)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
	# Skip the first byte
	buffer.seek(buffer.get_position() + 1) 
	var error_class : int = buffer.get_u16()
	var error_number : int = buffer.get_u8()
	code = (error_class * 100) + error_number
	reason = buffer.get_utf8_string() if size > CODE_SIZE else ""
	_skip_padding(buffer, size)
	
func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
	var size : int = CODE_SIZE + reason.to_utf8_buffer().size()
	var error_class : int = floori(code / 100.0)
	var error_number : int = code - (error_class * 100)
	buffer.put_u16(type)
	buffer.put_u16(size)
	# Empty first byte
	buffer.put_u8(0)
	buffer.put_u16(error_class)
	buffer.put_8(error_number)
	if !reason.is_empty():
		buffer.put_utf8_string(reason)
	_write_padding(buffer,size)

func _to_string() -> String:
	return '%s (%04x): code: %d, reason: %s' % [name, type, code, reason]
