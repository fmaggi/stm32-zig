const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });
    const optimize = b.standardOptimizeOption(.{});

    const app = b.addModule("app", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "stm32-zig.elf",
        .root_source_file = .{ .path = "src/chip/start.zig" },
        .target = target,
        .optimize = optimize,
        .code_model = .small,
        .linkage = .static,
        .single_threaded = true,
    });

    exe.link_gc_sections = true;
    exe.link_data_sections = true;
    exe.link_function_sections = true;

    exe.root_module.addImport("app", app);
    app.addImport("chip", &exe.root_module);

    exe.setLinkerScript(.{ .path = "linker.ld" });

    b.installArtifact(exe);
}
