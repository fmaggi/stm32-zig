// This is just a mess to try things out. Please don't look to much here :)

const std = @import("std");

const hal = @import("hal.zig");

const chip = @import("chip");
const app = @import("app");

const Callbacks = if (@hasDecl(app, "Callbacks"))
    app.Callbacks
else
    struct {
        pub const EMTPY = 1; // Make the compiler happy
    };

pub const VectorTable = struct {
    pub const SysTick = makeIRQ("SysTick");
    pub const NMI = makeIRQ("NMI");
    pub const HardFault = makeIRQ("HardFault");
    pub const EXTI0 = makeIRQ("EXTI0");
    pub const EXTI1 = makeIRQ("EXTI1");
    pub const EXTI2 = makeIRQ("EXTI2");
    pub const EXTI3 = makeIRQ("EXTI3");
    pub const EXTI4 = makeIRQ("EXTI4");
    pub const EXTI9_5 = makeIRQ("EXTI9_5");
    pub const EXTI15_10 = makeIRQ("EXTI15_10");
};

// Weird experiment with EXTIs. I dont know if I will keep them like this
const HalVectorTable = struct {
    pub fn SysTick() callconv(.C) void {
        @call(.always_inline, hal.incrementTick, .{});
    }

    pub fn NMI() callconv(.C) noreturn {
        @panic("NMI");
    }

    pub fn HardFault() callconv(.C) noreturn {
        @panic("HardFault");
    }

    pub fn EXTI0() callconv(.C) void {
        if (comptime makeEXTI(&.{0})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI1() callconv(.C) void {
        if (comptime makeEXTI(&.{1})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI2() callconv(.C) void {
        if (comptime makeEXTI(&.{2})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI3() callconv(.C) void {
        if (comptime makeEXTI(&.{3})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI4() callconv(.C) void {
        if (comptime makeEXTI(&.{4})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI9_5() callconv(.C) void {
        if (comptime makeEXTI(&.{ 5, 6, 7, 8, 9 })) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI15_10() callconv(.C) void {
        if (comptime makeEXTI(&.{ 10, 11, 12, 13, 14, 15 })) |cb| {
            @call(.always_inline, cb, .{});
        }
    }
};

fn makeIRQ(comptime name: []const u8) fn () callconv(.C) ReturnType(name) {
    if (!@hasDecl(app, "VectorTable")) return @field(HalVectorTable, name);

    const AppVectorTable = app.VectorTable;

    return if (@hasDecl(AppVectorTable, name))
        @field(AppVectorTable, name)
    else
        @field(HalVectorTable, name);
}

fn ReturnType(comptime name: []const u8) type {
    const f = @field(HalVectorTable, name);
    const info = @typeInfo(@TypeOf(f)).Fn;
    return info.return_type.?;
}

fn makeEXTI(comptime lines: []const u4) ?fn () callconv(.C) void {
    const EXTI = chip.peripherals.EXTI;
    blk: {
        inline for (lines) |line| {
            const callback_name = std.fmt.comptimePrint("GPIO{}", .{line});
            if (@hasDecl(Callbacks, callback_name)) break :blk;
        }
        return null;
    }

    return struct {
        pub fn Fn() callconv(.C) void {
            inline for (lines) |line| {
                const callback_name = std.fmt.comptimePrint("GPIO{}", .{line});
                if (comptime @hasDecl(Callbacks, callback_name)) {
                    const mask: u32 = comptime @as(u32, 1) << line;
                    if (EXTI.PR.raw & mask != 0) {
                        EXTI.PR.raw &= ~mask;
                        return @call(.auto, @field(Callbacks, callback_name), .{});
                    }
                }
            }
        }
    }.Fn;
}
