const std = @import("std");

const examples = &.{
    "blinky",
    "blinky_irq",
    "adc",
    "adc_dma",
    "button",
    "button_irq",
    "uart",
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });
    const optimize = b.standardOptimizeOption(.{});

    const flash_cmd = b.addSystemCommand(&.{
        "/home/fran/.local/stm32/STM32CubeProgrammer/bin/STM32_Programmer_CLI",
        "-c",
        "port=SWD",
        "mode=UR",
        "reset=HWrst",
    });

    const server_cmd = b.addSystemCommand(&.{
        "ST-LINK_gdbserver",                                "-p", "61234", "-l", "1",      "-d", "-z", "61235", "-s", "-cp",
        "/home/fran/.local/stm32/STM32CubeProgrammer/bin/", "-m", "0",     "-k", "--halt",
    });

    const debugger_cmd = b.addSystemCommand(&.{
        "arm-none-eabi-gdb",
        "-ex",
        "target remote localhost:61234",
    });

    inline for (examples) |example| {
        const hal = b.addModule("hal", .{
            .root_source_file = .{ .path = "src/hal/hal.zig" },
            .target = target,
            .optimize = optimize,
        });

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

        flash_cmd.step.dependOn(&exe.step);
        server_cmd.step.dependOn(&exe.step);
        debugger_cmd.step.dependOn(&exe.step);
    }

    if (b.args) |args| {
        const name = b.getInstallPath(.bin, b.fmt("stm32-zig-{s}.elf", .{args[0]}));
        flash_cmd.addArgs(&.{
            "-w",
            name,
            "--verify",
        });
        debugger_cmd.addArg(name);
    }

    const flash_step = b.step("flash", "Flash the program");
    flash_step.dependOn(&flash_cmd.step);

    server_cmd.step.dependOn(&flash_cmd.step);
    const server_step = b.step("server", "Start the server");
    server_step.dependOn(&server_cmd.step);

    const debug_step = b.step("debug", "Debug the program");
    debug_step.dependOn(&debugger_cmd.step);
}
