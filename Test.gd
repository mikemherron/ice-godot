extends Control

var turn_client: TurnClient
var turn_enet_proxy : TurnEnetProxy

const DEFAULT_ADDRESS = "35.230.153.84"
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
	
	# Set IP of channels to turn IP to speed up testing
	$Turn/Controls/Channels/PeerIpPort.text = DEFAULT_ADDRESS + ":"

func _on_allocate_success():
	$Turn/Controls/Channels/Channel.text = str(turn_client._next_channel)
	var peer = ENetMultiplayerPeer.new()
	var res : int = peer.create_server(turn_client._server_reflexive_address.port)
	if res != OK:
		print("Connection failed")
	else:
		print("Connected....?")
	multiplayer.multiplayer_peer = peer

func _on_allocate_error():
	print("ALLOCATE ERROR")

func _on_channel_data(channel : int, data : PackedByteArray):
	var channel_data_component = channel_data_scene.instantiate()
	_add_debug_message(channel_data_component)
	channel_data_component.set_data(channel, data)

func _debug_message_sent(message: StunMessage):
	var message_component = message_scene.instantiate()
	_add_debug_message(message_component)
	message_component.set_message(message)

func _debug_message_received(response: StunMessage, request: StunMessage):
	var message_component = message_scene.instantiate()
	_add_debug_message(message_component)
	message_component.set_message(response)
	
func _add_debug_message(control : Control) -> void:
	$Turn/Output/ScrollContainer/MessageContainer.add_child(control)
	$Turn/Output/ScrollContainer/MessageContainer.move_child(control, 0)
	
func _process(_delta: float) -> void:
	if turn_client==null:
		return
	turn_client.poll(_delta)
	if turn_enet_proxy!=null:
		turn_enet_proxy.poll()
	$Turn/Status/LocalPort.text = str(turn_client._peer._peer.get_local_port())
	$Turn/Status/Status.text = TurnClient.State.find_key(turn_client._state)
	if turn_client._relayed_transport_address!=null:
		$Turn/Status/RelayedIp.text = turn_client._relayed_transport_address.ip + ":" + str(turn_client._relayed_transport_address.port)
	if turn_client._server_reflexive_address!=null:
		$Turn/Status/ReflexiveIp.text = turn_client._server_reflexive_address.ip + ":" + str(turn_client._server_reflexive_address.port)
		$Turn/Status/RefreshTime.text = str(int(turn_client._remaining_lifetime)) + "s"

func _on_connect_button_down():
	turn_client = TurnClient.new(%Address.text, int(%Port.text), %Username.text, %Password.text, %Realm.text)
	turn_client._peer.message_received.connect(_debug_message_received)
	turn_client._peer.message_sent.connect(_debug_message_sent)
	turn_client.allocate_success.connect(_on_allocate_success)
	turn_client.allocate_error.connect(_on_allocate_error)
	turn_client.channel_bind_success.connect(_on_channel_bind_success)
	turn_client.channel_data.connect(_on_channel_data)
	
	turn_enet_proxy = TurnEnetProxy.new(turn_client)
	
	turn_client.send_allocate_request()
	%Connect.disabled = true

func _on_channel_bind_success(channel : int, ip : String, port : int):
	$Turn/Controls/Channels/Channel.text = str(channel+1)
	
	var new_channel : Label = Label.new()
	new_channel.text = str(channel)

	var new_channel_peer : Label = Label.new()
	new_channel_peer.text = ip + ":" + str(port)
	
	$Turn/Controls/Channels/Existing.add_child(new_channel)
	$Turn/Controls/Channels/Existing.add_child(new_channel_peer)
	$Turn/Controls/Channels/SendChannel.text = str(channel)
	
func _on_button_button_down() -> void:
	if turn_client==null:
		return
	var ip_parts : Array = $Turn/Controls/Channels/PeerIpPort.text.split(":",false,1)
	if ip_parts.size() != 2:
		return push_error("invalid ip, missing port?")
	turn_client.send_channel_bind_request(ip_parts[0], int(ip_parts[1]))

func _on_send_channel_data_button_down():
	turn_client.send_channel_data(int($Turn/Controls/Channels/SendChannel.text), $Turn/Controls/Channels/SendChannelData.text.to_utf8_buffer())

func _on_start_server_button_down():

	# Start the server bound to local host only - packets from
	# clients will be forwarded by the turn enet proxy
	var peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	peer.create_server(4433)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		OS.alert("Failed to start multiplayer server.")
		return
	
	print("Enet server started on port 4433")
	
	# Start the proxy providing the server port
	turn_enet_proxy.create_server_proxy(4433)
	
	multiplayer.multiplayer_peer = peer


func _on_start_client_button_down():
	if turn_client._active_channels.size() !=1:
		push_error("Can't create Turn ENet proxy, must have single TURN channel setup to server")
		return
		
	# The ENet client treats the local proxy socket as the "server". We need to 
	# specify a local port so that the proxy knows where to send the relayed
	# packets to
	var peer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 6677, 0, 0, 0, 7788)
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		OS.alert("Failed to start multiplayer server.")
		return

	# Start the proxy providing the pretend server port the client is 
	# expecting server packets from. Also provide the port the Enet client
	# is listening on so we know where to send incoming packets
	turn_enet_proxy.create_client_proxy(6677, 7788, turn_client._active_channels.keys()[0])
		
	multiplayer.multiplayer_peer = peer
	
