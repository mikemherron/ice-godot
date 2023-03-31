extends RefCounted

class_name StunClient

var _peer : StunMessagePeer

signal bind_success (address : StunAttributeAddress)
signal bind_error

func _init(ip: String, port: int):
	_peer = StunMessagePeer.new(ip, port)
	_peer.connect("message_received", self._handle_message_received)

func send_binding_request() -> void:
	var msg = StunMessage.new(StunMessage.Type.BINDING_REQUEST, StunTxnId.new_random())
	_peer.send_message(msg)

func _handle_message_received(res: StunMessage, req : StunMessage) -> void:
	match res.type:
		StunMessage.Type.BINDING_SUCCESS:
			emit_signal("bind_success", res.get_attribute(StunAttributeXorMappedAddress.TYPE))
		StunMessage.Type.BINDING_ERROR:
			emit_signal("bind_error")

func poll() -> void:
	_peer.poll()