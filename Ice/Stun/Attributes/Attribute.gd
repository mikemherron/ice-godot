extends RefCounted

class_name StunAttribute

var type: int
var name: String

func _init(_type: int, _name: String):
	type = _type
	name = _name

# TODO - change from while...
func _skip_padding(buffer: StreamPeerBuffer, size: int) -> void:
	while size % 4 != 0:
		buffer.get_8()
		size+= 1

func _write_padding(buffer: StreamPeerBuffer, size: int) -> void:
	while size % 4 != 0:
		buffer.put_u8(0)
		size+= 1

# TODO - may not need msg to be passed in here, possibly just transaction ID
func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
	buffer.seek(buffer.get_position() + size)
	_skip_padding(buffer, size)

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
	pass

func _to_string() -> String:
	return '%s (%04x)' % [name, type]
