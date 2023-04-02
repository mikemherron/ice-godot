class_name StunMessage

const MAGIC_COOKIE = 0x2112a442
const HEADER_SIZE = 20

var type: int
var txn_id: StunTxnId
var attributes: Array[StunAttribute]

enum Type {
	BINDING_REQUEST   		= 0x0001,
	BINDING_SUCCESS   		= 0x0101,
	BINDING_ERROR     		= 0x0111,
	
	ALLOCATE_REQUEST  		= 0x0003,
	ALLOCATE_SUCCESS  		= 0x0103,
	ALLOCATE_ERROR	  		= 0x0113,

	REFRESH_REQUEST				= 0x0004,
	REFRESH_SUCCESS				= 0x0104,
	REFRESH_ERROR					= 0x0114,

	CHANNEL_BIND_REQUEST	= 0x0009,
	CHANNEL_BIND_SUCCESS	= 0x0109,
	CHANNEL_BIND_ERROR		= 0x0119
}

static func from_bytes(bytes: PackedByteArray) -> StunMessage:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data(bytes)
	return StunMessage.from_buffer(buffer)
	
static func from_buffer(buffer: StreamPeerBuffer) -> StunMessage:
	buffer.seek(0)
	var type = buffer.get_u16()
	var size = buffer.get_u16()
	
	var magic_cookie = buffer.get_u32()
	if magic_cookie != MAGIC_COOKIE:
		push_error("magic cookie doesn't match the expected value")
		return null
	
	var msg = StunMessage.new(type, StunTxnId.read_from_buffer(buffer))
	
	while buffer.get_position() < buffer.get_size():
		var attr = _parse_attribute(buffer, msg)
		if attr:
			msg.attributes.append(attr)
	
	# Debug verify round-tripping results in same bytes
	buffer.seek(0)
	var available : int = buffer.get_available_bytes()
	var bytes : PackedByteArray = PackedByteArray(buffer.get_data(available)[1])
	if msg.to_bytes() != bytes:
		push_error("round-tripping bytes doesn't match original (\n\texpected %s\n\tgot %s)" % [bytes, msg.to_bytes()])

	return msg

static func create_attribute_for_type(_type: int) -> StunAttribute:
	match _type:
		StunAttributeMappedAddress.TYPE:
			return StunAttributeMappedAddress.new()
		StunAttributeXorMappedAddress.TYPE:
			return StunAttributeXorMappedAddress.new()
		StunAttributeXorRelayedAddress.TYPE:
			return StunAttributeXorRelayedAddress.new()
		StunAttributeSoftware.TYPE:
			return StunAttributeSoftware.new()
		StunAttributeFingerprint.TYPE:
			return StunAttributeFingerprint.new()
		StunAttributeResponseOrigin.TYPE:
			return StunAttributeResponseOrigin.new()
		StunAttributeOtherAddress.TYPE:
			return StunAttributeOtherAddress.new()
		StunAttributeErrorCode.TYPE:
			return StunAttributeErrorCode.new()
		StunAttributeUsername.TYPE:
			return StunAttributeUsername.new()
		StunAttributeRealm.TYPE:
			return StunAttributeRealm.new()
		StunAttributeNonce.TYPE:
			return StunAttributeNonce.new()
		StunAttributeLifetime.TYPE:
			return StunAttributeLifetime.new()
		StunAttributeMessageIntegrity.TYPE:
			return StunAttributeMessageIntegrity.new()
	return null

static func _parse_attribute(buffer: StreamPeerBuffer, msg: StunMessage) -> StunAttribute:
	var type := buffer.get_u16()
	var size := buffer.get_u16()
	if buffer.get_position() + size > buffer.get_size():
		size = buffer.get_size() - buffer.get_position()
	var attr: StunAttribute = StunMessage.create_attribute_for_type(type)
	if attr == null:
		push_warning("unknown attribute type 0x%04x" % type)
		attr = StunAttributeUnknown.new(type)
	attr.read_from_buffer(buffer, size, msg)
	return attr

func _init(_type: int, _txn_id: StunTxnId, _attributes : Array[StunAttribute] = []) -> void:
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
	## TODO can probably store these in dict
	for attribute in attributes:
		if attribute.type == attribute_type:
			return attribute
	return null

func has_attribute(attribute_type : int) -> bool:
	return get_attribute(attribute_type) != null

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
		if (after-before) % 4 != 0:
			push_warning("attribute type %s does not end on a 32 bit boundary" % [attr.name])
	
	# Write the size in now that we know it.
	buffer.seek(2)
	buffer.put_u16(buffer.get_size() - 20 + add_bytes)
	return buffer.data_array
