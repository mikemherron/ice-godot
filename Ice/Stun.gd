# STUN: https://datatracker.ietf.org/doc/html/rfc8489
extends Node

func bytes_to_hex(bytes: PackedByteArray) -> String:
	var hex_string = ""
	for b in bytes:
		hex_string += "%02x" % b
	return hex_string
	
const MAGIC_COOKIE = 0x2112a442

# 96-bit transaction id.
class TxnId:
	var bytes := []
	
	func _init(_bytes: Array) -> void:
		bytes = _bytes
	
	func _to_string() -> String:
		return "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % bytes
	
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

var AttributeClasses := {
	MappedAddressAttribute.TYPE		: MappedAddressAttribute,
	XorMappedAddressAttribute.TYPE	: XorMappedAddressAttribute,
	SoftwareAttribute.TYPE			: SoftwareAttribute,
	FingerprintAttribute.TYPE		: FingerprintAttribute,
	ResponseOriginAttribute.TYPE	: ResponseOriginAttribute,
	OtherAddressAttribute.TYPE		: OtherAddressAttribute,
	ErrorCodeAttribute.TYPE			: ErrorCodeAttribute,
	UsernameAttribute.TYPE			: UsernameAttribute,
	RealmAttribute.TYPE				: RealmAttribute,
	NonceAttribute.TYPE				: NonceAttribute
}

class Attribute:
	var type: int
	var name: String
	
	func _init(_type: int, _name: String):
		type = _type
		name = _name
	
	static func _skip_padding(buffer: StreamPeerBuffer, size: int) -> void:
		while size % 4 != 0:
			buffer.get_8()
			size+= 1
	
	static func _write_padding(buffer: StreamPeerBuffer, size: int) -> void:
		while size % 4 != 0:
			buffer.put_u8(0)
			size+= 1
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		buffer.seek(buffer.get_position() + size)
		Attribute._skip_padding(buffer, size)
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		pass
	
	func _to_string() -> String:
		## TODO fix this, caused recursion with port to GD4
		var details = "" #to_string()
		if details == '':
			return '%s (%04x)' % [name, type]
		return '%s (%04x): %s' % [name, type, details]

class UnknownAttribute extends Attribute:
	var data: PackedByteArray
	
	func _init(type: int):
		super(type, 'UNKNOWN')
	
	func _to_string() -> String:
		return str(data)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		data = buffer.get_data(size)[1]
		Attribute._skip_padding(buffer, size)
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		buffer.put_u16(data.size())
		buffer.put_data(data)
		Attribute._write_padding(buffer, data.size())
		
class ErrorCodeAttribute extends Attribute:
	const TYPE = 0x0009
	const NAME = "ERROR-CODE"
	
	var code : int 
	var reason : String
	
	func _init():
		super(TYPE, NAME)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		buffer.seek(buffer.get_position()+1)
		code = (buffer.get_u16() * 100) + buffer.get_u8()
		var remaining_byes : int = 4-size
		if remaining_byes > 0:
			reason = buffer.get_utf8_string()
		else:
			reason = ""
		Attribute._skip_padding(buffer, size)
		
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		var size : int = 4 + reason.to_utf8_buffer().size()
		buffer.put_u16(size)
		buffer.put_u8(0)
		
		## TODO this properly!
		buffer.put_u16(code / 100)
		buffer.put_8(1)
		## 
		
		if reason!="":
			buffer.put_utf8_string(reason)
		Attribute._write_padding(buffer,size)
	
	func _to_string() -> String:
		return '%s (%04x): code: %d, reason: %s' % [name, type, code, reason]

class _StringAttribute extends Attribute:
	
	var _value : String
	
	func _init(type, name):
		super(type, name)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		_value = buffer.get_data(size)[1].get_string_from_utf8()
		Attribute._skip_padding(buffer, size)
		
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		var bytes : PackedByteArray = _value.to_utf8_buffer()
		buffer.put_u16(bytes.size())
		buffer.put_data(bytes)
		print(" Type %s has data size %d, should add padding of %d" % [name, bytes.size(), bytes.size() % 4])
		Attribute._write_padding(buffer, bytes.size())
	
	func _to_string() -> String:
		return '%s (%04x): %s' % [name, type, _value]
		
class UsernameAttribute extends _StringAttribute:
	const TYPE = 0x0006
	const NAME = "USERNAME"
	
	var username : String:
		get: 
			return _value
		set(value):
			_value = value
			
	func _init(username : String):
		super(TYPE, NAME)
		self.username = username
		
class MessageIntegrityAttribute extends Attribute:
	const TYPE = 0x0008
	const NAME = "MESSAGE-INTEGRITY"
	
	var hmac : PackedByteArray
		
	func _init(hmac : PackedByteArray):
		super(TYPE, NAME)
		self.hmac = hmac
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		hmac = buffer.get_data(size)[1]
		Attribute._skip_padding(buffer, size)
		
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		buffer.put_u16(hmac.size())
		print("MessageIntegrity writing size: %d" % [hmac.size()])
		buffer.put_data(hmac)
		Attribute._write_padding(buffer, hmac.size())
	
	func _to_string() -> String:
		return '%s (%04x): %s' % [name, type, hmac]
		
class RealmAttribute extends _StringAttribute:
	const TYPE = 0x0014
	const NAME = "REALM"
	
	var realm : String:
		get: 
			return _value
		set(value):
			_value = value
			
	func _init():
		super(TYPE, NAME)
	
class NonceAttribute extends _StringAttribute:
	const TYPE = 0x0015
	const NAME = "NONCE"
	
	var nonce : String:
		get: 
			return _value
		set(value):
			_value = value
			
	func _init():
		super(TYPE, NAME)

class FingerprintAttribute extends Attribute:
	const TYPE = 0x8028
	const NAME = "FINGERPRINT"
	func _init():
		super(TYPE, NAME)
	
	var fingerprint: int
	
	func _to_string() -> String:
		return str(fingerprint)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		fingerprint = buffer.get_u32()
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		buffer.put_u16(4)
		buffer.put_u32(fingerprint)
				
enum AddressFamily {
	UNKNOWN = 0x00,
	IPV4    = 0x01,
	IPV6    = 0x02,
}

class _AddressAttribute extends Attribute:
	func _init(_type: int, _name: String):
		super(_type, _name)
	
	var family: int
	var port: int
	var ip: String
	
	func _to_string() -> String:
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
	
	func _write_type_and_size(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		var size := 0
		if family == AddressFamily.IPV4:
			size = 4
		elif family == AddressFamily.IPV6:
			size = 16
		buffer.put_u16(size + 2)
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		_write_type_and_size(buffer, msg)
		buffer.put_u16(family)
		buffer.put_u16(port)
		if family == AddressFamily.IPV4:
			buffer.put_u32(_parse_ipv4())
		elif family == AddressFamily.IPV6:
			for value in _parse_ipv6():
				buffer.put_u64(value)

class _XorAddressAttribute extends _AddressAttribute:
	func _init(_type: int, _name: String):
		super(_type, _name)
	
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
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		_write_type_and_size(buffer, msg)
		buffer.put_u16(family)
		buffer.put_u16(port ^ (MAGIC_COOKIE >> 16))
		if family == AddressFamily.IPV4:
			var ip_value := _parse_ipv4()
			buffer.put_u32(ip_value ^ MAGIC_COOKIE)
		elif family == AddressFamily.IPV6:
			var ip_value := _parse_ipv6()
			var high_mask = ((MAGIC_COOKIE << 32) | msg.txn_id.slice_to_int(0, 3))
			var low_mask = msg.txn_id.slice_to_int(4, 11)
			buffer.put_u64(ip_value[0] ^ high_mask)
			buffer.put_u64(ip_value[0] ^ low_mask)

class MappedAddressAttribute extends _AddressAttribute:
	const TYPE = 0x0001
	const NAME = "MAPPED-ADDRESS"
	func _init():
		super(TYPE, NAME)

class XorMappedAddressAttribute extends _XorAddressAttribute:
	const TYPE = 0x0020
	const NAME = "XOR-MAPPED-ADDRESS"
	func _init():
		super(TYPE, NAME)

class SoftwareAttribute extends Attribute:
	const TYPE = 0x8022
	const NAME = "SOFTWARE"
	func _init():
		super(TYPE, NAME)
	
	var description: String
	
	func _to_string() -> String:
		return description
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		description = buffer.get_data(size)[1].get_string_from_utf8()
		Attribute._skip_padding(buffer, size)
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_u16(type)
		var bytes : PackedByteArray = description.to_utf8_buffer()
		buffer.put_u16(bytes.size())
		buffer.put_data(bytes)
		Attribute._write_padding(buffer, bytes.size())

class RequestedTransportAttribute extends Attribute:
	
	# https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
	const UDP = 17
	
	const TYPE = 0x0019
	const NAME = "REQUESTED-TRANSPORT"
	
	func _init():
		super(TYPE, NAME)
	
	func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: Message) -> void:
		buffer.get_u32()
	
	func write_to_buffer(buffer: StreamPeerBuffer, msg: Message) -> void:
		buffer.put_16(type)
		#Always 4
		buffer.put_16(4)
		buffer.put_u8(UDP)
		buffer.put_u16(0)
		buffer.put_u8(0)

class ResponseOriginAttribute extends _AddressAttribute:
	const TYPE = 0x802b
	const NAME = "RESPONSE-ORIGIN"
	func _init():
		super(TYPE, NAME)

class OtherAddressAttribute extends _AddressAttribute:
	const TYPE = 0x802c
	const NAME = "OTHER-ADDRESS"
	func _init():
		super(TYPE, NAME)

#####
# MESSAGE:
#####

# See: https://www.iana.org/assignments/stun-parameters/stun-parameters.xhtml#stun-parameters-2

# MessageType is a "unusual" encoding of a message class (request, success response, error response
# or indication) and a method (allocate, bind, etc.)
# 
# See https://www.rfc-editor.org/rfc/rfc8489#section-5
enum MessageType {
	BINDING_REQUEST = 0x0001,
	BINDING_SUCCESS = 0x0101,
	BINDING_ERROR   = 0x0111,
	
	ALLOCATE		= 0x0003,
	ALLOCATE_ERROR	= 0x0113
}

class Message:
	var type: int
	var txn_id: TxnId
	var attributes: Array[Attribute]
	
	func _init(_type: int, _txn_id: TxnId, _attributes : Array[Attribute] = []) -> void:
		type = _type
		txn_id = _txn_id
		attributes = _attributes
	
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
	
	func get_attribute(attribute_type : int):
		for attribute in attributes:
			if attribute.type == attribute_type:
				return attribute
		return null

	func to_bytes(add_bytes : int = 0) -> PackedByteArray:
		var buffer := StreamPeerBuffer.new()
		buffer.big_endian = true
		
		buffer.put_u16(type)
		# This is the size - just put 0 for now.
		buffer.put_u16(0)
		buffer.put_u32(MAGIC_COOKIE)
		
		# Write the transaction id.
		for byte in txn_id.bytes:
			buffer.put_u8(byte)
		
		for attr in attributes:
			var before : int = buffer.get_size()
			attr.write_to_buffer(buffer, self)
			var after : int = buffer.get_size()
			print(" - attribute %s added: %d" % [attr.name, after-before])
			if (after-before) % 4 != 0:
				push_warning("attribute type %s does not end on a 32 bit boundary" % [attr.name])
		
		# Write the size in now that we know it.
		buffer.seek(2)
		buffer.put_u16(buffer.get_size() - 20 + add_bytes)
		print(" - total message size (minus header):%d" % [buffer.get_size()-20])
		print(" - buffer size:%d" % [buffer.data_array.size()])
		
		return buffer.data_array
	
	static func from_bytes(bytes: PackedByteArray, attribute_classes = null) -> Message:
		var buffer := StreamPeerBuffer.new()
		buffer.big_endian = true
		buffer.put_data(bytes)
		buffer.seek(0)
		
		var type = buffer.get_u16()
		var size = buffer.get_u16()
		
		var magic_cookie = buffer.get_u32()
		if magic_cookie != MAGIC_COOKIE:
			push_error("Magic cookie doesn't match the expected value")
			return null
		
		var msg = Message.new(type, TxnId.read_from_buffer(buffer))
		
		# Parse the attributes.
		if attribute_classes:
			while buffer.get_position() < buffer.get_size():
				var attr = _parse_attribute(buffer, attribute_classes, msg)
				if attr:
					msg.attributes.append(attr)
		
		return msg
	
	static func _parse_attribute(buffer: StreamPeerBuffer, attribute_classes: Dictionary, msg: Message) -> Attribute:
		var type := buffer.get_u16()
		var size := buffer.get_u16()
		if buffer.get_position() + size > buffer.get_size():
			size = buffer.get_size() - buffer.get_position()
		
		var attr: Attribute
		print("Looking for attribute with byte size: %d, type: %04x" % [size, type])
		if attribute_classes.has(type):
			attr = attribute_classes[type].new()
		else:
			attr = UnknownAttribute.new(type)
		
		attr.read_from_buffer(buffer, size, msg)
		return attr
