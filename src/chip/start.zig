const std = @import("std");

const chip = @import("chip.zig");
pub const types = chip.types;

const STM32F103 = chip.devices.STM32F103;
pub const peripherals = STM32F103.peripherals;
pub const memory = STM32F103.memory;
pub const VectorTable = STM32F103.VectorTable;
pub const properties = STM32F103.properties;

const app = @import("app");
const hal = @import("hal");

pub export fn _start() callconv(.C) noreturn {

    // fill .bss with zeroes
    {
        const bss_start: [*]u8 = @ptrCast(&sections._start_bss);
        const bss_len = @intFromPtr(&sections._size_bss);

        for (0..bss_len) |i| {
            bss_start[i] = 0;
        }
    }

    // load .data from flash
    {
        const data_start: [*]u8 = @ptrCast(&sections._start_data);
        const data_len = @intFromPtr(&sections._size_data);
        const data_src: [*]const u8 = @ptrCast(&sections._end_text);

        for (0..data_len) |i| {
            data_start[i] = data_src[i];
        }
    }

    app.main();

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
    extern var _end_text: u8;
    extern var _start_data: u8;
    extern var _size_data: u8;
    extern var _start_bss: u8;
    extern var _size_bss: u8;
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
    if (@hasDecl(hal, "VectorTable")) {
        break :blk createVectorTable(hal.VectorTable);
    }

    if (@hasDecl(app, "VectorTable")) {
        break :blk createVectorTable(app.VectorTable);
    }

    const RAM = memory.RAM;
    break :blk .{
        .initial_stack_pointer = RAM.start + RAM.length - 8,
        .Reset = .{ .C = _start },
    };
};

fn createVectorTable(comptime vector_table: type) VectorTable {
    const RAM = memory.RAM;
    const Handler = VectorTable.Handler;
    var vt: VectorTable = .{
        .initial_stack_pointer = RAM.start + RAM.length - 8,
        .Reset = .{ .C = _start },
    };

    if (@hasDecl(vector_table, "initial_stack_pointer"))
        @compileError("Cannot override initial stack pointer");

    if (@hasDecl(vector_table, "Reset"))
        @compileError("Cannot override Reset vector");

    for (@typeInfo(vector_table).Struct.decls) |decl| {
        if (@hasField(VectorTable, decl.name)) {
            const v = @field(vector_table, decl.name);

            const info = @typeInfo(@TypeOf(v));
            if (info != .Fn) continue;

            const fn_info = @typeInfo(@TypeOf(v)).Fn;
            const handler: Handler = switch (fn_info.calling_convention) {
                .C => .{ .C = v },
                .Naked => .{ .Naked = v },
                .Unspecified => .{ .C = wrap(v) },
                else => @compileError("Invalid calling convention on " ++ decl.name ++ ". Use .C or .Naked"),
            };

            @field(vt, decl.name) = handler;
        } else {
            @compileError("Unkown interrupt vector: " ++ decl.name);
        }
    }

    return vt;
}
