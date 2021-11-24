extends Node2D

const StunClient = preload("res://StunClient.gd")

var stun_client: StunClient

func _ready() -> void:
	stun_client = StunClient.new('69.164.203.66', 443)
	#stun_client = StunClient.new('2600:3c00::f03c:92ff:fe8c:017a', 443)
	
	# stun.l.google.com
	#stun_client = StunClient.new('173.194.196.127', 19302)
	#stun_client = StunClient.new('2607:f8b0:4001:c0f::7f', 19302)
	
	# global.stun.twilio.com (no IPv6?)
	#stun_client = StunClient.new('34.203.250.120', 3478)
	
	stun_client.connect("message_received", self, "_on_stun_client_message_received")
	stun_client.send_binding_request()

func _on_stun_client_message_received(response: StunClient.Message, request: StunClient.Message):
	print ("REQUEST:\n")
	print (request)
	print ("\n--\n\nRESPONSE:\n")
	print (response)
	
	# Test round-tripping the response data.
	print ("\n--\n\nWRITE AND LOAD AGAIN:\n")
	var bytes = response.to_bytes()
	var response2 = StunClient.Message.from_bytes(bytes, stun_client.attribute_classes)
	print (response2)

func _process(delta: float) -> void:
	stun_client.poll()

