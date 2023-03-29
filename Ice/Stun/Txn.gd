extends RefCounted

class_name StunTxnId

var bytes := []

static func from_string(s: String) -> StunTxnId:
  var bytes := []
  for i in range(12):
    bytes.append(("0x" + s.substr(i * 2, 2)).hex_to_int())
  return StunTxnId.new(bytes)

static func new_random() -> StunTxnId:
  var bytes := []
  for i in range(12):
    bytes.append(randi() % 256)
  return StunTxnId.new(bytes)

static func read_from_buffer(buffer: StreamPeerBuffer) -> StunTxnId:
  var bytes := []
  for i in range(12):
    bytes.append(buffer.get_u8())
  return StunTxnId.new(bytes)
  
func _init(_bytes: Array) -> void:
  bytes = _bytes

func _to_string() -> String:
  return "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % bytes

func slice_to_int(start: int, end: int) -> int:
  var slice := bytes.slice(start, end)
  var count := slice.size()
  if count > 8:
    return 0
  var shift := (count - 1) * 8
  var value := 0
  for i in range(count):
    if shift > 0:
      value = value | (slice[i] << shift)
    else:
      value = value | slice[i]
    shift -= 8
  return value