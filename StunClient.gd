extends Node

# STUN: https://datatracker.ietf.org/doc/html/rfc8489

enum MessageType {
	BINDING_REQUEST = 0x0001,
	BINDING_SUCCESS = 0x0101,
	BINDING_ERROR   = 0x0111,
}

enum AttributeType {
	UNKNOWN                  = 0x0000,
	MAPPED_ADDRESS           = 0x0001,
	USERNAME                 = 0x0006,
	MESSAGE_INTEGRITY        = 0x0008,
	ERROR_CODE               = 0x0009,
	UNKNOWN_ATTRIBUTES       = 0x000a,
	REALM                    = 0x0014,
	NONCE                    = 0x0015,
	MESSAGE_INTEGRITY_SHA256 = 0x001c,
	PASSWORD_ALGORITHM       = 0x001d,
	USERHASH                 = 0x001e,
	XOR_MAPPED_ADDRESS       = 0x0020,
	PASSWORD_ALGORITHMS      = 0x8002,
	ALTERNATE_DOMAIN         = 0x8003,
	SOFTWARE                 = 0x8022,
	ALTERNATE_SERVER         = 0x8023,
	FINGERPRINT              = 0x8028,
	RESPONSE_ORIGIN          = 0x802b,
}

const MAGIC_COOKIE = 0x2112a442

class Attribute:
	var type: int
	var data: Dictionary
	
	func _init(_type: int):
		type = _type
	


class Message:
	var type: int
	var txn_id: String
	var attributes: Array
	
	func _init(_type: int, _txn_id: String) -> void:
		type = _type
		txn_id = _txn_id

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)

func _init(ip: String, port: int) -> void:
	_peer.connect_to_host(ip, port)

static func _txn_id_to_bytes(txn_id: String) -> Array:
	var bytes := []
	for i in range(12):
		bytes.append(("0x" + txn_id.substr(i * 2, 2)).hex_to_int())
	return bytes

static func _bytes_to_int(bytes: Array) -> int:
	var count := bytes.size()
	if count > 8:
		return 0
	var shift := (count - 1) * 8
	var value := 0
	for i in range(count):
		if shift > 0:
			value = value & (bytes[i] << shift)
		else:
			value = value & bytes[i]
		shift -= 8
	return value

func _new_txn_id() -> String:
	return "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % [
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
	]

func send_message(msg: Message) -> void:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.resize(20)
	
	buffer.put_u16(msg.type)
	
	# @todo This is the size of the message after the header - put 0 for now
	buffer.put_u16(0)
	
	buffer.put_u32(MAGIC_COOKIE)
	
	# Write the transaction id.
	for byte in _txn_id_to_bytes(msg.txn_id):
		buffer.put_u8(byte)
	
	# @todo Actually write the attributes
	
	_txns[msg.txn_id] = msg
	_peer.put_packet(buffer.data_array)

func poll() -> void:
	while true:
		var data := _peer.get_packet()
		if not data:
			return
		
		var buffer := StreamPeerBuffer.new()
		buffer.big_endian = true
		buffer.put_data(data)
		buffer.seek(0)
		
		var type = buffer.get_u16()
		var size = buffer.get_u16()
		
		var magic_cookie = buffer.get_u32()
		if magic_cookie != MAGIC_COOKIE:
			push_error("Magic cookie doesn't match the expected value")
			continue
		
		var txn_id: String = ""
		for i in range(12):
			txn_id += "%x" % buffer.get_u8()
		
		var request: Message = _txns.get(txn_id)
		if request == null:
			push_warning("Received response with unknown transaction id: %s" % txn_id)
		else:
			_txns.erase(txn_id)
		
		var response = Message.new(type, txn_id)
		
		# Parse the attributes.
		while buffer.get_position() < buffer.get_size():
			var attr = _parse_attribute(buffer, txn_id)
			if attr:
				response.attributes.append(attr)
		
		emit_signal("message_received", response, request)

static func _parse_address_attribute(attr: Attribute, buffer: StreamPeerBuffer) -> void:
	var unused = buffer.get_u8()
	attr.data['family'] = buffer.get_u8()
	attr.data['port'] = buffer.get_u16()
	if attr.data['family'] == 0x01:
		attr.data['ip'] = "%d.%d.%d.%d" % [
			buffer.get_u8(),
			buffer.get_u8(),
			buffer.get_u8(),
			buffer.get_u8(),
		]
	else:
		attr.data['ip'] = "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x" % [
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
			buffer.get_u16(),
		]

static func _parse_xor_address_attribute(attr: Attribute, buffer: StreamPeerBuffer, txn_id: String) -> void:
	var unused = buffer.get_u8()
	attr.data['family'] = buffer.get_u8()
	attr.data['port'] = buffer.get_u16() ^ (MAGIC_COOKIE >> 16)
	if attr.data['family'] == 0x01:
		var ip = buffer.get_u32() ^ MAGIC_COOKIE
		attr.data['ip'] = "%d.%d.%d.%d" % [
			ip >> 24,
			(ip >> 16) & 0xff,
			(ip >> 8) & 0xff,
			ip & 0xff,
		]
	else:
		var tb = _txn_id_to_bytes(txn_id)
		var high_mask = ((MAGIC_COOKIE << 32) & _bytes_to_int(tb.slice(0, 4)))
		var low_mask = _bytes_to_int(tb.slice(4, 12))
		var high_value = buffer.get_u64() ^ high_mask
		var low_value = buffer.get_u64() ^ low_mask
		attr.data['ip'] = "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x" % [
			high_value >> 48,
			(high_value >> 32) & 0xffff,
			(high_value >> 16) & 0xffff,
			high_value & 0xffff,
			low_value >> 48,
			(low_value >> 32) & 0xffff,
			(low_value >> 16) & 0xffff,
			low_value & 0xffff,
		]

static func _skip_padding(buffer: StreamPeerBuffer, size: int) -> void:
	var remainder = size % 4
	if remainder > 0:
		buffer.seek(buffer.get_position() + remainder)

static func _parse_attribute(buffer: StreamPeerBuffer, txn_id: String) -> Attribute:
	var type := buffer.get_u16()
	var size := buffer.get_u16()
	var orig_size := size
	if buffer.get_position() + size > buffer.get_size():
		size = buffer.get_size() - buffer.get_position()
	
	var attr := Attribute.new(type)
	
	match type:
		AttributeType.MAPPED_ADDRESS:
			_parse_address_attribute(attr, buffer)
		
		AttributeType.XOR_MAPPED_ADDRESS:
			_parse_xor_address_attribute(attr, buffer, txn_id)
		
		AttributeType.RESPONSE_ORIGIN:
			_parse_address_attribute(attr, buffer)
		
		AttributeType.SOFTWARE:
			attr.data['software'] = buffer.get_data(size)[1].get_string_from_utf8()
			_skip_padding(buffer, size)
		
		AttributeType.FINGERPRINT:
			attr.data['fingerprint'] = buffer.get_u32()
		
		_:
			attr.type = AttributeType.UNKNOWN
			attr.data['type'] = type
			attr.data['data'] = buffer.get_data(size)[1]
			attr.data['size'] = orig_size
			_skip_padding(buffer, size)
	
	return attr

func send_binding_request() -> void:
	var msg = Message.new(MessageType.BINDING_REQUEST, _new_txn_id())
	send_message(msg)
