extends Node2D

#var stun_client: StunClient
var turn_client: TurnClient

const USERNAME = "username"
const PASSWORD = "password"

var crypto : Crypto = Crypto.new()
var sent_username : bool = false

func _ready() -> void:
	turn_client = TurnClient.new('127.0.0.1', 3478)
	#stun_client = StunClient.new('127.0.0.1', 3478)
	#stun_client = StunClient.new('2600:3c00::f03c:92ff:fe8c:017a', 443)
	
	# stun.l.google.com
	#stun_client = StunClient.new('173.194.196.127', 19302)
	#stun_client = StunClient.new('2607:f8b0:4001:c0f::7f', 19302)
	
	# global.stun.twilio.com (no IPv6?)
	#stun_client = StunClient.new('34.203.250.120', 3478)
	
	turn_client.message_received.connect(_on_stun_message_received)
	turn_client.fatal_error.connect(func():get_tree().quit())
	turn_client.send_allocate()

func _on_stun_message_received(response: Stun.Message, request: Stun.Message):
	print ("REQUEST:\n")
	print (request)
	print ("\n--\n\nRESPONSE:\n")
	print (response)
	
	# Test round-tripping the response data.
	print ("\n--\n\nWRITE AND LOAD AGAIN:\n")
	var bytes = response.to_bytes()
	var response2 = Stun.Message.from_bytes(bytes, Stun.AttributeClasses)
	print (response2)
	
	if response.type == Stun.MessageType.ALLOCATE_ERROR:
		var error : Stun.ErrorCodeAttribute = response.get_attribute(Stun.ErrorCodeAttribute.TYPE) as Stun.ErrorCodeAttribute
		if error==null:
			print("received error response with no error attribute")
			return
		
		# https://www.rfc-editor.org/rfc/rfc5389#section-10.2.3
		# 10.2.3.  Receiving a Response
		# If the response is an error response with an error code of 401
		# (Unauthorized), the client SHOULD retry the request with a new
		# transaction.  This request MUST contain a USERNAME, determined by the
		# client as the appropriate username for the REALM from the error
		# response.  The request MUST contain the REALM, copied from the error
		# response.  The request MUST contain the NONCE, copied from the error
		# response.  The request MUST contain the MESSAGE-INTEGRITY attribute,
		# computed using the password associated with the username in the
		# USERNAME attribute.  The client MUST NOT perform this retry if it is
		# not changing the USERNAME or REALM or its associated password, from
		# the previous attempt.
		if error.code==401 && !sent_username:
			var realm : Stun.RealmAttribute = response.get_attribute(Stun.RealmAttribute.TYPE) as Stun.RealmAttribute
			var nonce : Stun.NonceAttribute = response.get_attribute(Stun.NonceAttribute.TYPE) as Stun.NonceAttribute
			var username : Stun.UsernameAttribute = Stun.UsernameAttribute.new(USERNAME)
				
			
			# Based on the rules above, the hash used to construct MESSAGE-
			# INTEGRITY includes the length field from the STUN message header.
			# Prior to performing the hash, the MESSAGE-INTEGRITY attribute MUST be
			# inserted into the message (with dummy content).  The length MUST then
			# be set to point to the length of the message up to, and including,
			# the MESSAGE-INTEGRITY attribute itself, but excluding any attributes
			# after it.  Once the computation is performed, the value of the
			# MESSAGE-INTEGRITY attribute can be filled in, and the value of the
			# length in the STUN header can be set to its correct value -- the
			# length of the entire message.  Similarly, when validating the
			# MESSAGE-INTEGRITY, the length field should be adjusted to point to
			# the end of the MESSAGE-INTEGRITY attribute prior to calculating the
			# HMAC.  Such adjustment is necessary when attributes, such as
			# FINGERPRINT, appear after MESSAGE-INTEGRITY.
			
			var msg = Stun.Message.new(Stun.MessageType.ALLOCATE, Stun.TxnId.new_random(), 
				[
					realm,
					nonce,
					username,
					Stun.RequestedTransportAttribute.new()
				]
			)
			
			var msgBytes : PackedByteArray = msg.to_bytes(24)
			
			var key : PackedByteArray = (USERNAME + ":" + realm.realm + ":" + PASSWORD).md5_buffer()
#			print("key:")
#			for b in key:
#				print("[%d]" % [b])
				
			var actualHash : PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA1, key, msgBytes)
			var messageIntegrity = Stun.MessageIntegrityAttribute.new(actualHash)
			msg.attributes.append(messageIntegrity)
			sent_username = true
			#check_message(msg)
			turn_client.send_message(msg)
			#turn_client.send_allocate()
			
		##if response.has

func _process(_delta: float) -> void:
	turn_client.poll()
	
func check_message(msg : Stun.Message) -> void:
	var bytes : PackedByteArray = msg.to_bytes()
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data(bytes)
	buffer.seek(2)
		
	print("reported size: %d, actual size: %d" % [buffer.get_u16(), bytes.size()])	
	var round_tripped_msg : Stun.Message = Stun.Message.from_bytes(bytes)
	
