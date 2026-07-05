module raknet

import net
import time

fn test_error_log_close_drain() {
	events := chan string{cap: 16}
	log_fn := fn [events] (msg string, fields map[string]string) {
		events <- msg or {}
	}
	mut listener := listen('127.0.0.1:0') or { panic(err) }
	defer {
		listener.close() or {}
	}
	dialer := Dialer{
		error_log: log_fn
	}
	mut conn := dialer.dial(listener.addr()) or { panic(err) }
	conn.close() or { panic(err) }

	mut got_start := false
	mut got_complete := false
	for _ in 0 .. 20 {
		select {
			msg := <-events {
				if msg == 'close drain start' {
					got_start = true
				}
				if msg == 'close drain complete' {
					got_complete = true
				}
			}
			50 * time.millisecond {}
		}
		if got_start && got_complete {
			break
		}
	}
	assert got_start
	assert got_complete
}

fn test_error_log_blocked_read() {
	events := chan string{cap: 16}
	log_fn := fn [events] (msg string, fields map[string]string) {
		events <- msg or {}
	}
	mut listener := ListenConfig{
		error_log: log_fn
	}.listen('127.0.0.1:0') or { panic(err) }
	defer {
		listener.close() or {}
	}
	addr := net.resolve_addrs_fuzzy('127.0.0.1:12345', .udp) or { panic(err) }[0]
	listener.block(addr)
	ping_timeout(listener.addr(), 200 * time.millisecond) or {}

	mut got := false
	for _ in 0 .. 20 {
		select {
			msg := <-events {
				if msg == 'blocked read' {
					got = true
				}
			}
			50 * time.millisecond {}
		}
		if got {
			break
		}
	}
	assert got
}
