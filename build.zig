const std = @import("std");

pub fn build(b: *std.Build) void {
    const build_examples = b.option(bool, "examples", "Build examples (default = false)") orelse false;
    if (build_examples) {
        buildExamples(b);
    } else {
        buildTest(b);
    }

    const args = b.args orelse &[_][]const u8{""};
    const name = args[0];
    const formatted_name = b.fmt("zig-out/bin/stm32-zig-{s}.elf", .{name});
    const flash_cmd = b.addSystemCommand(&.{
        "/home/fran/.local/stm32/STM32CubeProgrammer/bin/STM32_Programmer_CLI",
        "-c",
        "port=SWD",
        "mode=UR",
        "reset=HWrst",
        "-w",
        formatted_name,
        "--verify",
    });

    const flash_step = b.step("flash", "Flash the program");
    flash_step.dependOn(&flash_cmd.step);

    const server_cmd = b.addSystemCommand(&.{
        "ST-LINK_gdbserver",                                "-p", "61234", "-l", "1",      "-d", "-z", "61235", "-s", "-cp",
        "/home/fran/.local/stm32/STM32CubeProgrammer/bin/", "-m", "0",     "-k", "--halt",
    });
    server_cmd.step.dependOn(&flash_cmd.step);
    const server_step = b.step("server", "server");
    server_step.dependOn(&server_cmd.step);

    const debugger_cmd = b.addSystemCommand(&.{
        "arm-none-eabi-gdb", formatted_name,
    });

    const debug_step = b.step("debug", "Debug the program");
    debug_step.dependOn(&debugger_cmd.step);

    // debug: flash
    // 	ST-LINK_gdbserver -p 61234 -l 1 -d -z 61235 -s -cp $(PROGRAMMER_DIR) -m 0 -k --halt &
    // 	arm-none-eabi-gdb $(TARGET) -ex "target remote localhost:61234"
    //
    // clean:
    // 	make -C Debug -j4 clean
    //
}

pub fn buildTest(b: *std.Build) void {
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
        .linkage = .static,
    });

    exe.link_gc_sections = true;
    exe.link_data_sections = true;
    exe.link_function_sections = true;

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
    const examples: []const []const u8 = &.{"blinky"};

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
        const source = b.fmt("src/examples/{s}.zig", .{example});
        const artifact = b.fmt("stm32-zig-{s}.elf", .{example});
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
        });

        exe.link_gc_sections = true;
        exe.link_data_sections = true;
        exe.link_function_sections = true;

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
