const std = @import("std");

const clocks = @import("clocks.zig");

const hal = @import("hal.zig");

const SCALE = if (@import("builtin").mode == .Debug) 20 else 1;

pub fn delay_us(us: u32) void {
    var wait_loop_index = us * (clocks.systemCoreClockFrequency() / 1_000_000) / SCALE;
    while (wait_loop_index != 0) {
        wait_loop_index -= 1;
    }
}

pub fn delay_ms(ms: u32) void {
    delay_us(ms * 1000);
}

pub fn timeout_ms(ms: u32) Timeout {
    const now = hal.getTick();
    return @enumFromInt(now + ms);
}

pub const Timeout = enum(u32) {
    _,

    pub fn isReached(timeout: Timeout) bool {
        return hal.getTick() >= timeout.to_ms();
    }

    pub fn to_ms(timeout: Timeout) u32 {
        return @intFromEnum(timeout);
    }
};
