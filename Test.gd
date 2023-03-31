extends Node2D

#var stun_client: StunClient
var turn_client: TurnClient

const USERNAME = "username"
const PASSWORD = "password"
const REALM = "pion.ly"

func _ready() -> void:
	turn_client = TurnClient.new('127.0.0.1', 3478, USERNAME, PASSWORD, REALM)
	#stun_client = StunClient.new('127.0.0.1', 3478)
	#stun_client = StunClient.new('2600:3c00::f03c:92ff:fe8c:017a', 443)
	
	# stun.l.google.com
	#stun_client = StunClient.new('173.194.196.127', 19302)
	#stun_client = StunClient.new('2607:f8b0:4001:c0f::7f', 19302)
	
	# global.stun.twilio.com (no IPv6?)
	#stun_client = StunClient.new('34.203.250.120', 3478)
	
	turn_client._peer.message_received.connect(_debug_message_received)
	turn_client._peer.message_sent.connect(_debug_message_sent)
	turn_client.allocate_success.connect(_on_allocate_success)
	turn_client.allocate_error.connect(_on_allocate_error)
	turn_client.send_allocate_request()

func _on_allocate_success():
	print("ALLOCATE SUCCESS")

func _on_allocate_error():
	print("ALLOCATE ERROR")

func _debug_message_sent(message: StunMessage):
	print ("MESSAGE SENT:\n")
	print (message)
		
func _debug_message_received(response: StunMessage, request: StunMessage):
	print ("REQUEST:\n")
	print (request)
	print ("\n--\n\nRESPONSE:\n")
	print (response)
	
	# # Test round-tripping the response data.
	# print ("\n--\n\nWRITE AND LOAD AGAIN:\n")
	# var bytes = response.to_bytes()
	# var response2 = Stun.Message.from_bytes(bytes, Stun.AttributeClasses)
	# print (response2)
	
func _process(_delta: float) -> void:
	turn_client.poll()
	
# func check_message(msg : Stun.Message) -> void:
# 	var bytes : PackedByteArray = msg.to_bytes()
# 	var buffer := StreamPeerBuffer.new()
# 	buffer.big_endian = true
# 	buffer.put_data(bytes)
# 	buffer.seek(2)
		
# 	print("reported size: %d, actual size: %d" % [buffer.get_u16(), bytes.size()])	
# 	var round_tripped_msg : Stun.Message = Stun.Message.from_bytes(bytes)
	
