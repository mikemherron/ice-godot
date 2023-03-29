extends RefCounted

class_name StunClient

# STUN: https://datatracker.ietf.org/doc/html/rfc8489

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal bind_success (address : StunAttributeXorMappedAddress, request: StunMessage, response : StunMessage)
signal bind_error (request: StunMessage, response : StunMessage)
signal message_received (response, request)
signal message_sent (request)

func _init(ip: String, port: int):
	_peer.connect_to_host(ip, port)

func send_binding_request() -> void:
	var msg = StunMessage.new(StunMessage.Type.BINDING_REQUEST, StunTxnId.new_random())
	_send_message(msg)

func _send_message(msg: StunMessage) -> void:
	_txns[msg.txn_id.to_string()] = msg
	var err : int = _peer.put_packet(msg.to_bytes())
	emit_signal("message_sent", msg)
	if err != Error.OK:
		push_error("send message error:", err)

func _handle_message_response(res: StunMessage, req : StunMessage) -> void:
	emit_signal("message_received", res, req)
	if res.type == StunMessage.Type.BINDING_SUCCESS:
		emit_signal("bind_success", res.get_attribute(StunAttributeXorMappedAddress.TYPE), res, req)
	elif res.type == StunMessage.Type.BINDING_ERROR:
		emit_signal("bind_error", res.get_attribute(StunAttributeXorMappedAddress.TYPE), res, req)

func poll() -> void:
	var count : int = _peer.get_available_packet_count()
	if count < 1:
		return
		
	var data : PackedByteArray = _peer.get_packet()
	var err : int = _peer.get_packet_error()
	if err != Error.OK:
		push_error("get packet error:", err)
		return
		
	if data == null:
		return
	if data.size() == 0:
		return
	
	var response := StunMessage.from_bytes(data)
	if response == null:
		return
	
	var txn_id_string := response.txn_id.to_string()
	var request : StunMessage = _txns.get(txn_id_string)
	_txns.erase(txn_id_string)

	_handle_message_response(response, request)