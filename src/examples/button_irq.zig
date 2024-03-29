const hal = @import("hal");
const GPIO = hal.GPIO;

const led = GPIO.init(.C, 13);

pub const Callbacks = struct {
    pub fn GPIO11() void {
        led.toggle();
    }
};

pub fn main() void {
    hal.init();

    GPIO.Port.enable(.C);
    led.asOutput(.{});

    GPIO.Port.enable(.A);
    const button = GPIO.init(.A, 11);
    button.asInput(.{
        .exti = .{
            .config = .{
                .kind = .interrupt,
                .edge = .rising,
            },
            .pull = .down,
        },
    });

    while (true) {}
}
