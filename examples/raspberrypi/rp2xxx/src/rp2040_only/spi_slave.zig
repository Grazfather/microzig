const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;

const BUF_LEN = 0x100;
const spi = rp2xxx.spi.instance.SPI0;

// These will change depending on which GPIO pins you have your SPI device routed to.
const CS_PIN = 1;
const SCK_PIN = 2;
// -- Since this is the slave device, pins are swapped.
const MOSI_PIN = 4;
const MISO_PIN = 3;

// >>CDC stuff
const usb = rp2xxx.usb;
const usb_config_len = usb.templates.config_descriptor_len + usb.templates.cdc_descriptor_len;
const usb_config_descriptor =
    usb.templates.config_descriptor(1, 2, 0, usb_config_len, 0xc0, 100) ++
    usb.templates.cdc_descriptor(0, 4, usb.Endpoint.to_address(1, .In), 8, usb.Endpoint.to_address(2, .Out), usb.Endpoint.to_address(2, .In), 64);

var driver_cdc = usb.cdc.CdcClassDriver{};
var drivers = [_]usb.types.UsbClassDriver{driver_cdc.driver()};

// This is our device configuration
pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
    .device_descriptor = &.{
        .descriptor_type = usb.DescType.Device,
        .bcd_usb = 0x0200,
        .device_class = 0xEF,
        .device_subclass = 2,
        .device_protocol = 1,
        .max_packet_size0 = 64,
        .vendor = 0x2E8A,
        .product = 0x000a,
        .bcd_device = 0x0100,
        .manufacturer_s = 1,
        .product_s = 2,
        .serial_s = 0,
        .num_configurations = 1,
    },
    .config_descriptor = &usb_config_descriptor,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &usb.utils.utf8ToUtf16Le("Raspberry Pi"),
        &usb.utils.utf8ToUtf16Le("Pico Test Device"),
        &usb.utils.utf8ToUtf16Le("someserial"),
        &usb.utils.utf8ToUtf16Le("Board CDC"),
    },
    .drivers = &drivers,
};
// <<CDC stuff

pub fn main() !void {
    // Set pin functions for CS, SCK, MOSI, MISO
    const csn = gpio.num(CS_PIN);
    const mosi = gpio.num(MOSI_PIN);
    const miso = gpio.num(MISO_PIN);
    const sck = gpio.num(SCK_PIN);
    inline for (&.{ csn, mosi, miso, sck }) |pin| {
        pin.set_function(.spi);
    }

    rp2xxx.usb.Usb.init_clk();
    rp2xxx.usb.Usb.init_device(&DEVICE_CONFIGURATION) catch unreachable;
    var old: u64 = time.get_time_since_boot().to_us();
    var new: u64 = 0;

    var i: u32 = 0;
    var buf: [1024]u8 = undefined;
    while (true) {
        // You can now poll for USB events
        rp2xxx.usb.Usb.task(
            false, // debug output over UART [Y/n]
        ) catch unreachable;

        new = time.get_time_since_boot().to_us();
        if (new - old > 500000) {
            old = new;
            i += 1;
            // const text = std.fmt.bufPrint(&buf, "cdc test: {}\r\n", .{i}) catch &.{};
            driver_cdc.write("Hello!\r\n");
            // driver_cdc.write(text);
        }
    }
    var in_buf_eight: [BUF_LEN]u8 = undefined;
    // TODO: Wait on CS low
    spi.read_blocking(u8, 0, &in_buf_eight);

    var text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_eight}) catch &.{};
    driver_cdc.write(text);

    // 12 bit data words
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .twelve,
    });
    var in_buf_twelve: [BUF_LEN]u12 = undefined;
    // TODO: Wait on CS low
    spi.read_blocking(u12, 0, &in_buf_twelve);
    text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_twelve}) catch &.{};
    driver_cdc.write(text);

    // Back to 8 bit mode
    try spi.apply(.{
        .clock_config = rp2xxx.clock_config,
        .data_width = .eight,
    });
    while (true) {
        // TODO: Wait on CS low
        spi.read_blocking(u8, 0, &in_buf_eight);
        text = std.fmt.bufPrint(&buf, "Got: {any}\r\n", .{in_buf_eight}) catch &.{};
        driver_cdc.write(text);
        time.sleep_ms(1 * 1000);
    }
}
