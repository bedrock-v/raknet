module raknet

import time

pub const protocol_version = u8(11)
pub const min_mtu_size = u16(400)
pub const max_mtu_size = u16(1492)
pub const err_code_connection_closed = 10_001
pub const err_code_listener_closed = 10_002
pub const err_code_read_deadline_exceeded = 10_003
pub const err_code_write_deadline_exceeded = 10_004
pub const err_code_connection_timed_out = 10_005
pub const err_code_not_supported = 10_006
pub const err_code_protocol_mismatch = 10_007
pub const err_code_invalid_packet = 10_008
pub const err_connection_closed = error_with_code('connection closed', err_code_connection_closed)
pub const err_listener_closed = error_with_code('listener closed', err_code_listener_closed)
pub const err_read_deadline_exceeded = error_with_code('read deadline exceeded',
	err_code_read_deadline_exceeded)
pub const err_write_deadline_exceeded = error_with_code('write deadline exceeded',
	err_code_write_deadline_exceeded)
pub const err_connection_timed_out = error_with_code('connection timed out',
	err_code_connection_timed_out)
pub const err_not_supported = error_with_code('not supported', err_code_not_supported)
pub const err_invalid_packet = error_with_code('invalid packet', err_code_invalid_packet)
const max_window_size = 2048
const max_split_count = 512
const max_concurrent_splits = 16
const close_drain_timeout = time.second

fn clamp_mtu(mtu u16, min_mtu u16) u16 {
	if mtu == 0 || mtu > max_mtu_size {
		return max_mtu_size
	}
	if mtu < min_mtu {
		return min_mtu
	}
	return mtu
}
