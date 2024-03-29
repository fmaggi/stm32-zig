// This is just a mess to try things out. Please don't look to much here :)

const std = @import("std");

const hal = @import("hal.zig");

const chip = @import("chip");
const app = @import("app");

const dma = @import("dma.zig");

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

    pub const DMA1_Channel1 = makeIRQ("DMA1_Channel1");
    pub const DMA1_Channel2 = makeIRQ("DMA1_Channel2");
    pub const DMA1_Channel3 = makeIRQ("DMA1_Channel3");
    pub const DMA1_Channel4 = makeIRQ("DMA1_Channel4");
    pub const DMA1_Channel5 = makeIRQ("DMA1_Channel5");
    pub const DMA1_Channel6 = makeIRQ("DMA1_Channel6");
    pub const DMA1_Channel7 = makeIRQ("DMA1_Channel7");
};

const EXTI = chip.peripherals.EXTI;

fn getMask(pin: u4) u32 {
    return @as(u32, 1) << pin;
}

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
        if (@hasDecl(Callbacks, "GPIO0")) {
            const mask = comptime getMask(0);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO0();
            }
        }
    }

    pub fn EXTI1() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO1")) {
            const mask = comptime getMask(1);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO1();
            }
        }
    }

    pub fn EXTI2() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO2")) {
            const mask = comptime getMask(2);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO2();
            }
        }
    }

    pub fn EXTI3() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO3")) {
            const mask = comptime getMask(3);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO3();
            }
        }
    }

    pub fn EXTI4() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO4")) {
            const mask = comptime getMask(4);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO4();
            }
        }
    }

    pub fn EXTI9_5() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO5")) {
            const mask = comptime getMask(5);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO5();
            }
        }
        if (@hasDecl(Callbacks, "GPIO6")) {
            const mask = comptime getMask(6);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO6();
            }
        }
        if (@hasDecl(Callbacks, "GPIO7")) {
            const mask = comptime getMask(7);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO7();
            }
        }
        if (@hasDecl(Callbacks, "GPIO8")) {
            const mask = comptime getMask(8);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO8();
            }
        }
        if (@hasDecl(Callbacks, "GPIO9")) {
            const mask = comptime getMask(9);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO9();
            }
        }
    }

    pub fn EXTI15_10() callconv(.C) void {
        if (@hasDecl(Callbacks, "GPIO10")) {
            const mask = comptime getMask(10);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO10();
            }
        }
        if (@hasDecl(Callbacks, "GPIO11")) {
            const mask = comptime getMask(11);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO11();
            }
        }
        if (@hasDecl(Callbacks, "GPIO12")) {
            const mask = comptime getMask(12);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO12();
            }
        }
        if (@hasDecl(Callbacks, "GPIO13")) {
            const mask = comptime getMask(13);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO13();
            }
        }
        if (@hasDecl(Callbacks, "GPIO14")) {
            const mask = comptime getMask(14);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO14();
            }
        }
        if (@hasDecl(Callbacks, "GPIO15")) {
            const mask = comptime getMask(15);
            if (EXTI.PR.raw & mask != 0) {
                EXTI.PR.raw = mask;
                Callbacks.GPIO15();
            }
        }
    }

    pub const DMA1_Channel1 = dma.channel1IRQ;
    pub const DMA1_Channel2 = dma.channel2IRQ;
    pub const DMA1_Channel3 = dma.channel3IRQ;
    pub const DMA1_Channel4 = dma.channel4IRQ;
    pub const DMA1_Channel5 = dma.channel5IRQ;
    pub const DMA1_Channel6 = dma.channel6IRQ;
    pub const DMA1_Channel7 = dma.channel6IRQ;
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
