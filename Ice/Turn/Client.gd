extends RefCounted

class_name TurnClient

## TODO
#  Time out allocation requests / retry requests
#  Change allocaiton error signal to include self error code (so can indicate non-response errors)
#  Refresh requests
#  Support lifetime specification in allocate
#  Investigate why PION error strings are not coming back in error responses

signal allocate_success
signal allocate_error

enum State {
	Idle, 
	AllocationRequested, 
	AllocationActive, 
	AllocationError
}

var _username : String 
var _password : String 
var _realm : String 

var _hmac_key : PackedByteArray

var _state : int = State.Idle

var _relayed_transport_address : StunAttributeAddress 
var _server_reflexive_address : StunAttributeAddress
var _remaining_lifetime : float

var _peer : StunMessagePeer

func _init(ip: String, port: int, username : String, password : String, realm : String):
	_peer = StunMessagePeer.new(ip, port)
	_peer.connect("message_received", self._handle_message_received)
	
	_username = username
	_password = password
	_realm = realm
	
	_hmac_key = ("%s:%s:%s" % [_username, _realm, _password]).md5_buffer()

func poll() -> void:
	_peer.poll()

func send_allocate_request() -> void:
	if _state != State.Idle:
		return push_error("allocate request already sent")
	_state = State.AllocationRequested
	_peer.send_message(StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random()))

func _handle_message_received(res: StunMessage, req : StunMessage) -> void:
	match res.type:
		StunMessage.Type.ALLOCATE_SUCCESS:
			_handle_allocate_success(res)
		StunMessage.Type.ALLOCATE_ERROR:
			_handle_allocate_error(res, req)

func _handle_allocate_error(res: StunMessage, req : StunMessage) -> void:	
	if !res.has_attribute(StunAttributeErrorCode.TYPE):
		_state = State.AllocationError
		return push_error("allocation error response with no error attribute")

	# We already sent the username and still got an error, so can't recover
	if req.has_attribute(StunAttributeUsername.TYPE):
		_state = State.AllocationError
		return push_error("allocation auth error response")
	
	# For now, can't do anything about errors other than unauthenticated
	var error : StunAttributeErrorCode = res.get_attribute(StunAttributeErrorCode.TYPE)
	if error.code!=401:
		_state = State.AllocationError
		return push_error("allocation error code ", error.code)
	
	var realm_attr : StunAttributeRealm = res.get_attribute(StunAttributeRealm.TYPE)
	if realm_attr == null || realm_attr.value != _realm:
		_state = State.AllocationError
		return push_error("allocation error response with invalid realm")

	# Resend allocate with auth details and nonce from response
	var msg = StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random())
	msg.attributes.append(realm_attr)
	msg.attributes.append(res.get_attribute(StunAttributeNonce.TYPE))
	msg.attributes.append(StunAttributeUsername.new(_username))
	msg.attributes.append(StunAttributeRequestedTransport.new())
	
	var mng_integrity_attr := StunAttributeMessageIntegrity.for_message(_hmac_key, msg)
	msg.attributes.append(mng_integrity_attr)
	
	_peer.send_message(msg)

func _handle_allocate_success(res: StunMessage) -> void:
	if !res.has_attribute(StunAttributeMessageIntegrity.TYPE):
		_state = State.AllocationError
		return push_error("received allocate success response with no message integrity")

	var msg_integrity_attr : StunAttributeMessageIntegrity = res.get_attribute(StunAttributeMessageIntegrity.TYPE)
	if !msg_integrity_attr.verify(_hmac_key, res):
		_state = State.AllocationError
		return push_error("received allocate success response with invalid message integrity")
		
	_relayed_transport_address = res.get_attribute(StunAttributeXorRelayedAddress.TYPE)
	_server_reflexive_address = res.get_attribute(StunAttributeXorMappedAddress.TYPE)
	_remaining_lifetime = float(res.get_attribute(StunAttributeLifetime.TYPE).lifetime)

	_state = State.AllocationActive
	emit_signal("allocate_success")
