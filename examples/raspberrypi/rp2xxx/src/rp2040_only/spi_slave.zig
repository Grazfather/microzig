const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;
const clocks = rp2xxx.clocks;
const peripherals = microzig.chip.peripherals;

const BUF_LEN = 0x100;
const spi = rp2xxx.spi.instance.SPI0;

// These will change depending on which GPIO pins you have your SPI device routed to
const CS_PIN = 1;
const SCK_PIN = 2;
const MOSI_PIN = 3;
const MISO_PIN = 4;

// Communicate with a SPI master
pub fn main() !void {

    // Set pin functions for CS, SCK, MOSI, MISO
    const csn = gpio.num(CS_PIN);
    const mosi = gpio.num(MOSI_PIN);
    const miso = gpio.num(MISO_PIN);
    const sck = gpio.num(SCK_PIN);
    inline for (&.{ csn, mosi, miso, sck }) |pin| {
        pin.set_function(.spi);
    }

    // 8 bit data words
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .eight,
    });
    var in_buf_eight: [BUF_LEN]u8 = undefined;
    // TODO: Wait on CS low
    spi.read_blocking(u8, 0, &in_buf_eight);

    // 12 bit data words
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .twelve,
    });
    var in_buf_twelve: [BUF_LEN]u12 = undefined;
    // TODO: Wait on CS low
    spi.read_blocking(u12, 0, &in_buf_twelve);

    // Back to 8 bit mode
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .eight,
    });
    while (true) {
        // TODO: Wait on CS low
        spi.read_blocking(u8, 0, &in_buf_eight);
        time.sleep_ms(1 * 1000);
    }
}
