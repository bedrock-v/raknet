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

listener.set_pong_data('raknet server'.bytes())

mut conn := listener.accept()!
mut buf := []u8{len: 4096}
n := conn.read(mut buf)!
conn.write(buf[..n])!
```

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

## Tests

```sh
v test .
```
