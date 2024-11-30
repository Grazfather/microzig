const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;

const BUF_LEN = 0x100;
const spi = rp2xxx.spi.instance.SPI1;

const led = gpio.num(25);
// >>UART logging
const uart = rp2xxx.uart.instance.num(1);
const baud_rate = 115200;
const uart_tx_pin = gpio.num(4);
const uart_rx_pin = gpio.num(5);
// <<UART logging

// These will change depending on which GPIO pins you have your SPI device routed to.
const CS_PIN = 1;
const SCK_PIN = 2;
// -- Since this is the slave device, we read on MISO_PIN
const MOSI_PIN = 0;
const MISO_PIN = 3;

pub fn main() !void {
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);
    // Set pin functions for CS, SCK, MOSI, MISO
    const csn = gpio.num(CS_PIN);
    const mosi = gpio.num(MOSI_PIN);
    const miso = gpio.num(MISO_PIN);
    const sck = gpio.num(SCK_PIN);
    inline for (&.{ csn, mosi, miso, sck }) |pin| {
        pin.set_function(.spi);
    }

    // >>UART logging
    inline for (&.{ uart_tx_pin, uart_rx_pin }) |pin| {
        pin.set_function(.uart);
    }
    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });

    rp2xxx.uart.init_logger(uart);
    // <<UART logging

    try uart.write_blocking("Setting SPI as slave device\r\n", null); // DELETEME
    spi.set_slave(true);

    // Back to 8 bit mode
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .eight,
    });
    var buf: [1024]u8 = undefined;
    var in_buf_eight: [BUF_LEN]u8 = undefined;
    try uart.write_blocking("Waiting!\r\n", null);
    // while (true) {
    //     const x = csn.read();
    //     led.put(x);
    // }
    // TODO: Wait on CS low
    // This doesn't wait at all..
    spi.read_blocking(u8, 0, &in_buf_eight);
    led.put(0);

    // std.log.info("Got: {any}\r\n", .{in_buf_eight});
    var text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_eight}) catch &.{};
    try uart.write_blocking(text, null);

    // 12 bit data words
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .twelve,
    });
    var in_buf_twelve: [BUF_LEN]u12 = undefined;
    // TODO: Wait on CS low
    spi.read_blocking(u12, 0, &in_buf_twelve);
    // std.log.info("Got: {any}\r\n", .{in_buf_twelve});
    text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_twelve}) catch &.{};
    try uart.write_blocking(text, null);

    // Back to 8 bit mode
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .eight,
    });

    while (true) {
        // TODO: Wait on CS low
        spi.read_blocking(u8, 0, &in_buf_eight);
        text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_eight}) catch &.{};
        std.log.info("Got: {any}\r\n", .{in_buf_eight});
        try uart.write_blocking(text, null);
    }
}
