extends Node2D

const StunClient = preload("res://StunClient.gd")

var stun_client: StunClient

func _ready() -> void:
	stun_client = StunClient.new('69.164.203.66', 443)
	stun_client.connect("message_received", self, "_on_stun_client_message_received")
	stun_client.send_binding_request()

func _on_stun_client_message_received(response: StunClient.Message, request: StunClient.Message):
	if response.type == StunClient.MessageType.BINDING_ERROR:
		print ("BINDING ERROR")
	elif response.type == StunClient.MessageType.BINDING_SUCCESS:
		print ("BUNDING SUCCESS")
	else:
		print ("Other message type: %s" % response.type)
	
	print ("Attributes:")
	print (response.attributes)

func _process(delta: float) -> void:
	stun_client.poll()

