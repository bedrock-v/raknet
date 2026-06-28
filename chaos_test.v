module raknet

import time

// Sends 10 reliable packets, drops every 3rd one, then drives a manual resend.
// Verifies all 10 packets are eventually delivered to the receiver.
fn test_packet_loss_recovery_via_resend() {
	mut sender := &Conn{
		mtu:    max_mtu_size
		resend: new_resend_map()
	}
	count := 10
	for i in 0 .. count {
		// 0x40+ avoids all connected control message IDs (0x00–0x15)
		sender.write([u8(0x40 + u8(i))])!
	}
	assert sender.sent_raw.len == count

	mut receiver := &Conn{
		mtu:          max_mtu_size
		packets:      chan []u8{cap: 16}
		win:          new_datagram_window()
		packet_queue: new_packet_queue()
		resend:       new_resend_map()
	}

	// deliver all except indices 2, 5, 8
	for i, raw in sender.sent_raw {
		if i % 3 == 2 {
			continue
		}
		receiver.receive(raw)!
	}
	receiver.flush_acknowledgements()!

	// route only ACKs back to sender so it knows which seqs arrived
	for raw in receiver.sent_raw {
		if raw[0] & bit_flag_ack != 0 {
			sender.handle_ack(raw[1..])!
		}
	}

	// after RTT timeout the 3 un-acked seqs must be retransmitted
	before := sender.sent_raw.len
	sender.check_resend(time.now().add(500 * time.millisecond))!
	resent_count := sender.sent_raw.len - before
	assert resent_count == 3

	for i in before .. sender.sent_raw.len {
		receiver.receive(sender.sent_raw[i])!
	}

	mut got := []u8{}
	for _ in 0 .. count {
		select {
			data := <-receiver.packets {
				assert data.len == 1
				got << data[0]
			}
			100 * time.millisecond {
				assert false, 'timed out waiting for packet'
			}
		}
	}
	got.sort()
	assert got == []u8{len: count, init: u8(0x40 + index)}
}

// Delivers all packets to the receiver but never routes the ACKs back.
// The sender must retransmit every packet after RTT delay.
fn test_ack_loss_triggers_full_resend() {
	mut sender := &Conn{
		mtu:    max_mtu_size
		resend: new_resend_map()
	}
	for i in 0 .. 4 {
		sender.write([u8(i)])!
	}
	assert sender.sent_raw.len == 4

	mut receiver := &Conn{
		mtu:          max_mtu_size
		packets:      chan []u8{cap: 8}
		win:          new_datagram_window()
		packet_queue: new_packet_queue()
		resend:       new_resend_map()
	}
	for raw in sender.sent_raw {
		receiver.receive(raw)!
	}
	// intentionally drop all ACKs — do not flush to sender

	before_resend := sender.sent_raw.len
	sender.check_resend(time.now().add(500 * time.millisecond))!
	assert sender.sent_raw.len - before_resend == 4

	// receiver deduplicates via datagram window; packet count must not grow
	before_pkts := receiver.packets.len
	for i in before_resend .. sender.sent_raw.len {
		receiver.receive(sender.sent_raw[i])!
	}
	assert receiver.packets.len == before_pkts
}

// Drops the middle fragment of a split payload, lets the receiver generate a
// NACK, routes it back to the sender, and verifies the full payload reassembles.
fn test_split_nack_recovery_delivers_full_payload() {
	payload := []u8{len: 3000, init: u8(index % 251)}
	mut sender := &Conn{
		mtu:    max_mtu_size
		resend: new_resend_map()
	}
	sender.write(payload)!
	assert sender.sent_raw.len == 3

	mut receiver := &Conn{
		mtu:          max_mtu_size
		packets:      chan []u8{cap: 4}
		win:          new_datagram_window()
		packet_queue: new_packet_queue()
		resend:       new_resend_map()
	}

	receiver.receive(sender.sent_raw[0])!
	receiver.receive(sender.sent_raw[2])!

	missing := receiver.win.missing(50 * time.millisecond, time.now().add(200 * time.millisecond))
	receiver.queue_nack(missing)
	receiver.flush_acknowledgements()!

	mut found_nack := false
	for raw in receiver.sent_raw {
		if raw[0] & bit_flag_nack != 0 {
			sender.handle_nack(raw[1..])!
			found_nack = true
		}
	}
	assert found_nack, 'expected at least one NACK from receiver'

	// sender retransmitted; deliver the new datagram (last entry in sent_raw)
	assert sender.sent_raw.len == 4
	receiver.receive(sender.sent_raw[3])!

	select {
		got := <-receiver.packets {
			assert got == payload
		}
		100 * time.millisecond {
			assert false, 'split payload not reassembled after NACK recovery'
		}
	}
}

// 5 packets arrive in reverse order; the ordered queue must hold them until
// index 0 arrives, then flush all 5 in correct order.
fn test_ordered_delivery_reversed_arrival() {
	mut conn := &Conn{
		packets:      chan []u8{cap: 8}
		packet_queue: new_packet_queue()
	}
	n := 5
	for i := n - 1; i >= 0; i-- {
		// 0x40+ avoids all connected control message IDs (0x00–0x15)
		conn.receive_packet(Packet{
			reliability: .reliable_ordered
			order_index: Uint24(u32(i))
			content:     [u8(0x40 + i)]
		})!
		if i > 0 {
			assert conn.packets.len == 0
		}
	}
	for i in 0 .. n {
		select {
			data := <-conn.packets {
				assert data == [u8(0x40 + i)]
			}
			50 * time.millisecond {
				assert false, 'packet ${i} not delivered in order'
			}
		}
	}
}

// The same datagram delivered 10 times must result in exactly one packet.
fn test_duplicate_storm_single_delivery() {
	mut conn := &Conn{
		mtu:          max_mtu_size
		packets:      chan []u8{cap: 8}
		win:          new_datagram_window()
		packet_queue: new_packet_queue()
		resend:       new_resend_map()
	}
	mut dg := []u8{}
	dg << (bit_flag_datagram | bit_flag_needs_b_and_as)
	write_uint24(mut dg, Uint24(0))

	Packet{
		reliability: .reliable_ordered
		order_index: Uint24(0)
		content:     [u8(0xab)]
	}.write(mut dg)

	for _ in 0 .. 10 {
		conn.receive(dg)!
	}
	assert conn.packets.len == 1
}

// A datagram whose seq is beyond max_window_size ahead of the current lowest
// must be silently dropped (no panic, no allocation explosion).
fn test_datagram_window_rejects_huge_seq_jump() {
	mut win := new_datagram_window()
	assert win.add(Uint24(0))
	assert win.add(Uint24(1))
	assert !win.add(Uint24(max_window_size + 1))
	assert win.size() == Uint24(2)
}
