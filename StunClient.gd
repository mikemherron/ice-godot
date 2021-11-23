extends Node

# STUN: https://datatracker.ietf.org/doc/html/rfc8489

enum MessageType {
	BINDING_REQUEST = 0x0001,
	BINDING_SUCCESS = 0x0101,
	BINDING_ERROR   = 0x0111,
}

enum AttributeType {
	MAPPED_ADDRESS           = 0x0001,
	USERNAME                 = 0x0006,
	MESSAGE_INTEGRITY        = 0x0008,
	ERROR_CODE               = 0x0009,
	UNKNOWN_ATTRIBUTES       = 0x000a,
	REALM                    = 0x0014,
	NONCE                    = 0x0015,
	MESSAGE_INTEGRITY_SHA256 = 0x001c,
	PASSWORD_ALGORITHM       = 0x001d,
	USERHASH                 = 0x001e,
	XOR_MAPPED_ADDRESS       = 0x0020,
}

const MAGIC_COOKIE = 0x2112a442

class Attribute:
	var type: int
	var data: Dictionary

class Message:
	var type: int
	var txn_id: String
	var attributes: Array
	
	func _init(_type: int, _txn_id: String) -> void:
		type = _type
		txn_id = _txn_id

var _peer := PacketPeerUDP.new()
var _txns: Dictionary

signal message_received (response, request)

func _init(ip: String, port: int) -> void:
	_peer.connect_to_host(ip, port)

func _new_txn_id() -> String:
	return "%x%x%x%x%x%x%x%x%x%x%x%x" % [
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
		randi() % 256,
	]

func send_message(msg: Message) -> void:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.resize(20)
	
	buffer.put_u16(msg.type)
	
	# @todo This is the size of the message after the header - put 0 for now
	buffer.put_u16(0)
	
	buffer.put_u32(MAGIC_COOKIE)
	
	# Write the transaction id.
	for i in range(12):
		buffer.put_u8(("0x" + msg.txn_id.substr(i * 2, 2)).hex_to_int())
	
	# @todo Actually write the attributes
	
	print (buffer.data_array)
	
	_txns[msg.txn_id] = msg
	_peer.put_packet(buffer.data_array)

func poll() -> void:
	while true:
		var data := _peer.get_packet()
		if not data:
			return
		print (data)
		
		var buffer := StreamPeerBuffer.new()
		buffer.big_endian = true
		buffer.put_data(data)
		buffer.seek(0)
		
		var type = buffer.get_u16()
		var size = buffer.get_u16()
		
		var magic_cookie = buffer.get_u32()
		if magic_cookie != MAGIC_COOKIE:
			push_error("Magic cookie doesn't match the expected value")
			continue
		
		var txn_id: String = ""
		for i in range(12):
			txn_id += "%x" % buffer.get_u8()
		print (txn_id)
		
		var request: Message = _txns.get(txn_id)
		if request == null:
			push_warning("Received response with unknown transaction id: %s" % txn_id)
		else:
			_txns.erase(txn_id)
		
		var response = Message.new(type, txn_id)
		
		# @todo Parse the attributes
		
		emit_signal("message_received", response, request)

func send_binding_request() -> void:
	var msg = Message.new(MessageType.BINDING_REQUEST, _new_txn_id())
	print (msg.txn_id)
	send_message(msg)
