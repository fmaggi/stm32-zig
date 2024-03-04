const hal = @import("hal");
const time = hal.time;
const GPIO = hal.GPIO;

pub fn main() void {
    hal.reset();

    GPIO.Port.enable(.C);
    const led = GPIO.init(.C, 13);

    while (true) {
        led.toggle();
        time.delay_ms(1000);
    }
}
