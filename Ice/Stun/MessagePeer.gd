extends RefCounted

class_name StunMessagePeer

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)
signal message_sent (request)

signal bytes_sent (data)
signal bytes_received (data)

func _init(ip: String, port: int):
	_peer.connect_to_host(ip, port)

func send_bytes(data: PackedByteArray) -> void:
	var err : int = _peer.put_packet(data)
	if err != Error.OK:
		return push_error("send bytes error", err)
	emit_signal("bytes_sent", data)

func send_message(msg: StunMessage) -> void:
	_txns[msg.txn_id.to_string()] = msg
	var err : int = _peer.put_packet(msg.to_bytes())
	if err != Error.OK:
		return push_error("send message error", err)
	emit_signal("message_sent", msg)

func poll() -> void:
	## TODO, should poll check for multiple packets?
	## TODO, probably just return message rather than signals now
	## TODO, this got clunky having to use stream peer buffer to 
	## 		   read in big endian to check for valid STUN message
	## 		   vs channel data - see if a way to read from packed byte
	##			 array as big endian (or even just write it)
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

	var buffer : StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data(data)
	buffer.seek(0)
	# header size is too small, definitely not STUN message
	if data.size() < StunMessage.HEADER_SIZE:
		emit_signal("bytes_received", buffer)
		return 
	
	buffer.seek(4)
	var cookie : int = buffer.get_32()
	buffer.seek(0)

	# Magic Cookie not as expected, definitely not STUN message
	if cookie != StunMessage.MAGIC_COOKIE:
		emit_signal("bytes_received", buffer)
		return

	# It looks like a STUN message...
	var response : StunMessage = StunMessage.from_buffer(buffer)
	if response == null:
		return
	
	var txn_id_string := response.txn_id.to_string()
	var request : StunMessage = _txns.get(txn_id_string)
	_txns.erase(txn_id_string)

	emit_signal("message_received", response, request)
