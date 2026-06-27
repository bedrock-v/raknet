module raknet

import net

fn test_dynamic_pong_data() {
	mut listener := listen('127.0.0.1:0') or { panic(err) }
	defer {
		listener.close() or {}
	}
	listener.set_pong_data('static pong'.bytes())
	listener.set_pong_data_func(dynamic_test_pong_data)
	assert ping(listener.addr()) or { panic(err) }.bytestr() == 'dynamic pong'
	listener.clear_pong_data_func()
	assert ping(listener.addr()) or { panic(err) }.bytestr() == 'static pong'
}

fn dynamic_test_pong_data(_ net.Addr) []u8 {
	return 'dynamic pong'.bytes()
}
