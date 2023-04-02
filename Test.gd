extends Control

#var stun_client: StunClient
var turn_client: TurnClient

const DEFAULT_ADDRESS = "127.0.0.1"
const DEFAULT_PORT = "3478"
const DEFAULT_USERNAME = "username"
const DEFAULT_PASSWORD = "password"
const DEFAULT_REALM = "pion.ly"

var message_scene  = preload("res://Message.tscn")
var channel_data_scene = preload("res://ChannelData.tscn")

func _ready() -> void:
	%Address.text = DEFAULT_ADDRESS
	%Port.text = DEFAULT_PORT
	%Username.text = DEFAULT_USERNAME
	%Password.text = DEFAULT_PASSWORD
	%Realm.text = DEFAULT_REALM

func _on_allocate_success():
	$Controls/Channels/Channel.text = str(turn_client._next_channel)

func _on_allocate_error():
	print("ALLOCATE ERROR")

func _on_channel_data(channel : int, data : String):
	var channel_data_component = channel_data_scene.instantiate()
	$Output/ScrollContainer/MessageContainer.add_child(channel_data_component)
	$Output/ScrollContainer/MessageContainer.move_child(channel_data_component, 0)
	channel_data_component.set_data(channel, data)

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
	if turn_client==null:
		return
	turn_client.poll(_delta)
	$Status/Status.text = TurnClient.State.find_key(turn_client._state)
	if turn_client._relayed_transport_address!=null:
		$Status/RelayedIp.text = turn_client._relayed_transport_address.ip + ":" + str(turn_client._relayed_transport_address.port)
	if turn_client._server_reflexive_address!=null:
		$Status/ReflexiveIp.text = turn_client._server_reflexive_address.ip + ":" + str(turn_client._server_reflexive_address.port)
		$Status/RefreshTime.text = str(int(turn_client._remaining_lifetime)) + "s"

func _on_connect_button_down():
	turn_client = TurnClient.new(%Address.text, int(%Port.text), %Username.text, %Password.text, %Realm.text)
	turn_client._peer.message_received.connect(_debug_message_received)
	turn_client._peer.message_sent.connect(_debug_message_sent)
	turn_client.allocate_success.connect(_on_allocate_success)
	turn_client.allocate_error.connect(_on_allocate_error)
	turn_client.channel_bind_success.connect(_on_channel_bind_success)
	turn_client.channel_data.connect(_on_channel_data)
	
	turn_client.send_allocate_request()
	%Connect.disabled = true

func _on_channel_bind_success(channel : int, ip : String, port : int):
	$Controls/Channels/Channel.text = str(channel+1)
	
	var new_channel : Label = Label.new()
	new_channel.text = str(channel)

	var new_channel_peer : Label = Label.new()
	new_channel_peer.text = ip + ":" + str(port)
	
	$Controls/Channels/Existing.add_child(new_channel)
	$Controls/Channels/Existing.add_child(new_channel_peer)

	$Controls/Channels/SendChannel.text = str(channel)
	
func _on_button_button_down() -> void:
	if turn_client==null:
		return
	var ip_parts : Array = $Controls/Channels/PeerIpPort.text.split(":",false,1)
	if ip_parts.size() != 2:
		return push_error("invalid ip, missing port?")
	turn_client.send_channel_bind_request(ip_parts[0], int(ip_parts[1]))

func _on_send_channel_data_button_down():
	turn_client.send_channel_data(int($Controls/Channels/SendChannel.text), $Controls/Channels/SendChannelData.text.to_utf8_buffer())
