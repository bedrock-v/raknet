module raknet

import net

const transient_udp_error_codes = [
	net.err_connection_refused.code(),
	111, // ECONNREFUSED
	113, // EHOSTUNREACH
	101, // ENETUNREACH
	104, // ECONNRESET
	103, // ECONNABORTED
	10061, // WSAECONNREFUSED
	10065, // WSAEHOSTUNREACH
	10051, // WSAENETUNREACH
	10054, // WSAECONNRESET
	10053, // WSAECONNABORTED
]

fn is_transient_udp_read_error(err IError) bool {
	if err.code() in transient_udp_error_codes {
		return true
	}
	msg := err.msg().to_lower()
	return msg.contains('connection refused') || msg.contains('host unreachable')
		|| msg.contains('network unreachable') || msg.contains('connection reset')
		|| msg.contains('connection aborted') || msg.contains('econnrefused')
		|| msg.contains('ehostunreach') || msg.contains('enetunreach') || msg.contains('econnreset')
		|| msg.contains('econnaborted')
}
