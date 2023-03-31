extends RefCounted

class_name StunMessagePeer

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)
signal message_sent (request)

func _init(ip: String, port: int):
	_peer.connect_to_host(ip, port)

func send_message(msg: StunMessage) -> void:
	_txns[msg.txn_id.to_string()] = msg
	var err : int = _peer.put_packet(msg.to_bytes())
	if err != Error.OK:
		return push_error("send message error", err)
	emit_signal("message_sent", msg)

func poll() -> void:
	## TODO, should poll check for multiple packets?
	## TODO, probably just return message rather than signals now
	var count : int = _peer.get_available_packet_count()
	if count < 1:
		return
		
	var data : PackedByteArray = _peer.get_packet()

	var err : int = _peer.get_packet_error()
	if err != Error.OK:
		push_error("get packet error", err)
		return
		
	if data == null || data.size() == 0:
		return
	
	var response := StunMessage.from_bytes(data)
	if response == null:
		return
	
	var txn_id_string := response.txn_id.to_string()
	var request : StunMessage = _txns.get(txn_id_string)
	_txns.erase(txn_id_string)

	emit_signal("message_received", response, request)