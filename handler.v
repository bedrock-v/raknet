module raknet

import message

fn (mut c Conn) handle_packet(data []u8, reliability Reliability) ! {
	if data.len == 0 {
		return
	}
	match data[0] {
		message.id_connection_request {
			c.handle_connection_request(data[1..])!
		}
		message.id_connection_request_accepted {
			c.handle_connection_request_accepted(data[1..])!
		}
		message.id_new_incoming_connection {
			c.handle_new_incoming_connection(data[1..])!
		}
		message.id_disconnect_notification {
			c.close_immediately()
		}
		message.id_connected_ping {
			c.handle_connected_ping(data, reliability)!
		}
		message.id_connected_pong {
			c.handle_connected_pong(data, reliability)!
		}
		message.id_detect_lost_connections {
			c.send_keepalive_ping()!
		}
		else {
			c.packets <- data.clone()
		}
	}
}

fn (mut c Conn) handle_connection_request(data []u8) ! {
	if !c.is_server {
		return
	}
	req := message.decode_connection_request(data)!
	addr := addr_port_from_string(c.remote.str()) or { message.AddrPort{} }
	c.write(message.ConnectionRequestAccepted{
		client_address: addr
		ping_time:      req.request_time
		pong_time:      timestamp()
	}.encode())!
}

fn (mut c Conn) handle_connection_request_accepted(data []u8) ! {
	if c.is_server {
		return
	}
	accepted := message.decode_connection_request_accepted(data)!
	c.write(message.NewIncomingConnection{
		server_address: accepted.client_address
		ping_time:      accepted.pong_time
		pong_time:      timestamp()
	}.encode())!
	if c.mark_connected_once() {
		c.connected <- true or {}
	}
}

fn (mut c Conn) handle_new_incoming_connection(data []u8) ! {
	if !c.is_server {
		return
	}
	_ := message.decode_new_incoming_connection(data)!
	if c.mark_connected_once() {
		c.connected <- true or {}
		if c.listener != unsafe { nil } {
			c.listener.queue_incoming(c)
		}
	}
}

fn (mut c Conn) handle_connected_ping(data []u8, reliability Reliability) ! {
	if data.len == 9 {
		ping_packet := message.decode_connected_ping(data[1..])!
		c.write_with_reliability(message.ConnectedPong{
			ping_time: ping_packet.ping_time
			pong_time: timestamp()
		}.encode(), .unreliable)!
	} else if reliability != .reliable_ordered {
		return error('malformed connected ping')
	} else {
		c.packets <- data.clone()
	}
}

fn (mut c Conn) handle_connected_pong(data []u8, reliability Reliability) ! {
	if data.len == 17 {
		_ := message.decode_connected_pong(data[1..])!
	} else if reliability != .reliable_ordered {
		return error('malformed connected pong')
	} else {
		c.packets <- data.clone()
	}
}
