const hal = @import("hal");
const GPIO = hal.GPIO;
const adc = hal.adc;

pub fn main() void {
    hal.init();

    const adc1 = adc.ADC1;

    adc1.apply(.{
        .channels = &.{
            adc.Channel.A0,
            // Default sampling cycles is 1.5, but you can change it
            // adc.Channel.A0.withSamplingCycles(.@"7.5"),
        },
    }) catch @panic("Failed to enable ADC");

    GPIO.Port.enable(.C);
    const led = GPIO.init(.C, 13);
    led.asOutput(.{});

    while (true) {
        adc1.start();
        const value = adc1.waitAndRead(null) catch continue;

        led.write(@intFromBool(value < 1000));
        hal.time.delay_ms(100);
    }
}
