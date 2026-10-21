module raknet

const packet_queue_max_bytes = 32 * 1024 * 1024

struct PacketQueue {
mut:
	lowest         Uint24
	sequence_index Uint24
	ordered        map[Uint24]Packet
	sequenced      map[Uint24][]Packet
	queued         int
	queued_bytes   int
}

fn (mut q PacketQueue) put(pk Packet) !bool {
	distance := uint24_distance(pk.order_index, q.lowest)
	if distance >= uint24_half_range {
		return false
	}
	if distance >= u32(max_window_size) {
		return error('packet queue window size is too big')
	}
	if pk.reliability.sequenced() {
		if distance == 0 && uint24_distance(pk.sequence_index, q.sequence_index) >= uint24_half_range {
			return false
		}
		mut packets := q.sequenced[pk.order_index] or { []Packet{} }
		for queued in packets {
			if queued.sequence_index == pk.sequence_index {
				return false
			}
		}
		if distance > 0 && q.queued >= max_window_size {
			return error('maximum buffered ordered and sequenced packets reached')
		}
		packets << pk.clone()
		q.sequenced[pk.order_index] = packets
	} else {
		if pk.order_index in q.ordered {
			return false
		}
		if distance > 0 && q.queued >= max_window_size {
			return error('maximum buffered ordered and sequenced packets reached')
		}
		q.ordered[pk.order_index] = pk.clone()
	}
	q.queued++
	q.queued_bytes += pk.content.len
	return true
}

fn (mut q PacketQueue) fetch() []Packet {
	mut packets := []Packet{}
	for {
		mut sequenced := q.sequenced[q.lowest] or { []Packet{} }
		if sequenced.len > 0 {
			base := q.sequence_index
			sequenced.sort_with_compare(fn [base] (a &Packet, b &Packet) int {
				return int(uint24_distance(a.sequence_index, base)) - int(uint24_distance(b.sequence_index, base))
			})
			q.sequenced.delete(q.lowest)
			q.queued -= sequenced.len
			for pk in sequenced {
				q.queued_bytes -= pk.content.len
				if uint24_distance(pk.sequence_index, q.sequence_index) < uint24_half_range {
					packets << pk
					q.sequence_index = uint24_next(pk.sequence_index)
				}
			}
		}
		pk := q.ordered[q.lowest] or { break }
		q.ordered.delete(q.lowest)
		q.queued--
		q.queued_bytes -= pk.content.len
		packets << pk
		q.lowest = uint24_next(q.lowest)
		q.sequence_index = 0
	}
	return packets
}
