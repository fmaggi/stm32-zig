const std = @import("std");

const chip = @import("chip");
const interrupts = @import("interrupts.zig");

const Port = chip.types.peripherals.GPIOA;

const RCC = chip.peripherals.RCC;
const AFIO = chip.peripherals.AFIO;
const EXTI = chip.peripherals.EXTI;

const GPIOA = chip.peripherals.GPIOA;
const GPIOB = chip.peripherals.GPIOB;
const GPIOC = chip.peripherals.GPIOC;
const GPIOD = chip.peripherals.GPIOD;
const GPIOE = chip.peripherals.GPIOE;
const GPIOF = chip.peripherals.GPIOF;
const GPIOG = chip.peripherals.GPIOG;

const GPIO = @This();

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

pub inline fn mask(gpio: GPIO) u16 {
    return @as(u16, 1) << gpio.pin;
}

/// For input
///     MODE[1:0] = 00
///     CNF[1:0] kind
pub const Input = packed struct(u4) {
    reserved: u2 = 0,
    kind: enum(u2) { analog, floating, pull } = .floating, // CNF
};

pub const InputOptions = struct {
    config: Input = .{},
    pull: ?Pull = null,
    exti: ?Exti = null,
};

pub fn asInput(gpio: GPIO, options: InputOptions) void {
    std.debug.assert(options.config.reserved == 0);
    // Should I do this?
    if (options.pull) |pull| {
        gpio.setConfig(.{ .input = .{ .kind = .pull } });
        gpio.setPull(pull);
    } else {
        gpio.setConfig(.{ .input = options.config });
    }

    if (options.exti) |e| {
        gpio.setExti(e);
    }
}

/// For output
///     MODE[1:0] speed
///     CNF[1:0] drain and function
pub const Output = packed struct(u4) {
    speed: enum(u2) { reserved, s10MHz, s2MHz, s50MHz } = .s2MHz, // MODE
    drain: enum(u1) { push_pull, open } = .push_pull, // CFN[0]
    function: enum(u1) { general_purpose, alternate } = .general_purpose, // CNF[1]
};

pub fn asOutput(gpio: GPIO, config: Output) void {
    std.debug.assert(config.speed != .reserved);
    gpio.setConfig(.{ .output = config });
}

/// Config registers
///     [ CNF[1:0] | MODE[1:0] ]
///     4          2           0
pub const Config = packed union {
    input: Input,
    output: Output,

    pub fn isInput(config: Config) bool {
        const info: u4 = @bitCast(config);
        return info & 0b11 == 0;
    }

    pub fn isOutput(config: Config) bool {
        return !config.isInput();
    }
};

pub fn setConfig(gpio: GPIO, config: Config) void {
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

pub const Pull = enum { up, down };

pub fn setPull(gpio: GPIO, pull: Pull) void {
    switch (pull) {
        .up => gpio.port.BSRR.raw = gpio.mask(),
        .down => gpio.port.BRR.raw = gpio.mask(),
    }
}

pub const Exti = struct {
    pub const Edge = enum { rising, falling, both };

    pub fn interrupt(edge: Edge) Exti {
        return .{
            .kind = .interrupt,
            .edge = edge,
        };
    }

    pub fn event(edge: Edge) Exti {
        return .{
            .kind = .event,
            .edge = edge,
        };
    }

    kind: enum { interrupt, event },
    edge: Edge,
    priority: interrupts.Priority = .{},
};

pub fn setExti(gpio: GPIO, exti: Exti) void {
    RCC.APB2ENR.modify(.{ .AFIOEN = 1 });
    _ = RCC.APB2ENR.read().AFIOEN;

    const port: u4 = switch (@intFromPtr(gpio.port)) {
        @intFromPtr(GPIOA) => 0,
        @intFromPtr(GPIOB) => 1,
        @intFromPtr(GPIOC) => 2,
        @intFromPtr(GPIOD) => 3,
        @intFromPtr(GPIOE) => 4,
        @intFromPtr(GPIOF) => 5,
        @intFromPtr(GPIOG) => 6,
        else => unreachable,
    };

    // pin 0  -> EXTICR1 -> 0
    // pin 1  -> EXTICR1 -> 1
    // pin 2  -> EXTICR1 -> 2
    // pin 3  -> EXTICR1 -> 3
    // pin 4  -> EXTICR2 -> 0
    // pin 5  -> EXTICR2 -> 1
    // pin 6  -> EXTICR2 -> 2
    // pin 7  -> EXTICR2 -> 3
    // pin 8  -> EXTICR3 -> 0
    // pin 9  -> EXTICR3 -> 1
    // pin 10 -> EXTICR3 -> 2
    // pin 11 -> EXTICR3 -> 3
    // pin 12 -> EXTICR4 -> 0
    // pin 13 -> EXTICR4 -> 1
    // pin 14 -> EXTICR4 -> 2
    // pin 15 -> EXTICR4 -> 3
    const cr_index: u2 = @truncate(gpio.pin >> 2);
    const index: u2 = @truncate(gpio.pin & 0b11);

    const control_registers: [*]volatile @TypeOf(AFIO.EXTICR1) = @ptrCast(&AFIO.EXTICR1);
    var control_register: [*]volatile u4 = @ptrCast(&control_registers[cr_index]);
    control_register[index] = port;

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

    if (exti.kind == .event) {
        EXTI.EMR.raw |= gpio.mask();
    } else {
        EXTI.EMR.raw &= ~gpio.mask();
    }

    if (exti.kind == .interrupt) {
        EXTI.IMR.raw |= gpio.mask();
    } else {
        EXTI.IMR.raw &= ~gpio.mask();
    }

    const interrupt = gpio.interruptLine();
    interrupt.setPriority(exti.priority);
    interrupt.enable();
}

pub fn interruptLine(gpio: GPIO) interrupts.DeviceInterrupt {
    return switch (gpio.pin) {
        0 => .EXTI0,
        1 => .EXTI1,
        2 => .EXTI2,
        3 => .EXTI3,
        4 => .EXTI4,
        5, 6, 7, 8, 9 => .EXTI9_5,
        10, 11, 12, 13, 14, 15 => .EXTI15_10,
    };
}
