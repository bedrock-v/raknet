module raknet

import net
import time

fn test_pending_ack_dedupe() {
	mut conn := &Conn{}
	conn.queue_ack(Uint24(1))
	conn.queue_ack(Uint24(1))
	conn.queue_nack([Uint24(2), Uint24(2)])
	assert conn.pending_ack == [Uint24(1)]
	assert conn.pending_nack == [Uint24(2)]
}

fn test_read_timeout() {
	mut conn := &Conn{
		packets:     chan []u8{cap: 1}
		closed_chan: chan bool{cap: 1}
	}
	conn.set_read_timeout(10 * time.millisecond)
	conn.read_packet() or {
		assert err.code() == err_code_read_deadline_exceeded
		assert err.msg().contains('deadline')
		return
	}
	assert false, 'read_packet should fail after read timeout'
}

fn test_read_deadline() {
	mut conn := &Conn{
		packets:     chan []u8{cap: 1}
		closed_chan: chan bool{cap: 1}
	}
	conn.set_read_deadline(time.now().add(-time.millisecond))
	mut buf := []u8{len: 8}
	conn.read(mut buf) or {
		assert err.code() == err_code_read_deadline_exceeded
		assert err.msg().contains('deadline')
		return
	}
	assert false, 'read should fail after read deadline'
}

fn test_deadline_can_be_cleared() {
	mut conn := &Conn{
		mtu:         max_mtu_size
		packets:     chan []u8{cap: 1}
		closed_chan: chan bool{cap: 1}
	}
	conn.set_deadline(time.now().add(-time.millisecond))
	mut failed := false
	conn.write([u8(1)]) or {
		failed = true
		assert err.code() == err_code_write_deadline_exceeded
		assert err.msg().contains('deadline')
	}
	assert failed
	conn.set_deadline(time.Time{})
	assert conn.write([u8(1)]) or { panic(err) } == 1
}

fn test_write_deadline() {
	mut conn := &Conn{
		mtu: max_mtu_size
	}
	conn.set_write_deadline(time.now().add(-time.millisecond))
	conn.write([u8(1)]) or {
		assert err.code() == err_code_write_deadline_exceeded
		assert err.msg().contains('deadline')
		return
	}
	assert false, 'write should fail after write deadline'
}

fn test_write_timeout() {
	mut conn := &Conn{
		mtu: max_mtu_size
	}
	conn.set_write_timeout(10 * time.millisecond)
	time.sleep(20 * time.millisecond)
	conn.write([u8(1)]) or {
		assert err.code() == err_code_write_deadline_exceeded
		assert err.msg().contains('deadline')
		return
	}
	assert false, 'write should fail after write timeout'
}

fn test_lifecycle_tuning() {
	mut conn := &Conn{}
	conn.set_idle_timeout(123 * time.millisecond)
	conn.set_keepalive_interval(456 * time.millisecond)
	conn.set_read_timeout(net.infinite_timeout)
	assert conn.idle_timeout == 123 * time.millisecond
	assert conn.keepalive_interval == 456 * time.millisecond
	wait, has_timeout := conn.read_wait_timeout(time.now())
	assert wait == 0
	assert !has_timeout
}
