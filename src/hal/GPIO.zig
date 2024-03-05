const std = @import("std");

const chip = @import("chip");
const interrupts = @import("interrupts.zig");

const RCC = chip.peripherals.RCC;
const AFIO = chip.peripherals.AFIO;
const EXTI = chip.peripherals.EXTI;

const GPIO = @This();

port: *volatile Port.Registers,
pin: u4,

pub const Port = enum(u3) {
    pub const Registers = chip.types.peripherals.GPIOA;
    pub const A = chip.peripherals.GPIOA;
    pub const B = chip.peripherals.GPIOB;
    pub const C = chip.peripherals.GPIOC;
    pub const D = chip.peripherals.GPIOD;
    pub const E = chip.peripherals.GPIOE;
    pub const F = chip.peripherals.GPIOF;
    pub const G = chip.peripherals.GPIOG;

    A,
    B,
    C,
    D,
    E,
    F,
    G,

    pub fn enable(port: Port) void {
        const offset = @intFromEnum(port) + 2;
        const bit = @as(u32, 1) << offset;
        RCC.APB2ENR.raw |= bit;
        // Delay after setting
        _ = RCC.APB2ENR.raw & bit;
    }

    pub fn fromRegisters(pointer: *const volatile Registers) Port {
        return switch (@intFromPtr(pointer)) {
            @intFromPtr(A) => .A,
            @intFromPtr(B) => .B,
            @intFromPtr(C) => .C,
            @intFromPtr(D) => .D,
            @intFromPtr(E) => .E,
            @intFromPtr(F) => .F,
            @intFromPtr(G) => .G,
            else => unreachable,
        };
    }

    pub fn registers(port: Port) *volatile Registers {
        return switch (port) {
            .A => A,
            .B => B,
            .C => C,
            .D => D,
            .E => E,
            .F => F,
            .G => G,
        };
    }
};

pub fn init(port: Port, pin: u4) GPIO {
    return .{
        .port = port.registers(),
        .pin = pin,
    };
}

pub fn read(gpio: GPIO) u1 {
    return @intFromBool((gpio.port.IDR.raw & gpio.mask()) != 0);
}

pub fn write(gpio: GPIO, value: u1) void {
    switch (value) {
        0 => gpio.port.BSRR.raw = @as(u32, gpio.mask()) << 16,
        1 => gpio.port.BSRR.raw = @as(u32, gpio.mask()),
    }
}

pub fn toggle(gpio: GPIO) void {
    gpio.port.ODR.raw ^= gpio.mask();
}

pub inline fn mask(gpio: GPIO) u16 {
    return @as(u16, 1) << gpio.pin;
}

pub const InputOptions = union(enum) {
    analog,
    floating,
    pull: Pull,
    exti: struct {
        config: Exti,
        pull: ?Pull = null,
    },
};

pub fn asInput(gpio: GPIO, options: InputOptions) void {
    switch (options) {
        .analog => gpio.setConfig(.{ .input = .{ .kind = .analog } }),
        .floating => gpio.setConfig(.{ .input = .{ .kind = .floating } }),
        .pull => |pull| {
            gpio.setConfig(.{ .input = .{ .kind = .pull } });
            gpio.setPull(pull);
        },
        .exti => |exti| {
            if (exti.pull) |pull| {
                gpio.setConfig(.{ .input = .{ .kind = .pull } });
                gpio.setPull(pull);
            } else {
                gpio.setConfig(.{ .input = .{ .kind = .floating } });
            }

            gpio.setExti(exti.config);
        },
    }
}

/// For output
///     MODE[1:0] speed
///     CNF[1:0] drain and function
pub const OutputOptions = packed struct(u4) {
    speed: enum(u2) { reserved, s10MHz, s2MHz, s50MHz } = .s2MHz, // MODE
    drain: enum(u1) { push_pull, open } = .push_pull, // CFN[0]
    function: enum(u1) { general_purpose, alternate } = .general_purpose, // CNF[1]
};

pub fn asOutput(gpio: GPIO, options: OutputOptions) void {
    std.debug.assert(options.speed != .reserved);
    gpio.setConfig(.{ .output = options });
}

/// Config registers
///     [ CNF[1:0] | MODE[1:0] ]
///     4          2           0
pub const Config = packed union {
    comptime {
        std.debug.assert(@bitSizeOf(Config) == 4);
    }

    input: packed struct(u4) {
        reserved: u2 = 0,
        kind: enum(u2) { analog, floating, pull, reserved } = .floating,
    },
    output: OutputOptions,

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
    kind: enum { interrupt, event },
    edge: enum { rising, falling, both },
    priority: interrupts.Priority = .{},
};

pub fn setExti(gpio: GPIO, exti: Exti) void {
    RCC.APB2ENR.modify(.{ .AFIOEN = 1 });
    _ = RCC.APB2ENR.read().AFIOEN;

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

    const port = @intFromEnum(Port.fromRegisters(gpio.port));
    const control_registers: *volatile [4]@TypeOf(AFIO.EXTICR1) = @ptrCast(&AFIO.EXTICR1);
    var control_register: *volatile [4]u4 = @ptrCast(&control_registers[cr_index]);
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
