const std = @import("std");

const chip = @import("chip.zig");
pub const types = chip.types;

const STM32F103 = chip.devices.STM32F103;
pub const peripherals = STM32F103.peripherals;
pub const memory = STM32F103.memory;
pub const VectorTable = STM32F103.VectorTable;
pub const properties = STM32F103.properties;

const app = @import("app");

export fn _start() noreturn {
    // NOTE: for some reason @memcpy and @memset bloat the binary and it doesn't fit in .text

    // fill .bss with zeroes
    {
        @setRuntimeSafety(false);
        const bss_start: [*]u8 = @ptrCast(&sections._start_bss);
        const bss_end: [*]u8 = @ptrCast(&sections._end_bss);
        const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

        for (0..bss_len) |i| {
            bss_start[i] = 0;
        }
    }

    // load .data from flash
    {
        @setRuntimeSafety(false);
        const data_start: [*]u8 = @ptrCast(&sections._start_data);
        const data_end: [*]u8 = @ptrCast(&sections._end_data);
        const data_len = @intFromPtr(data_end) - @intFromPtr(data_start);
        const data_src: [*]const u8 = @ptrCast(&sections._start_load_data);

        for (0..data_len) |i| {
            data_start[i] = data_src[i];
        }
    }

    const info: std.builtin.Type.Fn = @typeInfo(@TypeOf(app.main)).Fn;

    if (info.params.len > 0)
        @compileError("Main function needs to have 0 parameters");

    const return_type = info.return_type orelse @compileError("Unkown main return type");

    switch (@typeInfo(return_type)) {
        .ErrorUnion => app.main() catch @panic("!"),
        .Void => app.main(),
        .Int => {
            const ret_val = app.main();
            if (ret_val != 0) {
                @panic("!");
            }
        },
        else => @compileError("Invalid main return type: " ++ @typeName(return_type)),
    }

    while (true) {}
}

pub const std_options = struct {
    pub const logFn = if (@hasDecl(app, "logFn"))
        app.logFn
    else
        _logFn;
};

fn _logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = message_level;
    _ = scope;
    _ = format;
    _ = args;
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("{s}\n", .{message});
    if (@import("builtin").mode == .Debug) {
        @breakpoint();
    }
    while (true) {}
}

const sections = struct {
    extern var _start_load_data: u8;
    extern var _start_data: u8;
    extern var _end_data: u8;
    extern var _start_bss: u8;
    extern var _end_bss: u8;
};

fn wrap(comptime func: anytype) fn () callconv(.C) void {
    const S = struct {
        pub fn wrapper() callconv(.C) void {
            @call(.always_inline, func, .{});
        }
    };
    return S.wrapper;
}

export const vector: VectorTable linksection(".isr_vector") = blk: {
    const RAM = memory.RAM;
    const Handler = VectorTable.Handler;
    var _vector: VectorTable = .{
        .initial_stack_pointer = RAM.start + RAM.length,
        .Reset = .{ .C = _start },
    };

    if (@hasDecl(app, "VectorTable")) {
        const main_vector = app.VectorTable;

        if (@hasDecl(main_vector, "initial_stack_pointer"))
            @compileError("main cannot override initial stack pointer");

        if (@hasDecl(main_vector, "Reset"))
            @compileError("main cannot override Reset vector");

        for (@typeInfo(main_vector).Struct.decls) |decl| {
            if (@hasField(VectorTable, decl.name)) {
                const v = @field(main_vector, decl.name);
                const info: std.builtin.Type.Fn = @typeInfo(@TypeOf(v)).Fn;
                const handler: Handler = switch (info.calling_convention) {
                    .C => .{ .C = v },
                    .Naked => .{ .Naked = v },
                    .Unspecified => .{ .C = wrap(v) },
                    else => @compileError("Invalid calling convention on " ++ decl.name ++ ". Use .C or .Naked"),
                };

                @field(_vector, decl.name) = handler;
            } else {
                @compileError("Unkown interrupt vector: " ++ decl.name);
            }
        }
    }

    break :blk _vector;
};
