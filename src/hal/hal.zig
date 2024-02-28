const chip = @import("chip");

const interrupts = @import("interrupts.zig");

pub fn init() void {
    const FLASH = chip.peripherals.FLASH;
    reset(); // debug purposes
    FLASH.ACR.modify(.{ .PRFTBE = 1 });
    interrupts.setNVICPriorityGroup(.g4);
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
