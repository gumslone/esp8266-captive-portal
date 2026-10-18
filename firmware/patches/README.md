# Firmware patches

## ws2812-write_pin.patch
Adds `ws2812.write_pin(pin, "GRB...")` to NodeMCU 2.2.1's `ws2812` module.

The stock `ws2812.write()` streams via UART1, which is hard-wired to **GPIO2
(D4)**. Boards that route the LED data to another pin (the TeHy-Bug MicroBug
uses **GPIO12**) need this: `write_pin` bit-bangs the WS2812B/SK6812 timing on
any GPIO, using the CPU cycle counter (works at 80 and 160 MHz), the same
technique as NodeMCU's `tm1829` driver.

### Rebuild
```sh
cd ~/dev/nodemcu-firmware-2.2.1
git apply /path/to/ws2812-write_pin.patch          # or patch -p1 < ...
# enable the module + integer build (already set for the minimal config):
#   app/include/user_modules.h : #define LUA_USE_MODULES_WS2812
docker run --rm --platform linux/amd64 -e INTEGER_ONLY=1 \
  -v "$PWD":/opt/nodemcu-firmware marcelstoer/nodemcu-build build
# -> bin/nodemcu_integer_*.bin
```
The built image is kept in `firmware/minimal-ws2812-anypin/`.
