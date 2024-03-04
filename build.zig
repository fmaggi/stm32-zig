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

    const hal = b.addModule("hal", .{
        .root_source_file = .{ .path = "src/hal/hal.zig" },
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
        .pic = false,
    });

    exe.link_gc_sections = true;
    exe.link_data_sections = true;
    exe.link_function_sections = true;
    exe.pie = false;

    exe.root_module.addImport("app", app);
    exe.root_module.addImport("hal", hal);

    hal.addImport("chip", &exe.root_module);
    hal.addImport("app", app);

    app.addImport("chip", &exe.root_module);
    app.addImport("hal", hal);

    exe.setLinkerScript(.{ .path = "linker.ld" });

    b.installArtifact(exe);
}

pub fn buildExamples(b: *std.Build) void {
    const examples = &.{"blinky"};

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });
    const optimize = b.standardOptimizeOption(.{});

    const hal = b.addModule("hal", .{
        .root_source_file = .{ .path = "src/hal/hal.zig" },
        .target = target,
        .optimize = optimize,
    });

    for (examples) |example| {
        const source = b.fmt("src/examples/{}.zig", .{example});
        const artifact = b.fmt("stm32-zig-{}.elf", .{example});
        const app = b.addModule(example, .{
            .root_source_file = .{ .path = source },
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = artifact,
            .root_source_file = .{ .path = "src/chip/start.zig" },
            .target = target,
            .optimize = optimize,
            .code_model = .small,
            .linkage = .static,
            .single_threaded = true,
            .pic = false,
        });

        exe.link_gc_sections = true;
        exe.link_data_sections = true;
        exe.link_function_sections = true;
        exe.pie = false;

        exe.root_module.addImport("hal", hal);
        exe.root_module.addImport("app", app);

        hal.addImport("chip", &exe.root_module);
        hal.addImport("app", app);

        app.addImport("chip", &exe.root_module);
        app.addImport("hal", hal);

        exe.setLinkerScript(.{ .path = "linker.ld" });

        b.installArtifact(exe);
    }
}
