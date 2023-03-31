extends StunAttribute

class_name StunAttributeMessageIntegrity

const TYPE = 0x0008
const NAME = "MESSAGE-INTEGRITY"

var hmac : PackedByteArray

static func for_message(key : PackedByteArray, msg : StunMessage) -> StunAttributeMessageIntegrity:
	var crypto := Crypto.new()
	# Message integrity is calculated over the entire message exluding the message integrity attribute
	# itself, but the message integrity attribute length *should* be reflected in the message length 
	# attribute, so we need to add it to the bytes we used for the hmac
	var hmac : PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA1, key, msg.to_bytes(24))
	return StunAttributeMessageIntegrity.new(hmac)
	
func _init(_hmac = null):
	super(TYPE, NAME)
	if _hmac != null:
		hmac = _hmac
	
func verify(key : PackedByteArray, msg : StunMessage) -> bool:
	if !msg.has_attribute(StunAttributeMessageIntegrity.TYPE):
		push_error("message has no message integrity attribute")
		return false

	var integrity_attr : StunAttributeMessageIntegrity = msg.get_attribute(StunAttributeMessageIntegrity.TYPE)
	var msg_copy : StunMessage = StunMessage.from_bytes(msg.to_bytes())
	msg_copy.attributes.erase(msg_copy.get_attribute(StunAttributeMessageIntegrity.TYPE))
	
	var crypto := Crypto.new()
	var expected_hmac : PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA1, key, msg_copy.to_bytes(24))
	if expected_hmac != integrity_attr.hmac:
		push_error("invalid message integrity, expected %s, got %s" % [expected_hmac, integrity_attr.hmac])
		return false

	return true
		
func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
	hmac = buffer.get_data(size)[1]
	
func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
	buffer.put_u16(type)
	buffer.put_u16(hmac.size())
	buffer.put_data(hmac)

func _to_string() -> String:
	return '%s (%04x): %s' % [name, type, hmac]
