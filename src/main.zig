const hal = @import("hal/hal.zig");
const GPIO = @import("hal/GPIO.zig");
const int = @import("hal/interrupts.zig");

pub const VectorTable = struct {
    pub fn NMI() void {}
    pub fn HardFault() void {
        @panic("Hard fault");
    }
};

pub fn main() !void {
    hal.init();

    GPIO.enablePort(.C);
    GPIO.enablePort(.A);

    const pin1 = GPIO.init(.A, 0);
    pin1.asInput(.{
        .pull = .down,
        .exti = GPIO.Exti.interrupt(.rising),
    });

    const pin2 = GPIO.init(.C, 13);
    pin2.asOutput(.{});

    const i = int.DeviceInterrupt.TIM2;

    i.setPriority(.{ .preemptive = 4, .sub = 1 });

    while (true) {
        pin2.toggle();
    }
    // return 0;
}
