const chip = @import("chip");

const clocks = @import("clocks.zig");
const GPIO = @import("GPIO.zig");
const time = @import("time.zig");

const RCC = chip.peripherals.RCC;
const AFIO = chip.peripherals.AFIO;

pub const Registers = chip.types.peripherals.USART1;

pub const USART1: Self = .{ .registers = chip.peripherals.USART1 };
// TODO Implement other two
// pub const USART2: Self = .{ .registers = chip.peripherals.USART2 };
// pub const USART3: Self = .{ .registers = chip.peripherals.USART3 };

const Self = @This();

registers: *volatile Registers,

pub const Config = struct {
    baudrate: u32 = 115200,
    data_bits: DataBits = .b8,
    stop_bits: StopBits = .@"1",
    parity: Parity = .none,
    receiver: bool = true,
    transmitter: bool = true,
    remap: Remap = .none,

    pub const DataBits = enum { b8, b9 };
    pub const StopBits = enum(u2) { @"1", @"0.5", @"2", @"1.5" };
    pub const Parity = enum { none, even, odd };
    pub const Remap = enum { none, partial, full };
};

pub fn apply(self: Self, config: Config) void {
    var tx: GPIO = undefined;
    var rx: GPIO = undefined;

    switch (@intFromPtr(self.registers)) {
        @intFromPtr(USART1.registers) => {
            RCC.APB2ENR.modify(.{
                .USART1EN = 1,
                .AFIOEN = 1,
            });
            _ = RCC.APB2ENR.read().USART1EN;

            if (config.remap == .none) {
                GPIO.Port.enable(.A);
                tx = GPIO.init(.A, 9);
                rx = GPIO.init(.A, 10);
            } else {
                AFIO.MAPR.modify(.{ .USART1_REMAP = 1 });
                GPIO.Port.enable(.B);
                tx = GPIO.init(.B, 6);
                rx = GPIO.init(.B, 7);
            }
        },
        else => unreachable,
    }

    if (config.transmitter) {
        tx.asOutput(.{
            .speed = .s50MHz,
            .function = .alternate,
            .drain = .push_pull,
        });
    }

    if (config.receiver) {
        rx.asInput(.floating);
    }

    self.registers.CR2.modify(.{
        .STOP = @intFromEnum(config.stop_bits),
        .LINEN = 0,
        .CLKEN = 0,
    });

    self.registers.CR1.modify(.{
        .M = @intFromEnum(config.data_bits),
        .PCE = @intFromBool(config.parity != .none),
        .PS = if (config.parity == .odd) @as(u1, 1) else @as(u1, 0),
        .TE = @intFromBool(config.transmitter),
        .RE = @intFromBool(config.receiver),
    });

    // TODO
    self.registers.CR3.modify(.{
        .CTSE = 0,
        .RTSE = 0,
        .SCEN = 0,
        .HDSEL = 0,
        .IREN = 0,
    });

    const clock_freq = switch (@intFromPtr(self.registers)) {
        @intFromPtr(USART1.registers) => clocks.pclk2ClockFrequency(),
        else => unreachable,
    };

    self.registers.BRR.raw = calculateBRR(config.baudrate, clock_freq);

    self.registers.CR1.modify(.{ .UE = 1 });
}
pub fn flush(self: Self, timeout: ?u32) error{Timeout}!void {
    const delay = time.timeout_ms(timeout);

    while (!self.registers.SR.read().TC) {
        if (delay.isReached()) return error.Timeout;
    }
}

/// For now 9 bit data without parity bit will not work :)
pub fn transmitBlocking(self: Self, buffer: []const u8, timeout: ?u32) error{Timeout}!void {
    const delay = time.absolute();

    const regs = self.registers;
    for (buffer) |b| {
        // I may be able to remove this one?
        if (delay.isReached(timeout)) return error.Timeout;

        while (regs.SR.read().TXE != 1) {
            // Or maybe this one is not needed?
            if (delay.isReached(timeout)) return error.Timeout;
        }

        regs.DR.modify(.{ .DR = b });
    }
}

pub const ReadError = error{
    Timeout,
    Frame,
    Parity,
    Overrun,
};

pub fn readBlocking(self: Self, buffer: []u8, timeout: ?u32) ReadError!void {
    const delay = time.absolute();

    const regs = self.registers;
    for (buffer) |*b| {
        // I may be able to remove this one?
        if (delay.isReached(timeout)) return error.Timeout;

        while (!try self.checkRXflags()) {
            // Or maybe this one is not needed?
            if (delay.isReached(timeout)) return error.Timeout;
        }

        // TODO: Handle flags on 9-bit transmission
        b.* = @truncate(regs.DR.read().DR);
    }
}

pub fn checkRXflags(self: Self) ReadError!bool {
    const sr = self.registers.SR.read();
    if (sr.RXNE == 1) {
        if (sr.ORE == 1) return error.Overrun;
        if (sr.PE == 1) return error.Parity;
        if (sr.FE == 1) return error.Frame;

        return true;
    }
    return false;
}

fn calculateBRR(baud: u32, pclk: u32) u32 {
    const brr = pclk / baud;
    const rounding = ((pclk % baud) + (baud / 2)) / baud;
    return brr + rounding;
}
