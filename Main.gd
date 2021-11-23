extends Node2D

const StunClient = preload("res://StunClient.gd")

var stun_client: StunClient

func _ready() -> void:
	stun_client = StunClient.new('69.164.203.66', 443)
	
	#print(stun_client._new_txn_id())
	
	
	stun_client.send_binding_request()

func _process(delta: float) -> void:
	stun_client.poll()

