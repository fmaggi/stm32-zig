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
    pub const SysTick = irq("SysTick");
    pub const NMI = irq("NMI");
    pub const HardFault = irq("HardFault");
    pub const EXTI0 = irq("EXTI0");
    pub const EXTI1 = irq("EXTI1");
    pub const EXTI2 = irq("EXTI2");
    pub const EXTI3 = irq("EXTI3");
    pub const EXTI4 = irq("EXTI4");
    pub const EXTI9_5 = irq("EXTI9_5");
    pub const EXTI15_10 = irq("EXTI15_10");
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
        if (comptime buildEXTI(&.{0})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI1() callconv(.C) void {
        if (comptime buildEXTI(&.{1})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI2() callconv(.C) void {
        if (comptime buildEXTI(&.{2})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI3() callconv(.C) void {
        if (comptime buildEXTI(&.{3})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI4() callconv(.C) void {
        if (comptime buildEXTI(&.{4})) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI9_5() callconv(.C) void {
        if (comptime buildEXTI(&.{ 5, 6, 7, 8, 9 })) |cb| {
            @call(.always_inline, cb, .{});
        }
    }

    pub fn EXTI15_10() callconv(.C) void {
        if (comptime buildEXTI(&.{ 10, 11, 12, 13, 14, 15 })) |cb| {
            @call(.always_inline, cb, .{});
        }
    }
};

fn irq(comptime name: []const u8) fn () callconv(.C) ReturnType(name) {
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

fn buildEXTI(comptime lines: []const u4) ?fn () callconv(.C) void {
    const EXTI = chip.peripherals.EXTI;
    var build: bool = false;
    inline for (lines) |line| {
        const callback_name = std.fmt.comptimePrint("GPIO{}", .{line});
        build = build or @hasDecl(Callbacks, callback_name);
    }

    if (!build)
        return null;

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
