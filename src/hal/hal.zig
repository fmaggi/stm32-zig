const std = @import("std");

const chip = @import("chip");

pub const GPIO = @import("GPIO.zig");
pub const adc = @import("adc.zig");
pub const clocks = @import("clocks.zig");
pub const time = @import("time.zig");
pub const interrupts = @import("interrupts.zig");
pub const USART = @import("USART.zig");
pub const dma = @import("dma.zig");

pub const VectorTable = @import("vector_table.zig").VectorTable;

pub fn init() void {
    const FLASH = chip.peripherals.FLASH;
    reset(); // debug purposes
    FLASH.ACR.modify(.{ .PRFTBE = 1 });
    interrupts.setNVICPriorityGroup(.g4);
    configTick();
}

pub fn configTick() void {
    const TICK = chip.peripherals.STK;

    // MAX clock frequency is 72 MHz. Div by 1000 uses less than 24 bits
    const ticks: u24 = @truncate(clocks.systemCoreClockFrequency() / 1000);

    TICK.LOAD_.modify(.{ .RELOAD = ticks });

    interrupts.CortexM3Interrupt.setPriority(.SysTick, .{ .preemptive = 15, .sub = 0 });

    TICK.VAL.raw = 0;
    TICK.CTRL.raw = 0b111;
}

var tick: u32 = 0;

pub fn getTick() u32 {
    return tick;
}

pub fn incrementTick() void {
    tick +%= 1;
}

pub fn reset() void {
    const RCC = chip.peripherals.RCC;
    RCC.CR.modify(.{ .HSION = 1 });
    RCC.CFGR.modify(.{
        .SW = 0,
        .HPRE = 0,
        .PPRE1 = 0,
        .PPRE2 = 0,
        .ADCPRE = 0,
        .MCO = 0,
    });
    RCC.CR.modify(.{
        .HSEON = 0,
        .CSSON = 0,
        .PLLON = 0,
        .HSEBYP = 0,
    });
    RCC.CFGR.modify(.{
        .PLLSRC = 0,
        .PLLXTPRE = 0,
        .PLLMUL = 0,
        .OTGFSPRE = 0,
    });
    RCC.CIR.raw = 0x009F0000;
}
