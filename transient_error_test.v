module raknet

import net

fn test_transient_udp_errors() {
	assert is_transient_udp_read_error(net.err_connection_refused)
	assert is_transient_udp_read_error(error_with_code('net: socket error: 113', 113))
	assert is_transient_udp_read_error(error('read udp: connection reset by peer'))
	assert !is_transient_udp_read_error(net.err_timed_out)
	assert !is_transient_udp_read_error(error('some other error'))
}
