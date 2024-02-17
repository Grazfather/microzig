const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;
const dma = rp2xxx.dma;

const ws2812_program = blk: {
    @setEvalBranchQuota(10000);
    const p = rp2xxx.pio.assemble(
        \\.program ws2812
        \\
        \\.define public T1 2
        \\.define public T2 5
        \\.define public T3 3
        \\
        // \\ ; ORIGINAL
        // \\.wrap_target
        // \\bitloop:
        // \\    out x, 1       side 0 [T3 - 1] ; Side-set still takes place when instruction stalls
        // \\    jmp !x do_zero side 1 [T1 - 1] ; Branch on the bit we shifted out. Positive pulse
        // \\do_one:
        // \\    jmp  bitloop   side 1 [T2 - 1] ; Continue driving high, for a long pulse
        // \\do_zero:
        // \\    nop            side 0 [T2 - 1] ; Or drive low, for a short pulse
        // \\.wrap
        // \\
        // \\ ; FANCY ONE
        // \\.side_set 1 opt
        // // \\    pull block                  ; pull the next data (number of LEDs - 1)
        // \\    out y, 32                   ; and put it to "Y"
        // // \\
        // \\.wrap_target
        // \\    mov x, y                    ; initialise the LED counter "X" with the value of "Y"
        // \\next_led:
        // // \\    pull block                  ; pull the next data (RGB value for a LED), blocking
        // \\    irq 0                       ; set INT 0 flag
        // // \\    out null, 8                 ; ignore the trailing 8 bits
        // \\
        // \\next_bit:
        // \\    out x, 1 side 0 [T3 - 1]
        // \\    nop side 1    [T1 - 1]
        // \\    mov pins, x     [T2 - 2]
        // \\    jmp next_bit
        // \\    jmp x--, next_led
        // \\    nop side 1      [T1 - 1]   ; set the GPIO to "1"
        // \\    out pins, 1     [T2 - 1]    ; the middle 1/3 is equal to actual value we send
        // \\    jmp !osre next_bit side 0 [T3 -1]  ; set the GPIO to "0", jump if the shift register contains more bits
        // \\                                ; shift register empty -> no more data to send for a LED
        // \\
        // \\    jmp x-- next_led            ; jump if more LEDs to send data to
        // \\                                ; here we are done - introduce the 50us reset delay
        // \\                                ; wait 400 cycles (50us = 40 bit lengths * 3)
        // \\    set x, 24                   ; 400 = 25 * 16 (set "X" to 24-1)
        // \\delay_loop:
        // \\    nop                [7]
        // \\    jmp x-- delay_loop [7]      ; 1 + 7 + 1 + 7 cycles in each iteration
        // \\
        //        \\    irq clear 0                 ; clear INT 0 flag
        //        simple working in python
        \\.side_set 1 opt
        \\.wrap_target
        \\bitloop:
        \\out x, 1 side 0 [T3 - 1]
        \\jmp !x do_zero side 1 [T1 - 1]
        \\jmp bitloop side 1 [T2 - 1]
        \\do_zero:
        \\nop side 0 [T2 - 1]
        \\.wrap
    , .{}).get_program_by_name("ws2812");
    break :blk p;
};

const pio: Pio = .pio0;
const sm: StateMachine = .sm0;
const led_pin = gpio.num(22);

pub fn main() void {
    pio.gpio_init(led_pin);
    // TODO: For the fancier one, it expects outshift false false 32
    // https://www.youtube.com/watch?v=OenPIsmKeDI
    sm_set_consecutive_pindirs(pio, sm, @intFromEnum(led_pin), 1, true);

    // 52.08333206176758. Same as the C one
    // const div = (@as(f32, @floatFromInt(rp2040.clock_config.sys.?.output_freq)) / 1e6) * 1.25 / 3.0;
    // 10
    const cycles_per_bit: comptime_int = ws2812_program.defines[0].value + //T1
        ws2812_program.defines[1].value + //T2
        ws2812_program.defines[2].value; //T3
    // 15.625
    const div = @as(f32, @floatFromInt(rp2xxx.clock_config.sys.?.frequency())) /
        (800_000 * cycles_per_bit);

    // @compileLog(ws2812_program.side_set);
    // This loads the PIO program, setting the side set, wrap, etc. based on the Program returned from the assembler
    pio.sm_load_and_start_program(sm, ws2812_program, .{
        .clkdiv = rp2xxx.pio.ClkDivOptions.from_float(div),
        .pin_mappings = .{
            // This needs to be set if we use set or mov
            .set = .{
                .base = @intFromEnum(led_pin),
                .count = 1,
            },
            // This needs to be set if we use side set
            .side_set = .{
                .base = @intFromEnum(led_pin),
                // We use 2, 1 side plus 1 for opt
                .count = 2,
                // .count = 1,
            },
        },
        .shift = .{
            // We use left for fancy as well
            .out_shiftdir = .left,
            .autopull = true,
            // 0 means 32
            .pull_threshold = 0,
            // .pull_threshold = 24,
            // .join_tx = true,
        },
    }) catch unreachable;

    pio.sm_set_enabled(sm, true);

    const LED_COUNT = 8;
    // const colours = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff };
    const colours = [_]u32{ 0x00ACCC, 0x1D5DC5, 0x541ECB, 0x9C1CEE, 0xB30D8B, 0xBC1303, 0xD6AB01, 0xBEFE00, 0x69FF03, 0x26FF00, 0x00FF19 };
    var led_buffer = [_]u32{0} ** LED_COUNT;
    var first_colour: u32 = 0;

    // TODO: Claim the channel?
    // TODO: Get default config?
    // Config DMA to copy LED buffer to the PIO statemachine's FIFO
    // dma_channel_config dma_ch0 = dma_channel_get_default_config(led_dma_chan);
    // const DREQ_PIO0_TX0 = 0;
    // // var dma_ch0 = dma.channel(0);
    // var dma_ch = dma.claim_unused_channel() orelse unreachable;
    // var dma_config = dma.Channel.TransferConfig{
    //     .transfer_size_bytes = 2,
    //     .enable = true,
    //     .read_increment = true,
    //     .write_increment = false,
    //     .dreq = @enumFromInt(DREQ_PIO0_TX0),
    // };
    // var addr = pio.sm_get_tx_fifo(sm);
    // _ = addr;
    // _ = dma_ch;
    // _ = dma_config;
    // channel_config_set_transfer_data_size(&dma_ch, DMA_SIZE_32); // 32 bits == 4 bytes, but is that allowed?
    // channel_config_set_read_increment(&dma_ch, true);
    // channel_config_set_write_increment(&dma_ch, false);
    // channel_config_set_dreq(&dma_ch, DREQ_PIO0_TX0);

    // Tell PIO how many LEDs we have
    pio.sm_blocking_write(sm, LED_COUNT - 1);

    while (true) {
        // Rotate colours
        for (0..LED_COUNT) |i| {
            led_buffer[i] = colours[(i + first_colour) % colours.len];
            pio.sm_blocking_write(sm, led_buffer[i] << 8);
        }
        // dma_channel_configure(led_dma_chan, &dma_ch, &pio->txf[sm], led_buffer, LED_COUNT, true);
        // dma_ch.trigger_transfer(@intFromPtr(addr), @intFromPtr(&led_buffer), LED_COUNT, dma_config);
        rp2xxx.time.sleep_ms(50);

        first_colour = (first_colour + 1) % colours.len;

        // rp2040.time.sleep_ms(500);
        // pio.sm_blocking_write(sm, led_buffer[0] << 8);
        // pio.sm_blocking_write(sm, 0x00ff00 << 8); //red
        // pio.sm_blocking_write(sm, 0xff0000 << 8); //green
        // rp2040.time.sleep_ms(50);
        // pio.sm_blocking_write(sm, 0x0000ff << 8); //blue
        // rp2040.time.sleep_ms(50);
        // pio.sm_blocking_write(sm, 0x00ff00 << 8); //blue
        rp2xxx.time.sleep_ms(250);
    }
}

fn sm_set_consecutive_pindirs(_pio: Pio, _sm: StateMachine, pin: u5, count: u3, is_out: bool) void {
    const sm_regs = _pio.get_sm_regs(_sm);
    const pinctrl_saved = sm_regs.pinctrl.raw;
    sm_regs.pinctrl.modify(.{
        .SET_BASE = pin,
        .SET_COUNT = count,
    });
    _pio.sm_exec(_sm, rp2xxx.pio.Instruction{
        .tag = .set,
        .delay_side_set = 0,
        .payload = .{
            .set = .{
                .data = @intFromBool(is_out),
                .destination = .pindirs,
            },
        },
    });
    sm_regs.pinctrl.raw = pinctrl_saved;
}
