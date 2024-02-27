const chip = @import("chip");

const FLASH = chip.peripherals.FLASH;

pub fn init() void {
    FLASH.ACR.modify(.{ .PRFTBE = 1 });
}
