const std = @import("std");

const chip = @import("chip");
const RCC = chip.peripherals.RCC;
const AFIO = chip.peripherals.AFIO;
const EXTI = chip.peripherals.EXTI;
const Port = chip.types.peripherals.GPIOA;

const GPIOA = chip.peripherals.GPIOA;
const GPIOB = chip.peripherals.GPIOB;
const GPIOC = chip.peripherals.GPIOC;
const GPIOD = chip.peripherals.GPIOD;
const GPIOE = chip.peripherals.GPIOE;
const GPIOF = chip.peripherals.GPIOF;
const GPIOG = chip.peripherals.GPIOG;

const GPIO = @This();

pub const ConfigError = error{
    InvalidPull,
};

port: *volatile Port,
pin: u4,

pub const PortName = enum(u3) {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
};

pub fn enablePort(port: PortName) void {
    const offset = @intFromEnum(port) + 2;
    const bit = @as(u32, 1) << offset;
    RCC.APB2ENR.raw |= bit;
    // Delay after setting
    _ = RCC.APB2ENR.raw & bit;
}

pub fn init(port: PortName, pin: u4) GPIO {
    const p = switch (port) {
        .A => GPIOA,
        .B => GPIOB,
        .C => GPIOC,
        .D => GPIOD,
        .E => GPIOE,
        .F => GPIOF,
        .G => GPIOG,
    };

    return .{
        .port = p,
        .pin = pin,
    };
}

pub fn setInputMode(gpio: GPIO, config: Input, pull: ?Pull, exti: ?Exti) ConfigError!void {
    gpio.setMode(.{ .input = config });
    if (config.type == .pull) {
        const p = pull orelse return ConfigError.InvalidPull;
        gpio.setPull(p);
    }

    if (exti) |e| {
        gpio.setExti(e);
    }
}

pub fn setOutputMode(gpio: GPIO, config: Output) void {
    gpio.setMode(.{ .output = config });
}

pub fn setMode(gpio: GPIO, config: Config) void {
    const config_int: u32 = @intCast(@as(u4, @bitCast(config)));
    if (gpio.pin <= 7) {
        const offset = @as(u5, gpio.pin) << 2;
        gpio.port.CRL.raw &= ~(@as(u32, 0b1111) << offset);
        gpio.port.CRL.raw |= config_int << offset;
    } else {
        const offset = (@as(u5, gpio.pin) - 8) << 2;
        gpio.port.CRH.raw &= ~(@as(u32, 0b1111) << offset);
        gpio.port.CRH.raw |= config_int << offset;
    }
}

pub fn setPull(gpio: GPIO, pull: Pull) void {
    switch (pull) {
        .up => gpio.port.BSRR.raw = gpio.mask(),
        .down => gpio.port.BRR.raw = gpio.mask(),
    }
}

pub fn setExti(gpio: GPIO, exti: Exti) void {
    RCC.APB2ENR.modify(.{ .AFIOEN = 1 });
    _ = RCC.APB2ENR.read().AFIOEN;

    const port: usize = switch (@intFromPtr(gpio.port)) {
        @intFromPtr(GPIOA) => 0,
        @intFromPtr(GPIOB) => 1,
        @intFromPtr(GPIOC) => 2,
        @intFromPtr(GPIOD) => 3,
        @intFromPtr(GPIOE) => 4,
        @intFromPtr(GPIOF) => 5,
        @intFromPtr(GPIOG) => 6,
        else => unreachable,
    };

    const position: u2 = @truncate(gpio.pin >> 2);
    const offset: u5 = 4 * (@as(u5, position) & 3);
    const clear: u32 = ~(@as(u32, 0x0f) << offset);
    const value: u32 = @as(u32, port) << offset;

    switch (position) {
        0 => {
            const reg = &AFIO.EXTICR1;
            reg.raw &= clear;
            reg.raw |= value;
        },
        1 => {
            const reg = &AFIO.EXTICR2;
            reg.raw &= clear;
            reg.raw |= value;
        },
        2 => {
            const reg = &AFIO.EXTICR3;
            reg.raw &= clear;
            reg.raw |= value;
        },
        3 => {
            const reg = &AFIO.EXTICR4;
            reg.raw &= clear;
            reg.raw |= value;
        },
    }

    const rising = exti.edge == .rising or exti.edge == .both;
    const falling = exti.edge == .falling or exti.edge == .both;

    if (rising) {
        EXTI.RTSR.raw |= gpio.mask();
    } else {
        EXTI.RTSR.raw &= ~gpio.mask();
    }

    if (falling) {
        EXTI.FTSR.raw |= gpio.mask();
    } else {
        EXTI.FTSR.raw &= ~gpio.mask();
    }

    if (exti.type == .event) {
        EXTI.EMR.raw |= gpio.mask();
    } else {
        EXTI.EMR.raw &= ~gpio.mask();
    }

    if (exti.type == .interrupt) {
        EXTI.IMR.raw |= gpio.mask();
    } else {
        EXTI.IMR.raw &= ~gpio.mask();
    }
}

pub inline fn mask(gpio: GPIO) u16 {
    return @as(u16, 1) << gpio.pin;
}

pub inline fn read(gpio: GPIO) u1 {
    return @intFromBool((gpio.port.IDR.raw & gpio.mask()) != 0);
}

pub inline fn write(gpio: GPIO, value: u1) void {
    switch (value) {
        0 => gpio.port.BSRR.raw = gpio.mask() << 16,
        1 => gpio.port.BSRR.raw = gpio.mask(),
    }
}

pub inline fn toggle(gpio: GPIO) void {
    gpio.port.ODR.raw ^= gpio.mask();
}

/// Config registers
///     [ CNF[1:0] | MODE[1:0] ]
///     4          2           0
pub const Config = packed union {
    input: Input,
    output: Output,

    pub fn isInput(config: Config) bool {
        const info: u4 = @bitCast(config);
        return info & 1 != 0;
    }

    pub fn isOutput(config: Config) bool {
        return !config.isInput();
    }
};

/// For input
///     MODE[1:0] = 00
///     CNF[1:0] type
pub const Input = packed struct(u4) {
    reserved: u2 = 0,
    type: enum(u2) { analog, floating, pull } = .floating, // CNF
};

/// For output
///     MODE[1:0] speed
///     CNF[1:0] drain and function
pub const Output = packed struct(u4) {
    speed: enum(u2) { reserved, s10MHz, s2MHz, s50MHz } = .s2MHz, // MODE
    drain: enum(u1) { push_pull, open } = .push_pull, // CFN[0]
    function: enum(u1) { general_purpose, alternate } = .general_purpose, // CNF[1]
};

pub const Pull = enum { up, down };

pub const Exti = struct {
    type: enum { interrupt, event },
    edge: enum { rising, falling, both },
};
