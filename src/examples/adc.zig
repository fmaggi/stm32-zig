const hal = @import("hal");
const GPIO = hal.GPIO;
const ADC = hal.ADC;

pub fn main() void {
    hal.reset();

    const adc = ADC.init(.ADC1);
    adc.setConfig(.{
        .channels = &[_]ADC.Channel{
            .{ .number = 0 },
        },
    }) catch return;

    const led = GPIO.init(.C, 13);

    while (true) {
        adc.start() catch continue;
        const value = adc.poll(null) catch return orelse continue;
        if (value < 1000) {
            led.toggle();
        }
    }
}
