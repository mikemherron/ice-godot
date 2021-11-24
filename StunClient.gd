extends Node

# STUN: https://datatracker.ietf.org/doc/html/rfc8489

const MAGIC_COOKIE = 0x2112a442

# 96-bit transaction id.
class TxnId:
	var bytes := []
	
	func _init(_bytes: Array) -> void:
		bytes = _bytes
	
	func to_string() -> String:
		return "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % bytes
	
	func _to_string() -> String:
		return to_string()
	
	static func from_string(s: String) -> TxnId:
		var bytes := []
		for i in range(12):
			bytes.append(("0x" + s.substr(i * 2, 2)).hex_to_int())
		return TxnId.new(bytes)
	
	static func new_random() -> TxnId:
		var bytes := []
		for i in range(12):
			bytes.append(randi() % 256)
		return TxnId.new(bytes)
	
	static func read_from_buffer(buffer: StreamPeerBuffer) -> TxnId:
		var bytes := []
		for i in range(12):
			bytes.append(buffer.get_u8())
		return TxnId.new(bytes)
	
	func slice_to_int(start: int, end: int) -> int:
		var slice := bytes.slice(start, end)
		var count := slice.size()
		if count > 8:
			return 0
		var shift := (count - 1) * 8
		var value := 0
		for i in range(count):
			if shift > 0:
				value = value | (slice[i] << shift)
			else:
				value = value | slice[i]
			shift -= 8
		return value

#####
# ATTRIBUTES
# ===============
# See: https://www.iana.org/assignments/stun-parameters/stun-parameters.xhtml#stun-parameters-4
#####

class Attribute:
	var type: int
	var name: String
	
	func _init(_type: int, _name: String):
		type = _type
		name = _name
	
	static func _skip_padding(buffer: StreamPeerBuffer, size: int) -> void:
		var remainder = size % 4
		if remainder > 0:
			buffer.seek(buffer.get_position() + remainder)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		buffer.seek(buffer.get_position() + size)
		_skip_padding(buffer, size)
	
	func write_to_buffer(buffer: StreamPeerBuffer) -> void:
		pass
	
	func to_string() -> String:
		return ''
	
	func _to_string() -> String:
		var details = to_string()
		if details == '':
			return '%s (%04x)' % [name, type]
		return '%s (%04x): %s' % [name, type, details]

class UnknownAttribute extends Attribute:
	var data: PoolByteArray
	
	func _init(type: int).(type, 'UNKNOWN'):
		pass
	
	func to_string() -> String:
		return str(data)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		data = buffer.get_data(size)[1]
		_skip_padding(buffer, size)

enum AddressFamily {
	UNKNOWN = 0x00,
	IPV4    = 0x01,
	IPV6    = 0x02,
}

class _AddressAttribute extends Attribute:
	func _init(_type: int, _name: String).(_type, _name): pass
	
	var family: int
	var port: int
	var ip: String
	
	func to_string() -> String:
		var fs: String
		match family:
			AddressFamily.IPV4:
				fs = 'IPv4'
			AddressFamily.IPV6:
				fs = 'IPv6'
			_:
				fs = 'UNKNOWN'
		return '%s:%s (%s)' % [ip, port, fs]
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		family = buffer.get_u16()
		port = buffer.get_u16()
		if family == AddressFamily.IPV4:
			ip = "%d.%d.%d.%d" % [
				buffer.get_u8(),
				buffer.get_u8(),
				buffer.get_u8(),
				buffer.get_u8(),
			]
		elif family == AddressFamily.IPV6:
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

class _XorAddressAttribute extends _AddressAttribute:
	func _init(_type: int, _name: String).(_type, _name): pass
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		family = buffer.get_u16()
		port = buffer.get_u16() ^ (MAGIC_COOKIE >> 16)
		if family == AddressFamily.IPV4:
			var raw_ip = buffer.get_u32() ^ MAGIC_COOKIE
			ip = "%d.%d.%d.%d" % [
				(raw_ip >> 24) & 0xff,
				(raw_ip >> 16) & 0xff,
				(raw_ip >> 8) & 0xff,
				raw_ip & 0xff,
			]
		elif family == AddressFamily.IPV6:
			var high_mask = ((MAGIC_COOKIE << 32) | msg.txn_id.slice_to_int(0, 3))
			var low_mask = msg.txn_id.slice_to_int(4, 11)
			var high_value = buffer.get_u64() ^ high_mask
			var low_value = buffer.get_u64() ^ low_mask
			ip = "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x" % [
				(high_value >> 48) & 0xffff,
				(high_value >> 32) & 0xffff,
				(high_value >> 16) & 0xffff,
				high_value & 0xffff,
				(low_value >> 48) & 0xffff,
				(low_value >> 32) & 0xffff,
				(low_value >> 16) & 0xffff,
				low_value & 0xffff,
			]

class MappedAddressAttribute extends _AddressAttribute:
	const TYPE = 0x0001
	const NAME = "MAPPED-ADDRESS"
	func _init().(TYPE, NAME): pass

class XorMappedAddressAttribute extends _XorAddressAttribute:
	const TYPE = 0x0020
	const NAME = "XOR-MAPPED-ADDRESS"
	func _init().(TYPE, NAME): pass

class SoftwareAttribute extends Attribute:
	const TYPE = 0x8022
	const NAME = "SOFTWARE"
	func _init().(TYPE, NAME): pass
	
	var description: String
	
	func to_string() -> String:
		return description
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		description = buffer.get_data(size)[1].get_string_from_utf8()
		_skip_padding(buffer, size)

class FingerprintAttribute extends Attribute:
	const TYPE = 0x8028
	const NAME = "FINGERPRINT"
	func _init().(TYPE, NAME): pass
	
	var fingerprint: int
	
	func to_string() -> String:
		return str(fingerprint)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		fingerprint = buffer.get_u32()

class ResponseOriginAttribute extends _AddressAttribute:
	const TYPE = 0x802b
	const NAME = "RESPONSE-ORIGIN"
	func _init().(TYPE, NAME): pass

class OtherAddressAttribute extends _AddressAttribute:
	const TYPE = 0x802c
	const NAME = "OTHER-ADDRESS"
	func _init().(TYPE, NAME): pass

var attribute_classes := {
	MappedAddressAttribute.TYPE: MappedAddressAttribute,
	XorMappedAddressAttribute.TYPE: XorMappedAddressAttribute,
	SoftwareAttribute.TYPE: SoftwareAttribute,
	FingerprintAttribute.TYPE: FingerprintAttribute,
	ResponseOriginAttribute.TYPE: ResponseOriginAttribute,
	OtherAddressAttribute.TYPE: OtherAddressAttribute,
}

#####
# MESSAGE:
#####

# See: https://www.iana.org/assignments/stun-parameters/stun-parameters.xhtml#stun-parameters-2
enum MessageType {
	BINDING_REQUEST = 0x0001,
	BINDING_SUCCESS = 0x0101,
	BINDING_ERROR   = 0x0111,
}

class Message:
	var type: int
	var txn_id: TxnId
	var attributes: Array
	
	func _init(_type: int, _txn_id: TxnId) -> void:
		type = _type
		txn_id = _txn_id
	
	func _to_string() -> String:
		var s: String
		if txn_id:
			s = 'StunMessage(type=0x%04x, txn_id=%s)' % [type, txn_id]
		else:
			s = 'StunMessage(type=0x%04x)' % type
		if attributes.size() > 0:
			s += ':'
			for attr in attributes:
				s += "\n  " + str(attr)
		return s

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)

func _init(ip: String, port: int) -> void:
	_peer.connect_to_host(ip, port)

func send_message(msg: Message) -> void:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.resize(20)
	
	buffer.put_u16(msg.type)
	
	# @todo This is the size of the message after the header - put 0 for now
	buffer.put_u16(0)
	
	buffer.put_u32(MAGIC_COOKIE)
	
	# Write the transaction id.
	for byte in msg.txn_id.bytes:
		buffer.put_u8(byte)
	
	# @todo Actually write the attributes
	
	_txns[msg.txn_id.to_string()] = msg
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
		
		var txn_id := TxnId.read_from_buffer(buffer)
		var txn_id_string := txn_id.to_string()
		
		var request: Message = _txns.get(txn_id_string)
		if request == null:
			push_warning("Received response with unknown transaction id: %s" % txn_id)
		else:
			_txns.erase(txn_id_string)
		
		var response = Message.new(type, txn_id)
		
		# Parse the attributes.
		while buffer.get_position() < buffer.get_size():
			var attr = _parse_attribute(buffer, response)
			if attr:
				response.attributes.append(attr)
		
		emit_signal("message_received", response, request)

func _parse_attribute(buffer: StreamPeerBuffer, msg: Message) -> Attribute:
	var type := buffer.get_u16()
	var size := buffer.get_u16()
	var orig_size := size
	if buffer.get_position() + size > buffer.get_size():
		size = buffer.get_size() - buffer.get_position()
	
	var attr: Attribute
	if attribute_classes.has(type):
		attr = attribute_classes[type].new()
	else:
		attr = UnknownAttribute.new(type)
	
	attr.read_from_buffer(buffer, size, msg)
	return attr

func send_binding_request() -> void:
	var msg = Message.new(MessageType.BINDING_REQUEST, TxnId.new_random())
	send_message(msg)
