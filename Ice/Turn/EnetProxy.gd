extends RefCounted

class_name TurnEnetProxy

enum Mode {
	None, 
	Client, 
	Server	
}

var _turn_client : TurnClient

var _mode : int = Mode.None

var _enet_server_port : int
var _enet_client_local_port : int
var _turn_server_channel : int

var _server_socket : PacketPeerUDP
var _client_sockets : Dictionary

func _init(turn_client : TurnClient):
	_turn_client = turn_client
	_turn_client.connect("channel_data", _on_channel_data)

func create_server_proxy(enet_server_port : int) -> void:
	_mode = Mode.Server
	_enet_server_port = enet_server_port
	_client_sockets = {}

func create_client_proxy(enet_server_port : int, enet_client_local_port : int, turn_server_channel : int) -> void:
	_mode = Mode.Client
	_enet_client_local_port = enet_client_local_port
	_enet_server_port = enet_server_port
	_turn_server_channel = turn_server_channel
	# Set up the server proxy socket. It will receive messages from ENet, and 
	# then transport them through the TURN relay in the poll method. When messages
	# come in from the TURN relay, they will be sent to ENet from this method
	_server_socket = PacketPeerUDP.new()
	_server_socket.bind(enet_server_port, "127.0.0.1")
	_server_socket.set_dest_address("127.0.0.1", _enet_client_local_port)

func poll() -> void:
	# A message on the proxy socket(s) means ENet is trying to send a packet 
	# somewhere. Pick it up here and forward it through the Relay.
	
	# If we are a server, go through each of the client proxy sockets 
	# and check if they have a message
	if _mode == Mode.Server:
		for channel in _client_sockets:
			var client_socket : PacketPeerUDP = _client_sockets[channel]
			if client_socket.get_available_packet_count() == 0:
				continue
			var packet : PackedByteArray = client_socket.get_packet()
			if client_socket.get_packet_error()!=OK:
				continue
			print("TurnENetProxy: Client on channel %d has packet, forwarding" % [channel])
			# The server has sent a packet to this client proxy - forward
			# it on to the actual client through the correct TURN channel
			_turn_client.send_channel_data(channel, packet)
				
	# If we are a client, the packet will always be destined for the server
	elif _mode==Mode.Client && _server_socket.get_available_packet_count() > 0:
		var packet : PackedByteArray = _server_socket.get_packet()
		if _server_socket.get_packet_error()!=OK:
			return
		_turn_client.send_channel_data(_turn_server_channel, packet)

func _on_channel_data(channel : int, packet : PackedByteArray) -> void:
	# Channel data has been recieved from the TURN relay, forward it on to ENet
	# through the proxy socket
	if _mode == Mode.Server:
		# If we are a server and this is the first time we've received 
		# a packet on this channel, create a proxy socket
		if !_client_sockets.has(channel):
			print("TurnENetProxy: Client does not have a proxy socket, making a new one")
			var socket : PacketPeerUDP = PacketPeerUDP.new()
			socket.connect_to_host("127.0.0.1", _enet_server_port)
			_client_sockets[channel] = socket
		# Send the packet from the clients proxy socket to the server
		print("TurnENetProxy: Forwarding received packet from TURN to to ENet server")
		_client_sockets[channel].put_packet(packet)
	
	# If we are a client, forward the data on to the ENet client using 
	# the proxy server socket
	elif _mode == Mode.Client:
		print("TurnENetProxy: Forwarding received packet from TURN to ENet client")
		_server_socket.put_packet(packet)
