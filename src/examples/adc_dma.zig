const hal = @import("hal");
const GPIO = hal.GPIO;
const adc = hal.adc;
const dma = hal.dma;

pub fn main() void {
    hal.init();

    const adc1 = adc.ADC1.withDMA();
    adc1.apply(.{
        .channels = &.{
            adc.Channel.A0,
            adc.Channel.A1,
            adc.Channel.temperature,
            // You can repeat channels
            adc.Channel.A1,
            // Default sampling cycles is 1.5, but you can change it
            adc.Channel.A2.withSamplingCycles(.@"7.5"),
        },
    }) catch @panic("Failed to enable ADC");

    GPIO.Port.enable(.C);
    const led = GPIO.init(.C, 13);
    led.asOutput(.{});

    var buf: [5]u16 = undefined;

    while (true) {
        const transfer = adc1.start(&buf) catch continue;
        transfer.wait(null) catch unreachable;

        led.write(@intFromBool(buf[0] < 1000));
        hal.time.delay_ms(100);
    }
}
