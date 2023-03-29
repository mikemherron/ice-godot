extends StunClient

class_name TurnClient

signal allocate_success (request: StunMessage, response : StunMessage)
signal allocate_error (request: StunMessage, response : StunMessage)

var _username : String 
var _password : String 
var _realm : String 

var _crypto : Crypto

func _init(ip: String, port: int, username : String, password : String, realm : String):
	super(ip, port)
	_username = username
	_password = password
	_realm = realm
	_crypto = Crypto.new()

func send_allocate_request() -> void:
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
	
	msg.attributes.append(StunAttributeMessageIntegrity.new(hmac_digest))
	_send_message(msg)

func _handle_message_response(res: StunMessage, req : StunMessage) -> void:
	super._handle_message_response(res, req)
	if res.type == StunMessage.Type.ALLOCATE_SUCCESS:
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
