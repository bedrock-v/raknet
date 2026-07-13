module raknet

import sync
import sync.stdatomic

const packet_chan_initial_cap = 256
const packet_chan_max_cap = 4096
const packet_chan_max_bytes = 32 * 1024 * 1024

// PacketChan is a growable, bounded queue of fully reassembled inbound
// application packets.
//
// A packet count cap alone bounds the number of queue slots, not the
// memory behind them: a fully reassembled application packet can be up to
// max_split_count fragments large, so max_cap slots full of near maximum
// packets could still add up to a very large amount of per connection
// memory. max_bytes bounds the total size of currently queued payloads
// (tracked in queued_bytes) independently of how many packets that is,
// whichever limit is hit first closes the connection.
//
// send() must only ever be called from a single thread for a given instance.
struct PacketChan {
mut:
	resize_mutex &sync.RwMutex = sync.new_rwmutex()
	ch           chan []u8
	cap          int
	max_cap      int
	max_bytes    int
	queued_bytes i64
}

fn new_packet_chan(initial_cap int, max_cap int, max_bytes int) PacketChan {
	mut effective_max := max_cap
	if effective_max < initial_cap {
		effective_max = initial_cap
	}
	return PacketChan{
		ch:        chan []u8{cap: initial_cap}
		cap:       initial_cap
		max_cap:   effective_max
		max_bytes: max_bytes
	}
}

// send enqueues val without blocking while below max_cap (grows instead)
// and max_bytes. Once either limit is reached and no more room is
// available, returns false. Caller must treat false as a fatal,
// unrecoverable backlog for this connection (see Conn.push_packet).
fn (mut p PacketChan) send(val []u8) bool {
	if stdatomic.load_i64(&p.queued_bytes) + i64(val.len) > i64(p.max_bytes) {
		return false
	}
	if p.ch.len >= p.cap {
		if p.cap >= p.max_cap {
			select {
				p.ch <- val {
					stdatomic.add_i64(&p.queued_bytes, val.len)
					return true
				}
				else {
					return false
				}
			}
		}
		p.grow()
	}
	p.ch <- val
	stdatomic.add_i64(&p.queued_bytes, val.len)
	return true
}

// mark_delivered must be called by the consumer once for every packet
// received off rlock_chan()'s channel with that packet's length.
fn (mut p PacketChan) mark_delivered(n int) {
	stdatomic.add_i64(&p.queued_bytes, -n)
}

// grow doubles the channel capacity up to max_cap and moves all queued
// packets into the new channel.
//
// It takes an exclusive lock while replacing the channel. This is safe because
// grow() is only called when the current channel is full. Any reader holding a
// read lock therefore has a packet ready to receive, so it'll finish and
// release the lock instead of waiting indefinitely on an empty channel.
fn (mut p PacketChan) grow() {
	new_cap := if p.cap * 2 < p.max_cap { p.cap * 2 } else { p.max_cap }
	if new_cap <= p.cap {
		return
	}
	p.resize_mutex.lock()
	defer {
		p.resize_mutex.unlock()
	}
	old := p.ch
	mut grown := chan []u8{cap: new_cap}
	for old.len > 0 {
		val := <-old
		grown <- val
	}
	p.ch = grown
	p.cap = new_cap
}

// rlock_chan pins the current channel against a concurrent grow() and
// returns it so the caller can combine it in a `select` with other arms
// (closed_chan, a timeout). Caller must call runlock() exactly once after the select resolves.
fn (mut p PacketChan) rlock_chan() chan []u8 {
	p.resize_mutex.rlock()
	return p.ch
}

fn (mut p PacketChan) runlock() {
	p.resize_mutex.runlock()
}
