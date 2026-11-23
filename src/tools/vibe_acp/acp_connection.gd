class_name AcpConnection
extends RefCounted
## Owns a transport and turns raw bytes into parsed JSON-RPC messages.
## Poll-based (call poll() regularly, e.g. from _process); fully testable
## by injecting a fake AcpTransport.

signal message_received(msg: Dictionary)

var transport: AcpTransport
var _buffer: AcpCodec.LineBuffer
var _next_id := 1
var last_stderr := ""

func _init(p_transport: AcpTransport = null) -> void:
	transport = p_transport
	_buffer = AcpCodec.LineBuffer.new()

func open() -> Error:
	if transport == null:
		return ERR_UNAVAILABLE
	return transport.open()

func is_open() -> bool:
	return transport != null and transport.is_open()

func exit_code() -> int:
	return -1 if transport == null else transport.exit_code()

## Send one JSON-RPC message. Returns OK or an Error code.
func send(msg: Dictionary) -> Error:
	if transport == null or not transport.is_open():
		return ERR_UNAVAILABLE
	return transport.write_bytes(AcpCodec.encode_message(msg))

## Non-blocking: drain available bytes, parse complete lines, return messages.
func poll() -> Array:
	var msgs: Array = []
	if transport == null or not transport.is_open():
		return msgs
	var raw := transport.read_available()
	if raw.size() > 0:
		for line in _buffer.push(raw):
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				msgs.append(parsed)
				message_received.emit(parsed)
	var err_bytes := transport.drain_stderr()
	if err_bytes.size() > 0:
		last_stderr = err_bytes.get_string_from_utf8()
	return msgs

func next_request_id() -> int:
	var id := _next_id
	_next_id += 1
	return id

func close() -> void:
	if transport != null:
		transport.close()
