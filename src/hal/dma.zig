const std = @import("std");

const chip = @import("chip");

const time = @import("time.zig");

// Blue pill only has C 1
const DMA1 = chip.peripherals.DMA1;
const RCC = chip.peripherals.RCC;

var callbacks: [7]Callbacks = [_]Callbacks{.{}} ** 7;
var running: [7]bool = [_]bool{false} ** 7;

pub const Error = error{ Busy, TransferError, Timeout };

pub const Callbacks = struct {
    on_completion: ?*const fn () void = null,
    on_half: ?*const fn () void = null,
    on_error: ?*const fn () void = null,
};

pub inline fn enable() void {
    RCC.AHBENR.modify(.{ .DMA1EN = 1 });
}

pub const TransferOptions = struct {
    priority: enum(u2) { low, medium, high, very_high } = .low,
    // circular: bool = false,
    callbacks: Callbacks = .{},
};

pub inline fn read(comptime T: type, comptime from: Peripheral, to: []T, options: TransferOptions) Error!Transfer {
    const word_len = switch (T) {
        u8 => .byte,
        u16 => .half_word,
        u32 => .word,
        else => @compileError("DMA: Invalid data type " ++ @typeName(T)),
    };

    return Channel.transfer(
        comptime from.channel(.from),
        comptime from.address(),
        @intFromPtr(to.ptr),
        word_len,
        to.len,
        true,
        options,
    );
}

pub inline fn write(comptime T: type, from: []T, comptime to: Peripheral, options: TransferOptions) Error!Transfer {
    const word_len: u2 = switch (T) {
        u8 => .byte,
        u16 => .half_word,
        u32 => .word,
        else => @compileError("DMA: Invalid data type " ++ @typeName(T)),
    };

    return Channel.transfer(
        comptime to.channel(.to),
        comptime to.address(),
        @intFromPtr(from.ptr),
        word_len,
        from.len,
        true,
        options,
    );
}

pub const Transfer = struct {
    channel: Channel,

    pub fn deinit(self: Transfer) void {
        const index = @intFromEnum(self.channel);
        const pos = index * 4;
        DMA1.IFCR.raw = @as(u32, 0b1) << pos;
        running[index] = false;
    }

    pub fn abort(self: Transfer) void {
        self.deinit();
        const regs = self.channel.regs();

        regs.CR.modify(.{
            .TCIE = 0,
            .HTIE = 0,
            .TEIE = 0,
            .EN = 0,
        });
    }

    pub fn remaining(self: Transfer) u16 {
        return self.channel.regs().NDTR.read().NDT;
    }

    pub fn isDone(self: Transfer) Error!bool {
        if (self.channel.regs().CR.read().EN == 0) {
            return true;
        }

        const index = @intFromEnum(self.channel);

        const pos = index * 4;
        const mask = @as(u32, 0b1111) << pos;
        const s = (DMA1.ISR.raw & mask) >> pos;

        if (s & 0b1000 != 0) {
            self.abort();
            return Error.TransferError;
        }

        if (s & 0b0010 != 0) {
            self.deinit();
            return true;
        }

        return self.remaining() == 0;
    }

    pub fn wait(self: Transfer, timeout: ?u32) Error!void {
        const delay = time.timeout_ms(timeout);

        while (!try self.isDone()) {
            if (delay.isReached()) return Error.Timeout;
        }
    }
};

pub const Peripheral = union(enum) {
    pub const Direction = enum { from, to };

    adc1,
    spi: enum { one, two },
    i2s,
    usart: enum { one, two, three },
    i2c: enum { one, two },
    // tim1: enum {},
    // tim2: enum {},
    // tim3: enum {},
    // tim4: enum {},

    pub fn address(periph: Peripheral) u32 {
        return switch (periph) {
            .adc1 => @intFromPtr(&ADC1.DR),
            .usart => |i| switch (i) {
                .one => @intFromPtr(&USART1.DR),
                .two => @intFromPtr(&USART2.DR),
                .three => @intFromPtr(&USART3.DR),
            },
            else => 0,
        };
    }

    pub fn channel(periph: Peripheral, direction: Direction) Channel {
        return switch (periph) {
            .adc1 => .C1,
            .spi => |i| switch (i) {
                .one => if (direction == .from) .C2 else .C3,
                .two => if (direction == .from) .C4 else .C5,
            },
            .i2s => if (direction == .from) .C4 else .C5,
            .usart => |i| switch (i) {
                .one => if (direction == .from) .C5 else .C4,
                .two => if (direction == .from) .C6 else .C7,
                .three => if (direction == .from) .C3 else .C2,
            },
            .i2c => |i| switch (i) {
                .one => if (direction == .from) .C7 else .C6,
                .two => if (direction == .from) .C5 else .C4,
            },
        };
    }

    const ADC1 = chip.peripherals.ADC1;
    const USART1 = chip.peripherals.USART1;
    const USART2 = chip.peripherals.USART2;
    const USART3 = chip.peripherals.USART3;
};

pub const Channel = enum(u3) {
    C1,
    C2,
    C3,
    C4,
    C5,
    C6,
    C7,

    pub fn regs(channel: Channel) *volatile Registers {
        return switch (channel) {
            .C1 => R1,
            .C2 => R2,
            .C3 => R3,
            .C4 => R4,
            .C5 => R5,
            .C6 => R6,
            .C7 => R7,
        };
    }

    pub fn transfer(
        channel: Channel,
        periph_address: u32,
        mem_address: u32,
        word_len: enum(u2) { byte, half_word, word },
        mem_len: usize,
        mem_inc: bool,
        options: TransferOptions,
    ) Error!Transfer {
        const index = @intFromEnum(channel);
        if (running[index]) return Error.Busy;

        running[index] = true;
        callbacks[index] = options.callbacks;

        const registers = channel.regs();

        // Clear all interrupts
        const pos = index * 4;
        DMA1.IFCR.raw = @as(u32, 0b1111) << pos;

        registers.CR.modify(.{
            .TCIE = @intFromBool(options.callbacks.on_completion != null),
            .HTIE = @intFromBool(options.callbacks.on_half != null),
            .TEIE = @intFromBool(options.callbacks.on_error != null),
            // .CIRC = @intFromBool(options.circular),
            .CIRC = 0,
            .MINC = @intFromBool(mem_inc),
            .PINC = 0,
            .MSIZE = @intFromEnum(word_len),
            .PSIZE = @intFromEnum(word_len),
            .PL = @intFromEnum(options.priority),
        });

        registers.PAR.raw = periph_address;
        registers.MAR.raw = mem_address;
        registers.NDTR.modify(.{ .NDT = @as(u16, @truncate(mem_len)) });

        registers.CR.modify(.{ .EN = 1 });
        _ = registers.CR.read().EN;

        return .{ .channel = channel };
    }

    pub const R1: *volatile Registers = @ptrCast(&DMA1.CCR1);
    pub const R2: *volatile Registers = @ptrCast(&DMA1.CCR2);
    pub const R3: *volatile Registers = @ptrCast(&DMA1.CCR3);
    pub const R4: *volatile Registers = @ptrCast(&DMA1.CCR4);
    pub const R5: *volatile Registers = @ptrCast(&DMA1.CCR5);
    pub const R6: *volatile Registers = @ptrCast(&DMA1.CCR6);
    pub const R7: *volatile Registers = @ptrCast(&DMA1.CCR7);

    pub const Registers = extern struct {
        CR: @TypeOf(DMA1.CCR1),
        NDTR: @TypeOf(DMA1.CNDTR1),
        PAR: @TypeOf(DMA1.CPAR1),
        MAR: @TypeOf(DMA1.CMAR1),
    };
};

pub fn channel1IRQ() callconv(.C) void {
    const cbs = callbacks[0];
    if (DMA1.ISR.read().TCIF1 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF1 = 1 });
        running[0] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel2IRQ() callconv(.C) void {
    const cbs = callbacks[1];
    if (DMA1.ISR.read().TCIF2 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF2 = 1 });
        running[1] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel3IRQ() callconv(.C) void {
    const cbs = callbacks[2];
    if (DMA1.ISR.read().TCIF3 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF3 = 1 });
        running[2] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel4IRQ() callconv(.C) void {
    const cbs = callbacks[3];
    if (DMA1.ISR.read().TCIF4 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF4 = 1 });
        running[3] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel5IRQ() callconv(.C) void {
    const cbs = callbacks[4];
    if (DMA1.ISR.read().TCIF5 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF5 = 1 });
        running[4] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel6IRQ() callconv(.C) void {
    const cbs = callbacks[5];
    if (DMA1.ISR.read().TCIF6 == 1) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF6 = 1 });
        running[5] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

pub fn channel7IRQ() callconv(.C) void {
    const cbs = callbacks[6];
    if (DMA1.ISR.read().TCIF7) {
        // Clear bit flag
        DMA1.IFCR.modify(.{ .CTCIF7 = 1 });
        running[6] = false;
        if (cbs.on_completion) |cb| {
            cb();
        }
    }
}

fn onCompletionMask(comptime i: comptime_int) u32 {
    return i;
}

pub fn DMA1_IRQ() callconv(.C) void {
    inline for (0..7) |i| {
        const mask = comptime onCompletionMask(i);
        if (DMA1.ISR.raw & mask) {
            DMA1.IFCR.raw = mask;
            running[i] = false;
            if (callbacks[i].on_completion) |onc| {
                onc();
            }
        }
    }
}
