const hal = @import("hal");
const time = hal.time;
const clocks = hal.clocks;
const GPIO = hal.GPIO;

pub fn main() void {
    hal.init();

    GPIO.Port.enable(.C);
    const led = GPIO.init(.C, 13);

    led.asOutput(.{});

    while (true) {
        led.toggle();
        time.delay_ms(1000);
    }
}
