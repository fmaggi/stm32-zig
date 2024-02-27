const chip = @import("chip");

const interrupts = @import("interrupts.zig");

const FLASH = chip.peripherals.FLASH;

pub fn init() void {
    FLASH.ACR.modify(.{ .PRFTBE = 1 });
    interrupts.setNVICPriorityGroup(.g4);
}
