const std = @import("std");

const chip = @import("chip");

const GPIO = @import("GPIO.zig");
const time = @import("time.zig");

pub const Registers = chip.types.peripherals.ADC1;

const RCC = chip.peripherals.RCC;

const ADC = @This();

registers: *volatile Registers,

pub const ADC1: ADC = .{ .registers = chip.peripherals.ADC1 };
pub const ADC2: ADC = .{ .registers = @ptrCast(chip.peripherals.ADC2) };
// blue pill only has 2 ADCs
// const adc3: *volatile Registers = @ptrCast(chip.peripherals.ADC3);

pub const Config = struct {
    channels: []const Channel, // valid len [1, 16]
    trigger: Trigger = .SOFTWARE,
    data_alignment: DataAlignment = .right,
    mode: Mode = .continuous,
    // interrupt: bool = false,

    pub const DataAlignment = enum(u1) {
        right = 0,
        left = 1,
    };

    pub const Mode = union(enum) {
        continuous,
        discontinuous: u4, // valid range: [1, 8]
    };

    pub const Trigger = enum(u3) {
        TIM1_CC1,
        TIM1_CC2,
        TIM1_CC3,
        TIM2_CC2,
        TIM3_TRGO,
        TIM4_CC4,
        EXTI_11,
        SOFTWARE,
    };

    pub const Error = error{
        ZeroChannels,
        TooManyChannels,
        ZeroDiscontinouosConversions,
        TooManyDiscontinouosConversions,
        InvalidChannel,
    };

    pub fn check(config: Config) (error{UnimplementedDMA} || Error)!void {
        if (config.channels.len > 16) return Error.TooManyChannels;
        if (config.channels.len < 1) return Error.ZeroChannels;
        if (config.channels.len != 1) return error.UnimplementedDMA;
        if (config.mode == .discontinuous) {
            const n = config.mode.discontinuous;
            if (n > 8) return Error.TooManyDiscontinouosConversions;
            if (n < 1) return Error.ZeroDiscontinouosConversions;
        }

        for (config.channels) |channel| {
            if (!channel.isValid()) return Error.InvalidChannel;
        }
    }
};

pub inline fn setConfig(adc: ADC, comptime config: Config) void {
    comptime {
        const print = std.fmt.comptimePrint;
        const Error = Config.Error;
        config.check() catch |e| switch (e) {
            Error.ZeroChannels => @compileError("Zero ADC converion channels"),
            Error.TooManyChannels => @compileError(print("Too many ADC conversion channels: {}. Max is 16", .{config.channels.len})),
            Error.ZeroDiscontinouosConversions => @compileError("Zero ADC discontinuous conversions when in discontinuous mode"),
            Error.TooManyDiscontinouosConversions => @compileError(print("Too many ADC discontinuous conversions: {}. Max is 8", .{config.channels.len})),
            Error.InvalidChannel => @compileError("Invalid ADC conversion channel. Valid channels are 0-9, 16 and 17"),
            else => @compileError(@errorName(e)),
        };
    }
    adc.setConfigUnchecked(config);
}

pub fn setConfigUnchecked(adc: ADC, config: Config) void {
    switch (@intFromPtr(adc.registers)) {
        @intFromPtr(ADC1.registers) => RCC.APB2ENR.modify(.{ .ADC1EN = 1 }),
        @intFromPtr(ADC2.registers) => RCC.APB2ENR.modify(.{ .ADC2EN = 1 }),
        else => unreachable,
    }

    enableGPIOs(config.channels);

    adc.registers.CR1.modify(.{
        .SCAN = @intFromBool(config.channels.len > 1),
        .DISCEN = @intFromBool(config.mode == .discontinuous),
        .DISCNUM = switch (config.mode) {
            .continuous => 0,
            .discontinuous => |n| @as(u3, @truncate(n - 1)),
        },
    });

    adc.registers.CR2.modify(.{
        .ALIGN = @intFromEnum(config.data_alignment),
        .CONT = @intFromBool(config.mode == .continuous),
        .EXTSEL = @intFromEnum(config.trigger),
        // I don't think EXTTRIG triggers the actual conversion? I dont quite understand.
        // But it is possible it does that.
        // For some reason the ST C HAL sets this to 0 on init, so I'm doing the same.
        // What I think it does it enables external triggers.
        // If that is the case, the config should be this:
        // .EXTTRIG = @intFromBool(config.trigger != .SOFTWARE),
        .EXTTRIG = 0,
    });

    adc.registers.SQR1.modify(.{
        .L = @as(u4, @truncate(config.channels.len - 1)),
    });

    for (config.channels, 0..) |channel, rank| {
        adc.configChannel(channel, @truncate(rank)) catch unreachable;
    }
}

pub fn configChannel(adc: ADC, channel: Channel, rank: u5) error{InvalidChannel}!void {
    // Blue pill has up to channel 9 but channels 16 and 17 are
    // temperature sensor and Vbat sensor respectively
    // but they are only available in ADC1
    // so we need to handle them too
    if (!channel.isValid()) return error.InvalidChannel;
    {
        const mask: u32 = @as(u32, 0b11111) << rank;
        const value: u32 = @as(u32, channel.number) << rank;
        if (rank < 7) {
            const temp = adc.registers.SQR3.raw;
            adc.registers.SQR3.raw = (temp & ~mask) | value;
        } else if (rank < 13) {
            const temp = adc.registers.SQR2.raw;
            adc.registers.SQR2.raw = (temp & ~mask) | value;
        } else {
            const temp = adc.registers.SQR1.raw;
            adc.registers.SQR1.raw = (temp & ~mask) | value;
        }
    }

    if (channel.number == Channel.temperature or channel.number == Channel.vref) {
        if (adc.registers != ADC1.registers) return Config.Error.InvalidChannel;
        adc.registers.CR2.modify(.{ .TSVREFE = 1 });
        time.delay_us(10);
    }

    {
        const c = channel.number;
        const sc: u32 = @intFromEnum(channel.sampling_cycles);
        if (rank >= 10) {
            const mask: u32 = @as(u32, 0b111) << (3 * (c - 10));
            const temp = adc.registers.SMPR1.raw;
            adc.registers.SMPR1.raw = (temp & ~mask) | (sc << (3 * (c - 10)));
        } else {
            const mask: u32 = @as(u32, 0b111) << (3 * c);
            const temp = adc.registers.SMPR1.raw;
            adc.registers.SMPR1.raw = (temp & ~mask) | (sc << (3 * c));
        }
    }
}

pub fn start(adc: ADC) !void {
    try adc.enable();

    adc.registers.SR.modify(.{ .EOC = 0 });

    adc.registers.CR2.modify(.{
        .SWSTART = 1,
        .EXTTRIG = 1,
    });

    // C HAL does it like this, but it think the above should work
    // As the regerence manual says SWSTART triggers the conversion
    // IF ADC is configed as softwar triggered
    //
    // if (adc.isSoftwareTriggered()) {
    //     adc.registers.CR2.modify(.{
    //         .SWSTART = 1,
    //         .EXTTRIG = 1,
    //     });
    // } else {
    //     adc.registers.CR2.modify(.{ .EXTTRIG = 1 });
    // }
}

pub const PollError = error{PolledWithDMA};

/// On timeout returns null
pub fn poll(adc: ADC, timeout: ?u32) PollError!?u16 {
    if (adc.registers.CR2.read().DMA == 1) {
        return PollError.PolledWithDMA;
    }

    if (adc.isSingleConversion()) {
        if (timeout) |to| {
            const delay = time.timeout_ms(to);
            while (adc.registers.SR.read().EOC == 0) {
                if (delay.isReached()) return null;
            }
        } else {
            while (adc.registers.SR.read().EOC == 0) {}
        }
    } else {
        // TODO: Implement
    }

    adc.registers.SR.modify(.{
        .EOC = 0,
        .STRT = 0,
    });

    return adc.registers.DR.read().DATA;
}

fn enable(adc: ADC) !void {
    if (adc.registers.CR2.read().ADON == 1) {
        return;
    }

    adc.registers.CR2.modify(.{ .ADON = 1 });

    time.delay_us(1);

    const delay = time.timeout_ms(2);
    while (adc.registers.CR2.read().ADON == 1) {
        if (delay.isReached()) return error.Timeout;
    }

    return;
}

pub fn isSingleConversion(adc: ADC) bool {
    return adc.registers.CR1.read().SCAN == 0 and adc.registers.SQR1.read().L == 1;
}

pub fn isSoftwareTriggered(adc: ADC) bool {
    return adc.registers.CR2.read().EXTSEL == @intFromEnum(Config.Trigger.SOFTWARE);
}

pub const Channel = packed struct(u8) {
    pub const temperature = 17;
    pub const vref = 16;
    // C0 -> port A, pin 0 -> 0000
    // C1 -> port A, pin 1 -> 0001
    // C2 -> port A, pin 2 -> 0010
    // C3 -> port A, pin 3 -> 0011
    // C4 -> port A, pin 4 -> 0100
    // C5 -> port A, pin 5 -> 0101
    // C6 -> port A, pin 6 -> 0110
    // C7 -> port A, pin 7 -> 0111
    // C8 -> port B, pin 0 -> 1000
    // C9 -> port B, pin 1 -> 1001
    //
    // MSB -> Port, 3 LSBs -> Pin

    number: u5,
    sampling_cycles: enum(u3) {
        @"1.5",
        @"7.5",
        @"13.5",
        @"28.5",
        @"41.5",
        @"55.5",
        @"71.5",
        @"239.5",
    } = .@"1.5",

    pub inline fn port(channel: Channel) u1 {
        return @truncate(channel.number >> 3);
    }

    pub inline fn pin(channel: Channel) u3 {
        return @truncate(channel.number & 0b111);
    }

    pub inline fn isValid(channel: Channel) bool {
        return channel.number <= 9 or channel.number == temperature or channel.number == vref;
    }
};

fn enableGPIOs(channels: []const Channel) void {
    var ports: [2]bool = [_]bool{false} ** 2;
    var gpios: [10]bool = [_]bool{false} ** 10;
    for (channels) |channel| {
        const port = channel.port();
        const index = channel.number;
        std.debug.assert(index <= 9);

        if (!ports[port]) {
            GPIO.Port.enable(@enumFromInt(port));
            ports[port] = true;
        }

        if (!gpios[index]) {
            GPIO.init(@enumFromInt(port), channel.pin()).asInput(.analog);
            gpios[index] = true;
        }
    }
}
