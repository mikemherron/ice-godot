extends Control

#var stun_client: StunClient
var turn_client: TurnClient

const DEFAULT_ADDRESS = "127.0.0.1"
const DEFAULT_PORT = "3478"
const DEFAULT_USERNAME = "username"
const DEFAULT_PASSWORD = "password"
const DEFAULT_REALM = "pion.ly"

var message_scene  = preload("res://Message.tscn")

func _ready() -> void:
	%Address.text = DEFAULT_ADDRESS
	%Port.text = DEFAULT_PORT
	%Username.text = DEFAULT_USERNAME
	%Password.text = DEFAULT_PASSWORD
	%Realm.text = DEFAULT_REALM

func _on_allocate_success():
	print("ALLOCATE SUCCESS")

func _on_allocate_error():
	print("ALLOCATE ERROR")

func _debug_message_sent(message: StunMessage):
	print ("MESSAGE SENT:\n")
	print (message)
	
	var message_component = message_scene.instantiate()
	$Output/ScrollContainer/MessageContainer.add_child(message_component)
	$Output/ScrollContainer/MessageContainer.move_child(message_component, 0)
	message_component.set_message(message)

func _debug_message_received(response: StunMessage, request: StunMessage):
	print ("REQUEST:\n")
	print (request)
	print ("\n--\n\nRESPONSE:\n")
	print (response)
	var message_component = message_scene.instantiate()
	$Output/ScrollContainer/MessageContainer.add_child(message_component)
	$Output/ScrollContainer/MessageContainer.move_child(message_component, 0)
	message_component.set_message(response)
	
func _process(_delta: float) -> void:
	if turn_client!=null:
		turn_client.poll(_delta)

func _on_connect_button_down():
	turn_client = TurnClient.new(%Address.text, int(%Port.text), %Username.text, %Password.text, %Realm.text)
	turn_client._peer.message_received.connect(_debug_message_received)
	turn_client._peer.message_sent.connect(_debug_message_sent)
	turn_client.allocate_success.connect(_on_allocate_success)
	turn_client.allocate_error.connect(_on_allocate_error)
	turn_client.send_allocate_request()
	%Connect.disabled = true
