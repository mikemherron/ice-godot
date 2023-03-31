extends StunAttributeAddress

class_name StunAttributeXorAddress

func _init(type: int, name: String):
	super(type, name)

func read_from_buffer(buffer: StreamPeerBuffer, size: int, msg: StunMessage) -> void:
	family = buffer.get_u16()
	port = buffer.get_u16() ^ (StunMessage.MAGIC_COOKIE >> 16)
	if family == Family.IPV4:
		var raw_ip = buffer.get_u32() ^ StunMessage.MAGIC_COOKIE
		ip = "%d.%d.%d.%d" % [
			(raw_ip >> 24) & 0xff,
			(raw_ip >> 16) & 0xff,
			(raw_ip >> 8) & 0xff,
			raw_ip & 0xff,
		]
	elif family == Family.IPV6:
		var high_mask = ((StunMessage.MAGIC_COOKIE << 32) | msg.txn_id.slice_to_int(0, 3))
		var low_mask = msg.txn_id.slice_to_int(4, 11)
		var high_value = buffer.get_u64() ^ high_mask
		var low_value = buffer.get_u64() ^ low_mask
		ip = "%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x" % [
			(high_value >> 48) & 0xffff,
			(high_value >> 32) & 0xffff,
			(high_value >> 16) & 0xffff,
			high_value & 0xffff,
			(low_value >> 48) & 0xffff,
			(low_value >> 32) & 0xffff,
			(low_value >> 16) & 0xffff,
			low_value & 0xffff,
		]

func write_to_buffer(buffer: StreamPeerBuffer, msg: StunMessage) -> void:
	_write_type_and_size(buffer, msg)
	buffer.put_u16(family)
	buffer.put_u16(port ^ (StunMessage.MAGIC_COOKIE >> 16))
	if family == Family.IPV4:
		var ip_value := _parse_ipv4()
		buffer.put_u32(ip_value ^ StunMessage.MAGIC_COOKIE)
	elif family == Family.IPV6:
		var ip_value := _parse_ipv6()
		var high_mask = ((StunMessage.MAGIC_COOKIE << 32) | msg.txn_id.slice_to_int(0, 3))
		var low_mask = msg.txn_id.slice_to_int(4, 11)
		buffer.put_u64(ip_value[0] ^ high_mask)
		buffer.put_u64(ip_value[0] ^ low_mask)
