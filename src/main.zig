const hal = @import("hal/hal.zig");
const GPIO = @import("hal/GPIO.zig");

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
    pin1.setInputMode(.{}, null, null) catch return;

    const pin2 = GPIO.init(.C, 13);
    pin2.setMode(.{
        .output = .{},
    });

    while (true) {
        pin2.toggle();
    }
    // return 0;
}
