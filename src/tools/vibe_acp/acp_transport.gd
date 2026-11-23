class_name AcpTransport
extends RefCounted
## Abstract byte transport for an ACP agent process.
## Implementations: PipeTransport (real vibe-acp process), fakes in tests.

func open() -> Error:
	return ERR_UNAVAILABLE

## Non-blocking read of whatever bytes are currently available.
func read_available() -> PackedByteArray:
	return PackedByteArray()

## Drain stderr so the child never blocks on a full pipe. Non-blocking.
func drain_stderr() -> PackedByteArray:
	return PackedByteArray()

func write_bytes(_data: PackedByteArray) -> Error:
	return ERR_UNAVAILABLE

func is_open() -> bool:
	return false

func exit_code() -> int:
	return -1

func close() -> void:
	pass
