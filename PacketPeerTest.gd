extends Control

var peer1 : PacketPeerUDP
var peer2 : PacketPeerUDP
var peer3 : PacketPeerUDP
var peer4 : PacketPeerUDP

var delay : float = 2

func _ready() -> void:
	## Use connect_to_host so peer1 gets automatically assigned
	## a local port
	peer1 = PacketPeerUDP.new()
	if peer1.connect_to_host("127.0.0.1", 1111):
		push_error("Can't connect peer1")
		return
	
	log_msg("peer1 listening for packets from 127.0.0.1:%d, using local port: %d" % [1111, peer1.get_local_port()])
	
	## Create peer2 with bind and use the same port as peer1
	## is listening on...surely this should fail?
	peer2 = PacketPeerUDP.new()
	var err : int = peer2.bind(peer1.get_local_port())
	if err != OK:
		push_error("Can't bind peer2:", str(err))
		return

	## It doesn't fail! We have 2 peers listening on the same
	## local port :\
	log_msg("peer2 listening for packets from anywhere, using local port: %d" % [peer2.get_local_port()])

	## Create another peer and send some packets to this port
	## ...who will recieve them?
	peer3 = PacketPeerUDP.new()
	## Bind to 1111 so peer1 can recive packets from peer3
	peer3.bind(1111)
	peer3.set_dest_address("127.0.0.1", peer1.get_local_port())
	log_msg("peer3 set up to send packets to 127.0.0.1:%d, from port %d" % [peer1.get_local_port(), 1111])
	
	## Peer 4 will send packets to the same port, but from a 
	## different source port - this should mean they all go 
	## to peer2..?
	peer4 = PacketPeerUDP.new()
	peer4.bind(2222)
	peer4.set_dest_address("127.0.0.1", peer1.get_local_port())
	log_msg("peer4 set up to send packets to 127.0.0.1:%d, from port %d" % [peer1.get_local_port(), 2222])

func _process(delta):
	delay -= delta
	if delay > 0:
		return
		
	log_msg("")
	log_msg("#######################################")
	
	delay = 2
	if peer3.put_packet("from peer 3".to_utf8_buffer()) != OK:
		push_error("peer 3 unable to send packet")
	else:
		log_msg("peer3 sent packet")
	if peer4.put_packet("from peer 4".to_utf8_buffer()) != OK:
		push_error("unable to send packet")
	else:
		log_msg("peer4 sent packet")

	## While peer1 is open, it is the only socket that can receive any packets
	## to this port, and only from the specified host/port. If other packets come in
	## on this port but from a different host port, they seem to be ignored until
	## peer1 is closed, then peer 2 can see them
	##
	## This has some implications for how turn will work - it will be possible for
	## ENet multiplayer to bind to the same local port, but it won't receive
	## any packets until the TURN socket is closed. One solution could be for the
	## TURN client to close it's connection, and then continue TURN management 
	## (refreshes mainly) using the connection created by ENET multiplayer.
	if peer1.get_available_packet_count() > 0:
		log_msg("peer1 recieved packet: %s" % [peer1.get_packet().get_string_from_utf8()])
	else:
		log_msg("peer1 no packets available")
	
	if peer2.get_available_packet_count() > 0:
		log_msg("peer2 recieved packet: %s" % [peer2.get_packet().get_string_from_utf8()])
	else:
		log_msg("peer2 no packets available")
		
	log_msg("#######################################")
		
func log_msg(msg : String) -> void:
	%Log.text = "[" + Time.get_time_string_from_system() + "] " + msg + "\n" + %Log.text

func _on_button_down():
	$Button.disabled = true
	peer1.close()
