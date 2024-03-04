const hal = @import("hal");
const GPIO = hal.GPIO;
const clocks = hal.clocks;
const interrupts = hal.interrupts;
const ADC = hal.ADC;

const config: clocks.Config = .{
    .sys = clocks.PLL.fromHSI(.{}, 64_000_000).asOscillator(),
    .pclk1_frequency = 32_000_000,
    .pclk2_frequency = 32_000_000,
    .adc_frequency = 4_000_000,
};

var gpio0_clicked = false;

pub const Callbacks = struct {
    pub fn GPIO0() void {
        gpio0_clicked = true;
    }

    pub fn GPIO10() void {
        const pin = GPIO.init(.C, 10);
        pin.toggle();
    }

    pub fn GPIO13() void {
        const pin = GPIO.init(.C, 11);
        pin.toggle();
    }
};

pub fn main() void {
    hal.init();

    config.apply(.{}) catch return;

    GPIO.Port.enable(.C);
    GPIO.Port.enable(.A);

    const pin1 = GPIO.init(.A, 0);
    pin1.asInput(.{
        .exti = .{
            .config = .{
                .kind = .interrupt,
                .edge = .rising,
            },
            .pull = .down,
        },
    });

    const led = GPIO.init(.C, 13);
    led.asOutput(.{});

    const adc = ADC.ADC1;
    adc.setConfig(.{
        .channels = &[_]ADC.Channel{
            .{ .number = 0 },
        },
    });

    while (true) {
        adc.start() catch continue;
        const value = adc.poll(null) catch return orelse continue;
        if (value > 1000) {
            led.toggle();
        }

        if (gpio0_clicked) {
            led.toggle();
            gpio0_clicked = false;
        }
    }
}
