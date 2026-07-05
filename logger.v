module raknet

// LogFunc is an optional diagnostic hook. msg is a short, stable event name
// (e.g. "read from", "blocked read", "transient udp error", "close drain timeout")
// and fields carries event-specific context such as the remote address or underlying error.
pub type LogFunc = fn (msg string, fields map[string]string)

fn log_event(f LogFunc, msg string, fields map[string]string) {
	if voidptr(f) == unsafe { nil } {
		return
	}
	f(msg, fields)
}
