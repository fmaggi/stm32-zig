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

pub fn asbolute() Absolute {
    return @enumFromInt(hal.getTick());
}

pub const Absolute = enum(u32) {
    _,

    pub inline fn isReachedAfter(self: Absolute, timeout: ?u32) bool {
        const n = timeout orelse return false;
        return hal.getTick() - self.to_ms() > n;
    }

    pub inline fn to_ms(self: Absolute) u32 {
        return @intFromEnum(self);
    }
};
