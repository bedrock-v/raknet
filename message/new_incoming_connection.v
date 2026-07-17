module message

pub struct NewIncomingConnection {
pub:
	server_address AddrPort
	ping_time      i64
	pong_time      i64
}

pub fn (pk NewIncomingConnection) encode() []u8 {
	addr_size := sizeof_addr(pk.server_address)
	system_addr_size := sizeof_addr4 * 20
	mut b := []u8{len: 1 + addr_size + system_addr_size + 16}
	b[0] = id_new_incoming_connection
	mut offset := 1 + put_addr(mut b[1..], pk.server_address)
	for _ in 0 .. 20 {
		offset += put_addr(mut b[offset..], AddrPort{})
	}
	put_u64(mut b, offset, u64(pk.ping_time))
	put_u64(mut b, offset + 8, u64(pk.pong_time))
	return b
}

pub fn decode_new_incoming_connection(data []u8) !NewIncomingConnection {
	addr, mut offset := read_addr(data)!
	for data.len - offset >= sizeof_addr4 + 16 {
		_, n := read_addr(data[offset..])!
		offset += n
	}
	if data.len < offset + 16 {
		return error('unexpected eof reading new incoming connection')
	}
	return NewIncomingConnection{
		server_address: addr
		ping_time:      i64(read_u64(data, offset))
		pong_time:      i64(read_u64(data, offset + 8))
	}
}
