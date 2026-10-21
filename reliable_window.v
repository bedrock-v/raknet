module raknet

struct ReliableWindow {
mut:
	lowest   Uint24
	received map[Uint24]bool
}

fn (mut window ReliableWindow) add(index Uint24) !bool {
	distance := uint24_distance(index, window.lowest)
	if distance >= uint24_half_range || index in window.received {
		return false
	}
	if distance >= u32(reliable_message_window_size) {
		return error('reliable message window size is too big')
	}
	window.received[index] = true
	for window.lowest in window.received {
		window.received.delete(window.lowest)
		window.lowest = uint24_next(window.lowest)
	}
	return true
}
