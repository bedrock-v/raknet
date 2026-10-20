module raknet

fn test_ack_ranges_roundtrip() {
	mut ack := Acknowledgement{
		packets: [Uint24(7), 1, 3, 2]
	}
	mut out := []u8{}
	n := ack.write(mut out, 1200)
	assert n == 4
	assert out == [u8(0x00), 0x02, 0x00, 0x01, 0x00, 0x00, 0x03, 0x00, 0x00, 0x01, 0x07, 0x00,
		0x00]

	mut decoded := Acknowledgement{}
	decoded.read(out)!
	assert decoded.packets == [Uint24(1), 2, 3, 7]
}

fn test_ack_read_limit() {
	mut data := []u8{}
	data << [u8(0), 1] // one range record
	data << packet_range
	write_uint24(mut data, Uint24(0))
	write_uint24(mut data, Uint24(8193))

	mut decoded := Acknowledgement{}
	mut failed := false
	decoded.read(data) or {
		failed = true
		assert err.msg().contains('maximum amount')
	}
	assert failed
}

fn test_ack_mtu_boundary() {
	mut ack := Acknowledgement{
		packets: [Uint24(1), 10, 20, 30, 40, 50]
	}
	mut out := []u8{}
	n := ack.write(mut out, 12)
	assert n == 2
	assert out.len <= 12
}

fn test_ack_chunking_preserves_shuffled_packets() {
	for flag in [bit_flag_ack, bit_flag_nack] {
		for mtu in [u16(16), 1200] {
			mut ack := Acknowledgement{
				packets: [Uint24(300), 10, 250, 20, 200, 30, 150, 40, 100, 50]
			}
			mut received := []Uint24{}
			mut chunks := 0
			for ack.packets.len > 0 {
				mut out := [u8(flag | bit_flag_datagram)]
				n := ack.write(mut out, mtu)
				assert n > 0
				assert n <= ack.packets.len
				assert out.len <= int(mtu)
				mut decoded := Acknowledgement{}
				decoded.read(out[1..])!
				assert decoded.packets.len == n
				received << decoded.packets
				ack.packets = ack.packets[n..].clone()
				chunks++
			}
			if mtu == 16 {
				assert chunks > 1
			} else {
				assert chunks == 1
			}
			received.sort(a < b)
			assert received == [Uint24(10), 20, 30, 40, 50, 100, 150, 200, 250, 300]
		}
	}
}

fn test_ack_chunking_mixed_records_respects_mtu() {
	mut ack := Acknowledgement{
		packets: [Uint24(1), 10, 11, 12, 50]
	}
	mut received := []Uint24{}
	for ack.packets.len > 0 {
		mut out := [u8(bit_flag_ack | bit_flag_datagram)]
		n := ack.write(mut out, 16)
		assert n > 0
		assert out.len <= 16
		mut decoded := Acknowledgement{}
		decoded.read(out[1..])!
		assert decoded.packets.len == n
		received << decoded.packets
		ack.packets = ack.packets[n..].clone()
	}
	assert received == [Uint24(1), 10, 11, 12, 50]
}
