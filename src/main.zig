const hal = @import("hal/hal.zig");
const GPIO = @import("hal/GPIO.zig");
const clocks = @import("hal/clocks.zig");
const interrupts = @import("hal/interrupts.zig");

pub const VectorTable = struct {
    pub fn NMI() void {}
    pub fn HardFault() void {
        @panic("Hard fault");
    }
};

const config: clocks.Configuration = .{
    .sys = clocks.PLL.fromHSI(.{}, 64_000_000).asOscillator(),
    .apb1_frequency = 32_000_000,
};

pub fn main() !void {
    hal.init();

    try config.apply();

    GPIO.enablePort(.C);
    GPIO.enablePort(.A);

    const pin1 = GPIO.init(.A, 0);
    pin1.asInput(.{
        .pull = .down,
        .exti = GPIO.Exti.interrupt(.rising),
    });

    const pin2 = GPIO.init(.C, 13);
    pin2.asOutput(.{});

    while (true) {
        pin2.toggle();
    }
    // return 0;
}
