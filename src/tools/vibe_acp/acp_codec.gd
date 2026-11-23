class_name AcpCodec
extends RefCounted
## ACP framing codec: newline-delimited JSON-RPC 2.0 messages.
## vibe-acp reads one JSON object per line from stdin and writes one per line
## to stdout (verified against vibe-acp 3.1.4).

## Encode a message Dictionary to wire bytes (JSON + "\n").
static func encode_message(msg: Dictionary) -> PackedByteArray:
	return (JSON.stringify(msg) + "\n").to_utf8_buffer()

## Incremental line splitter: feed raw bytes, get complete lines back.
class LineBuffer:
	var _buf := PackedByteArray()

	func push(data: PackedByteArray) -> Array:
		_buf.append_array(data)
		var lines: Array = []
		while true:
			var nl := _buf.find(0x0A)
			if nl < 0:
				break
			var line := _buf.slice(0, nl).get_string_from_utf8().strip_edges()
			_buf = _buf.slice(nl + 1)
			if not line.is_empty():
				lines.append(line)
		return lines

	func pending_bytes() -> int:
		return _buf.size()
