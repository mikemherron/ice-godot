extends RefCounted

class_name TurnClient

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)
signal fatal_error

func _init(ip: String, port: int) -> void:
	_peer.connect_to_host(ip, port)

func send_message(msg: Stun.Message) -> void:
	var bytes : PackedByteArray = msg.to_bytes()
	print("Sending bytes:", bytes.size(), " type:", msg.type)
	for i in range(bytes.size()):
		print("\n%03d [%04x]" % [i, bytes[i]])
	
	_txns[msg.txn_id.to_string()] = msg
	var err : int = _peer.put_packet(msg.to_bytes())
	if err != Error.OK:
		print("send message error:", err)

func poll() -> void:
	var count : int = _peer.get_available_packet_count()
	if count < 1:
		return
		
	var data : PackedByteArray = _peer.get_packet()
	var err : int = _peer.get_packet_error()
	if err != Error.OK:
		print("get packet error:", err)
		return
		
	if data == null:
		return
	if data.size() == 0:
		return
		
	print("Recieved bytes:", data.size())
	var response := Stun.Message.from_bytes(data, Stun.AttributeClasses)
	if response == null:
		emit_signal(fatal_error.get_name())
		return
	
	var txn_id_string := response.txn_id.to_string()
	var request: Stun.Message = _txns.get(txn_id_string)
	_txns.erase(txn_id_string)
	
	emit_signal("message_received", response, request)

func send_allocate() -> void:
	var msg = Stun.Message.new(Stun.MessageType.ALLOCATE, Stun.TxnId.new_random())
	send_message(msg)
