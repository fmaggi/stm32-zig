const hal = @import("hal");
const GPIO = hal.GPIO;

pub fn main() void {
    hal.init();

    GPIO.Port.enable(.C);
    const led = GPIO.init(.C, 13);
    led.asOutput(.{});

    GPIO.Port.enable(.A);
    const button = GPIO.init(.A, 11);
    button.asInput(.{ .pull = .down });

    while (true) {
        led.write(button.read());
    }
}
