# raknet

`raknet` is a RakNet implementation for V, focused on the classic RakNet protocol used by Minecraft: Bedrock Edition.

The API is plain-structed and inspired by Sandertv's `go-raknet`.

## Basic Server

```v
import raknet

mut listener := raknet.listen('0.0.0.0:19132')!
defer {
	listener.close() or {}
}

listener.set_pong_data('raknet server'.bytes())!

mut conn := listener.accept()!
mut buf := []u8{len: 4096}
n := conn.read(mut buf)!
conn.write(buf[..n])!
```

The listener queues up to 32 completed connections waiting for `accept()`.
When that queue is full, additional completed connections are closed on the
server so existing peers can continue exchanging packets. Call `accept()`
regularly to drain the queue.

## Basic Client

```v
import raknet

mut conn := raknet.dial('127.0.0.1:19132')!
defer {
	conn.close() or {}
}

conn.write('ping'.bytes())!
packet := conn.read_packet()!
println(packet.bytestr())
```

## Basic Ping

```v
import raknet

data := raknet.ping('127.0.0.1:19132')!
println(data.bytestr())
```

IPv6 addresses use bracket notation:

```v
mut conn := raknet.dial('[::1]:19133')!
```

## Configuration

```v
import time
import raknet

mut listener := raknet.ListenConfig{
	max_mtu: 1200
	disable_cookies: false
	handshake_timeout: 10 * time.second
}.listen('0.0.0.0:19132')!

dialer := raknet.Dialer{
	max_mtu: 1200
	timeout: 2 * time.second
}
mut conn := dialer.dial(listener.addr())!
```

## Logging

`ListenConfig` and `Dialer` both accept an optional `error_log` hook for
diagnostic events (blocked reads, transient UDP errors, close-drain progress...)
that would otherwise be silently dropped:

```v
fn on_event(msg string, fields map[string]string) {
	eprintln('${msg}: ${fields}')
}

mut listener := raknet.ListenConfig{
	error_log: on_event
}.listen('0.0.0.0:19132')!
```

## Receive reliability

Reliable receive deduplicates retransmitted messages and fragments. Ordered and
sequenced delivery track each of the 32 ordering channels independently; the
write methods send on channel 0. Sequenced packets wait for missing ordered
packets in the same channel, and stale sequences are discarded.

Reliable receive windows allow up to 10,240 outstanding message indices to
cover fragmented bursts. Datagram and ordering windows allow up to 2,048
indices. Ordering buffers hold at most 2,048 future packets per channel and
32 MiB of payloads per connection. Exceeding these limits closes the
connection.

## Tests

```sh
v test .
```
