extends StunClient

class_name TurnClient

## TODO
#  Time out allocation requests / retry requests
#  Refactor Stun base logic in to StunPacketPeer class, remove inheritance
#  Move digest stuff in to Message integrity?
#  Change allocaiton error signal to include self error code (so can indicate non-response errors)
#  Refresh requests
#  Support lifetime specification in allocate
#  Investigate why PION error strings are not coming back in error responses

signal allocate_success (request: StunMessage, response : StunMessage)
signal allocate_error (request: StunMessage, response : StunMessage)

enum State {
	Idle, AllocateRequested, AllocationActive, AllocationError
}

var _username : String 
var _password : String 
var _realm : String 

var _crypto : Crypto
var _state : int = State.Idle

var _relayed_transport_address : String 
var _server_reflexive_address : String 
var _remaining_lifetime : float 

func _init(ip: String, port: int, username : String, password : String, realm : String):
	super(ip, port)
	_username = username
	_password = password
	_realm = realm
	_crypto = Crypto.new()

func send_allocate_request() -> void:
	if _state != State.Idle:
		push_error("allocate request already sent")
		return
	_state = State.AllocateRequested
	_send_message(StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random()))

func _send_allocate_auth_response(res : StunMessage) -> void:
	# Based on the rules above, the hash used to construct MESSAGE-
	# INTEGRITY includes the length field from the STUN message header.
	# Prior to performing the hash, the MESSAGE-INTEGRITY attribute MUST be
	# inserted into the message (with dummy content).  The length MUST then
	# be set to point to the length of the message up to, and including,
	# the MESSAGE-INTEGRITY attribute itself, but excluding any attributes
	# after it.  Once the computation is performed, the value of the
	# MESSAGE-INTEGRITY attribute can be filled in, and the value of the
	# length in the STUN header can be set to its correct value -- the
	# length of the entire message.  Similarly, when validating the
	# MESSAGE-INTEGRITY, the length field should be adjusted to point to
	# the end of the MESSAGE-INTEGRITY attribute prior to calculating the
	# HMAC.  Such adjustment is necessary when attributes, such as
	# FINGERPRINT, appear after MESSAGE-INTEGRITY.
	
	var msg = StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random(), [
		res.get_attribute(StunAttributeRealm.TYPE),
		res.get_attribute(StunAttributeNonce.TYPE),
		StunAttributeUsername.new(_username),
		StunAttributeRequestedTransport.new()
	])

	var hmac_key : PackedByteArray = ("%s:%s:%s" % [_username, _realm, _password]).md5_buffer()
	
	var hmac_digest : PackedByteArray = _crypto.hmac_digest(
		HashingContext.HASH_SHA1, 
		hmac_key, 
		msg.to_bytes(24))
	
	var integrity_attr = StunAttributeMessageIntegrity.new()
	integrity_attr.hmac = hmac_digest
	msg.attributes.append(integrity_attr)
	_send_message(msg)

func _handle_message_response(res: StunMessage, req : StunMessage) -> void:
	super._handle_message_response(res, req)
	if res.type == StunMessage.Type.ALLOCATE_SUCCESS:
		# https://www.rfc-editor.org/rfc/rfc8656#section-7.3
		# TODO - check address family as per spec
		var _message_integrity_attr : StunAttributeMessageIntegrity = res.get_attribute(StunAttributeMessageIntegrity.TYPE)

		res.attributes.erase(_message_integrity_attr)
		var hmac_key : PackedByteArray = ("%s:%s:%s" % [_username, _realm, _password]).md5_buffer()
		var expected_digest : PackedByteArray = _crypto.hmac_digest(
			HashingContext.HASH_SHA1,
			hmac_key, 
			res.to_bytes(24))

		if expected_digest != _message_integrity_attr.hmac:
			push_error("received allocate success response with invalid message integrity, expected %s, got %s" % [expected_digest, _message_integrity_attr.hmac])
			_state = State.AllocationError
			return

		var _relayed_address_attr : StunAttributeXorRelayedAddress = res.get_attribute(StunAttributeXorRelayedAddress.TYPE)
		_relayed_transport_address = "%s:%d" % [ _relayed_address_attr.ip, _relayed_address_attr.port ]
		var _mapped_address_attr : StunAttributeXorMappedAddress = res.get_attribute(StunAttributeXorMappedAddress.TYPE)
		_server_reflexive_address = "%s:%d" % [ _mapped_address_attr.ip, _mapped_address_attr.port ]
		_remaining_lifetime = float(res.get_attribute(StunAttributeLifetime.TYPE).lifetime)
		_state = State.AllocationActive
		emit_signal("allocate_success", req, res)
	elif res.type == StunMessage.Type.ALLOCATE_ERROR:
		if !res.has_attribute(StunAttributeErrorCode.TYPE):
			push_error("received error response with no error attribute")
			return
		# https://www.rfc-editor.org/rfc/rfc5389#section-10.2.3
		# TODO: Check realm
		var error : StunAttributeErrorCode = res.get_attribute(StunAttributeErrorCode.TYPE)
		if error.code==401 && !req.has_attribute(StunAttributeUsername.TYPE):
			_send_allocate_auth_response(res)
		else:
			emit_signal("allocate_error", error, req, res)
