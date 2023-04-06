extends RefCounted

class_name TurnClient

## TODO
#  More generic mechanism for retrying, limitnig and timing out requests (allocate, refresh)?
#  Handle nonce updating on refresh
#  Time out allocation requests / retry requests
#  Just make this a node to avoid clients having to call poll?
#  Proper error handling as per - https://www.rfc-editor.org/rfc/rfc8656#section-7.4
#  Change allocaiton error signal to include self error code (so can indicate non-response errors)
#  Support lifetime specification in allocate
#  Investigate why PION error strings are not coming back in error responses

const CHANNEL_DATA_HEADER_SIZE = 4
const REFRESH_THRESHOLD = 60

signal allocate_success
signal allocate_error
signal channel_bind_success
signal channel_data 

enum State {
	Idle, 
	AllocationRequested, 
	AllocationActive, 
	AllocationError
}

var _username : String 
var _password : String 
var _realm : String 
var _nonce : String

var _hmac_key : PackedByteArray

var _state : int = State.Idle

var _relayed_transport_address : StunAttributeAddress 
var _server_reflexive_address : StunAttributeAddress
var _remaining_lifetime : float

var _active_channels : Dictionary = {}

var _peer : StunMessagePeer
var _next_channel : int = StunAttributeChannelNumber.CHANNEL_MIN

enum ProxyMode {
	Client, Server	
}

var _proxy_mode : int
var _proxy_socket : PacketPeerUDP
# When in proxy server mode Maps ENet peer numbers to TURN channels
var _proxy_enet_peer_mapping : Dictionary = {}
var _proxy_client_sockets : Dictionary = {}

const ProxyClientsStartPort = 70000

func _init(ip: String, port: int, username : String, password : String, realm : String):
	_peer = StunMessagePeer.new(ip, port)
	_peer.connect("message_received", self._handle_message_received)
	_peer.connect("bytes_received", self._handle_bytes_received)
	_username = username
	_password = password
	_realm = realm
	
	_hmac_key = ("%s:%s:%s" % [_username, _realm, _password]).md5_buffer()

func poll(delta : float) -> void:
	_peer.poll()
	if _state != State.AllocationActive:
		return
		
	# TODO buffer/retry requests as per STUN RFC so we don't send a load
	# of requests until we get a response
	_remaining_lifetime -= delta
	if _remaining_lifetime < REFRESH_THRESHOLD:
		_send_refresh()
		
	# A message on the proxy socket means ENet is trying to send a packet 
	# somewhere...
	if _proxy_mode == ProxyMode.Server:
		# If we are a server, go through each of the client proxy sockets 
		# and check if they have a message
		for channel in _proxy_client_sockets:
			var client_proxy : PacketPeerUDP = _proxy_client_sockets[channel]
			if client_proxy.get_available_packet_count() > 0:
				var packet : PackedByteArray = client_proxy.get_packet()
				if _proxy_socket.get_packet_error()!=OK:
					return
				print("Client on channel %d has packet, forwarding" % [channel])
				# The server has sent a packet to this client proxy - forward
				# it on to the actual client through the correct TURN channel
				send_channel_data(channel, packet)
	elif _proxy_socket!=null && _proxy_socket.get_available_packet_count() > 0:
		var packet : PackedByteArray = _proxy_socket.get_packet()
		if _proxy_socket.get_packet_error()!=OK:
			return
		# If we are a client, the packet will always be destined for the server
		if _proxy_mode == ProxyMode.Client:
			# Assume that if we are a client only a single channel for the 
			# server should have been created
			if _active_channels.size() > 1:
				print("Unable to forward packet as more than 1 channel")
				return 
			print("forwarding ENet packet on to server as channel data")
			var server_channel : int = _active_channels.keys()[0]
			send_channel_data(server_channel, packet)
		
		# If we are a server, we need to figure out what client the packet
		# is destined for and then look up the correct channel - could we 
		# peek inside and get the peer ID?
		elif _proxy_mode == ProxyMode.Server:
			pass
#			print ("forwarding packet from Enet server to client..")
#			var possible_peer_number : int = packet.decode_u16(0)
#			print("- possible ENet peer number: %d" % [possible_peer_number])
#			if !_proxy_enet_peer_mapping.has(possible_peer_number):
#				print("- couldn't find channel mapping :(")
#			var client_channel : int = _proxy_enet_peer_mapping[possible_peer_number]
#			print("- sending on channel: %d" % [_proxy_enet_peer_mapping[possible_peer_number]])
#			send_channel_data(client_channel, packet)
	
func send_allocate_request() -> void:
	if _state != State.Idle:
		return push_error("allocate request already sent")
	_state = State.AllocationRequested
	_peer.send_message(StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random()))

# TODO: just assuming IPv4 for now
func send_channel_bind_request(peer_ip : String, peer_port :int) -> void:
	if _state!= State.AllocationActive:
		return push_error("channel bind request sent before allocation active")
	var msg := StunMessage.new(StunMessage.Type.CHANNEL_BIND_REQUEST, StunTxnId.new_random())
	msg.attributes.append(StunAttributeRealm.new(_realm))
	msg.attributes.append(StunAttributeNonce.new(_nonce))
	msg.attributes.append(StunAttributeUsername.new(_username))
	msg.attributes.append(StunAttributeChannelNumber.new(_next_channel))
	msg.attributes.append(StunAttributeXorPeerAddress.new(peer_ip, peer_port))

	var msg_integrity_attr := StunAttributeMessageIntegrity.for_message(_hmac_key, msg)
	msg.attributes.append(msg_integrity_attr)

	_peer.send_message(msg)

func send_channel_data(channel_number : int, data : PackedByteArray) -> void:
	if _state!= State.AllocationActive:
		return push_error("channel data sent before allocation active")
	if !_active_channels.has(channel_number):
		return push_error("channel data sent for unknown channel")
	
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_16(channel_number)
	buffer.put_16(data.size())
	# "Over UDP, the padding is not required but MAY be included." - maybe do this?
	buffer.put_data(data)
	_peer.send_bytes(buffer.get_data_array())
	
func set_server_proxy_socket(proxy_socket : PacketPeerUDP) -> void:
	_proxy_mode = ProxyMode.Server
	_proxy_socket = proxy_socket
	
func set_client_proxy_socket(proxy_socket : PacketPeerUDP) -> void:
	_proxy_mode = ProxyMode.Client
	_proxy_socket = proxy_socket

func _send_refresh() -> void:
	var msg := StunMessage.new(StunMessage.Type.REFRESH_REQUEST, StunTxnId.new_random())
	msg.attributes.append(StunAttributeRealm.new(_realm))
	msg.attributes.append(StunAttributeNonce.new(_nonce))
	msg.attributes.append(StunAttributeUsername.new(_username))
	
	var msg_integrity_attr := StunAttributeMessageIntegrity.for_message(_hmac_key, msg)
	msg.attributes.append(msg_integrity_attr)

	_peer.send_message(msg)

func _handle_message_received(res: StunMessage, req : StunMessage) -> void:
	match res.type:
		StunMessage.Type.ALLOCATE_SUCCESS:
			_handle_allocate_success(res)
		StunMessage.Type.ALLOCATE_ERROR:
			_handle_allocate_error(res, req)
		StunMessage.Type.REFRESH_SUCCESS:
			_handle_refresh_success(res)
		StunMessage.Type.CHANNEL_BIND_SUCCESS:
			_handle_channel_bind_success(req, res)
			
func _handle_allocate_error(res: StunMessage, req : StunMessage) -> void:	
	if !res.has_attribute(StunAttributeErrorCode.TYPE):
		_state = State.AllocationError
		return push_error("allocation error response with no error attribute")

	# We already sent the username and still got an error, so can't recover
	if req.has_attribute(StunAttributeUsername.TYPE):
		_state = State.AllocationError
		return push_error("allocation auth error response")
	
	# For now, can't do anything about errors other than unauthenticated
	var error : StunAttributeErrorCode = res.get_attribute(StunAttributeErrorCode.TYPE)
	if error.code!=401:
		_state = State.AllocationError
		return push_error("allocation error code ", error.code)
	
	var realm_attr : StunAttributeRealm = res.get_attribute(StunAttributeRealm.TYPE)
	if realm_attr == null || realm_attr.value != _realm:
		_state = State.AllocationError
		return push_error("allocation error response with invalid realm")

	# Resend allocate with auth details and nonce from response
	var nonce_attr : StunAttributeNonce = res.get_attribute(StunAttributeNonce.TYPE)
	_nonce = nonce_attr.value

	var msg = StunMessage.new(StunMessage.Type.ALLOCATE_REQUEST, StunTxnId.new_random())
	msg.attributes.append(realm_attr)
	msg.attributes.append(nonce_attr)
	msg.attributes.append(StunAttributeUsername.new(_username))
	msg.attributes.append(StunAttributeRequestedTransport.new())
	
	var mng_integrity_attr := StunAttributeMessageIntegrity.for_message(_hmac_key, msg)
	msg.attributes.append(mng_integrity_attr)
	
	_peer.send_message(msg)

func _handle_allocate_success(res: StunMessage) -> void:
	if !res.has_attribute(StunAttributeMessageIntegrity.TYPE):
		_state = State.AllocationError
		print("received allocate success response with no message integrity")
		return

	var msg_integrity_attr : StunAttributeMessageIntegrity = res.get_attribute(StunAttributeMessageIntegrity.TYPE)
	if !msg_integrity_attr.verify(_hmac_key, res):
		_state = State.AllocationError
		print("received allocate success response with invalid message integrity")
		return
		
	_relayed_transport_address = res.get_attribute(StunAttributeXorRelayedAddress.TYPE)
	_server_reflexive_address = res.get_attribute(StunAttributeXorMappedAddress.TYPE)
	_remaining_lifetime = float(res.get_attribute(StunAttributeLifetime.TYPE).lifetime)

	_state = State.AllocationActive
	emit_signal("allocate_success")

func _handle_refresh_success(res: StunMessage) -> void:
	var msg_integrity_attr : StunAttributeMessageIntegrity = res.get_attribute(StunAttributeMessageIntegrity.TYPE)
	if !msg_integrity_attr.verify(_hmac_key, res):
		_state = State.AllocationError
		print("received refresh success response with invalid message integrity")
		return
		
	_remaining_lifetime = float(res.get_attribute(StunAttributeLifetime.TYPE).lifetime)

func _handle_channel_bind_success(req : StunMessage, res: StunMessage) -> void:	
	var msg_integrity_attr : StunAttributeMessageIntegrity = res.get_attribute(StunAttributeMessageIntegrity.TYPE)
	if !msg_integrity_attr.verify(_hmac_key, res):
		print("received channel bind success response with invalid message integrity")
		return
	
	var channel : int = req.get_attribute(StunAttributeChannelNumber.TYPE).channel
	var peer : StunAttributeAddress = req.get_attribute(StunAttributeXorPeerAddress.TYPE)
	_active_channels[channel] = "%s:%d" % [peer.ip, peer.port]
	
	emit_signal("channel_bind_success", channel, peer.ip, peer.port)
	_next_channel+=1
	
func _handle_bytes_received(buffer : StreamPeerBuffer) -> void:
	if buffer.get_available_bytes() < CHANNEL_DATA_HEADER_SIZE:
		print("received data smaller than channel data")
		return
	
	var channel : int = buffer.get_16()
	if !_active_channels.has(channel):
		print("received channel data for unknown channel")
		return
		
	var length : int = buffer.get_16()
	var get_data_res : Array = buffer.get_data(length)
	if get_data_res[0]!=OK:
		print("error getting data from channel data packet:", get_data_res[0])
		return
		
	var raw_data : PackedByteArray = get_data_res[1]

	print("Channel data message received of length ", length)
	
	## If there is a proxy socket active, send on the raw packet data
	if _proxy_socket!=null:
		print("sending packet on to proxy")
		# TODO if we are the server, we'll need to inspect this and extract
		# the ENet peer ID so we can map it back to the channel in the poll 
		# method?
		if _proxy_mode == ProxyMode.Server:
			print("forwarding received packet from TURN to to ENet server")
			# Set up a new proxy socket for this client
			if !_proxy_client_sockets.has(channel):
				print("- this client does not have a proxy socket, making a new one")
				var socket : PacketPeerUDP = PacketPeerUDP.new()
				socket.connect_to_host("127.0.0.1", 4433)
				_proxy_client_sockets[channel] = socket
			_proxy_client_sockets[channel].put_packet(raw_data)
		elif _proxy_mode == ProxyMode.Client:
			print("forwarding received packet from TURN to ENet client")
			_proxy_socket.put_packet(raw_data)
			
			#var possible_peer_number : int = raw_data.decode_u16(0)
#			var possible_peer_number : int = buffer.get_u16()
#			print("Possible ENet peer number received from server: %d" % [possible_peer_number])
#			if !_proxy_enet_peer_mapping.has(possible_peer_number):
#				print("- mapped to channel: %d" % [channel])
#				_proxy_enet_peer_mapping[possible_peer_number] = channel
#				_proxy_socket.put_packet(raw_data)
	
	emit_signal("channel_data", channel, raw_data)
	
