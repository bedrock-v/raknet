module raknet

import time

// new_test_packet_chan wraps new_packet_chan behind a pointer so the same
// instance can be shared with a spawned thread.
fn new_test_packet_chan(initial_cap int, max_cap int) &PacketChan {
	return &PacketChan{
		ch:        chan []u8{cap: initial_cap}
		cap:       initial_cap
		max_cap:   max_cap
		max_bytes: 1024 * 1024
	}
}

fn test_packet_chan_grows_under_backlog() {
	mut pc := new_test_packet_chan(2, 8)
	done := chan bool{cap: 1}
	spawn fn (mut pc PacketChan, done chan bool) {
		for i in 0 .. 5 {
			assert pc.send([u8(i)])
		}
		done <- true
	}(mut pc, done)
	select {
		_ := <-done {}
		100 * time.millisecond {
			assert false, 'send blocked while below max_cap'
		}
	}
	assert pc.cap > 2
	for i in 0 .. 5 {
		val := <-pc.ch
		assert val == [u8(i)]
	}
}

fn test_packet_chan_returns_false_once_max_cap_exhausted() {
	mut pc := new_test_packet_chan(1, 1)
	assert pc.send([u8(1)])
	result := chan bool{cap: 1}
	spawn fn (mut pc PacketChan, result chan bool) {
		result <- pc.send([u8(2)])
	}(mut pc, result)
	select {
		ok := <-result {
			assert ok == false
		}
		100 * time.millisecond {
			assert false, 'send blocked instead of returning false'
		}
	}
}

fn test_packet_chan_concurrent_grow_and_recv_does_not_deadlock() {
	total := 200
	mut pc := new_test_packet_chan(2, total + 1)
	sent_done := chan bool{cap: 1}
	spawn fn (mut pc PacketChan, total int, sent_done chan bool) {
		for i in 0 .. total {
			assert pc.send([u8(i % 256)])
		}
		sent_done <- true
	}(mut pc, total, sent_done)

	mut received := 0
	for received < total {
		ch := pc.rlock_chan()
		select {
			_ := <-ch {
				received++
			}
			200 * time.millisecond {
				pc.runlock()
				assert false, 'recv stalled - possible deadlock with grow()'
			}
		}
		pc.runlock()
	}
	assert received == total

	select {
		_ := <-sent_done {}
		200 * time.millisecond {
			assert false, 'sender never finished'
		}
	}
}

fn test_packet_chan_initial_cap_preserved_when_not_full() {
	mut pc := new_test_packet_chan(8, 64)
	for i in 0 .. 4 {
		assert pc.send([u8(i)])
	}
	assert pc.cap == 8
}

fn test_packet_chan_rejects_once_byte_budget_exhausted() {
	// Slot count (64) is generous on purpose, the byte budget (10 bytes)
	// must be what actually rejects here, proving queue size is bounded by
	// payload bytes. Not just packet count.
	mut pc := &PacketChan{
		ch:        chan []u8{cap: 4}
		cap:       4
		max_cap:   64
		max_bytes: 10
	}
	assert pc.send([u8(0), 0, 0, 0, 0]) // 5 bytes queued
	assert pc.send([u8(0), 0, 0, 0, 0]) // 10 bytes queued, at budget
	assert !pc.send([u8(1)]) // any further byte should be rejected

	// Delivering a packet frees its share of the byte budget.
	delivered := <-pc.ch
	pc.mark_delivered(delivered.len)
	assert pc.send([u8(1), 2, 3, 4, 5])
}
