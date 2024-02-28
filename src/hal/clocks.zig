const std = @import("std");

const assert = std.debug.assert;
const comptimePrint = std.fmt.comptimePrint;

const chip = @import("chip");
const peripherals = chip.peripherals;
const RCC = peripherals.RCC;
const FLASH = peripherals.FLASH;

const MHz = 1_000_000;

pub const ConfigError = error{FailedToSetLatency};

pub const Configuration = struct {
    sys: Oscillator = HSI.oscillator(null),
    ahb_frequency: ?u32 = null,
    apb1_frequency: ?u32 = null,
    apb2_frequency: ?u32 = null,
    pll: ?PLL = null,

    pub fn apply(comptime config: Configuration) ConfigError!void {
        const checked = comptime config.check();
        try checked.apply();
    }

    fn check(comptime config: Configuration) CheckedConfig {
        const sys_freq = config.sys.frequency();
        if (sys_freq > 72 * MHz) {
            @compileError(comptimePrint("Sys frequency is too high. Max frequency: 72 MHz, got {} MHz", .{sys_freq / MHz}));
        }

        const latency: u3 = comptime if (sys_freq <= 24 * MHz)
            0b000
        else if (sys_freq <= 48 * MHz)
            0b001
        else
            0b010;

        return .{
            .sys = config.sys,
            .pll = comptime config.getPLL(),
            .hsi = comptime config.getHSI(),
            .hse = comptime config.getHSE(),
            .hpre = comptime config.getHPRE(),
            .ppre1 = comptime config.getPPRE1(),
            .ppre2 = comptime config.getPPRE2(),
            .latency = latency,
        };
    }

    fn getHSI(comptime config: Configuration) ?HSI {
        if (config.sys.getHSI()) |hsi| {
            return hsi;
        }

        if (config.pll) |pll| {
            return pll.getHSI();
        }

        return null;
    }

    fn getHSE(comptime config: Configuration) ?HSE {
        const hse = blk: {
            if (config.sys.getHSE()) |hse| {
                break :blk hse;
            }

            if (config.pll) |pll| {
                break :blk pll.getHSE() orelse return null;
            }

            return null;
        };

        const f = hse.frequency;
        if (f < 4 * MHz or f > 16 * MHz) {
            @compileError(comptimePrint("Invalid HSE oscillator: {}. Valid range is from 4 MHz to 16 MHz", .{f / MHz}));
        }

        return hse;
    }

    fn getPLL(comptime config: Configuration) ?PLL {
        const pll = blk: {
            if (config.sys.getPLL()) |sys_pll| {
                if (config.pll) |pll| {
                    // If config.pll is present, make sure they match
                    if (!std.meta.eql(sys_pll, pll)) {
                        @compileError("Sys PLL source doesn't match PLL configuration");
                    }
                }
                break :blk sys_pll;
            }
            break :blk config.pll orelse return null;
        };

        if (pll.frequency > 72 * MHz) {
            @compileError(comptimePrint("PLL frequency is too high. Max frequency: 72 MHz, got {} MHz", .{pll.frequency / MHz}));
        }
        comptime {
            // make sure multiplier is ok!
            const m = pll.multiplier();
            _ = m;
        }

        return pll;
    }

    fn getHPRE(comptime config: Configuration) u4 {
        const sys_freq = config.sys.frequency();
        const ahb_freq = config.ahb_frequency orelse sys_freq;

        if (ahb_freq > 72 * MHz) {
            @compileError(comptimePrint("AHB frequency is too high. Max frequency: 72 MHz, got {} MHz", .{ahb_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for AHB: {} Hz\n", .{ahb_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..10) |i| {
            if (i != 5) {
                msg = msg ++ comptimePrint("\t{} Hz\n", .{sys_freq >> i});
            }
        }

        const div = comptime std.math.divExact(u32, sys_freq, ahb_freq) catch @compileError(msg);
        return switch (div) {
            1 => 0b0000,
            2 => 0b1000,
            4 => 0b1001,
            8 => 0b1011,
            16 => 0b1011,
            64 => 0b1100,
            128 => 0b1101,
            256 => 0b1101,
            512 => 0b1111,
            else => @compileError(msg),
        };
    }

    fn getPPRE1(comptime config: Configuration) u3 {
        const sys_freq = config.sys.frequency();
        const ahb_freq = config.ahb_frequency orelse sys_freq;
        const apb1_freq = config.apb1_frequency orelse if (ahb_freq <= 36 * MHz) ahb_freq else 36 * MHz;
        if (apb1_freq > 36 * MHz) {
            @compileError(comptimePrint("APB1 frequency is too high. Max frequency: 36 MHz, got {} MHz", .{apb1_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for APB1: {} Hz\n", .{apb1_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..5) |i| {
            msg = msg ++ comptimePrint("\t{} Hz\n", .{ahb_freq >> i});
        }

        const div = comptime std.math.divExact(u32, ahb_freq, apb1_freq) catch @compileError(msg);
        return switch (div) {
            1 => 0b000,
            2 => 0b100,
            4 => 0b101,
            8 => 0b110,
            16 => 0b111,
            else => @compileError(msg),
        };
    }

    fn getPPRE2(comptime config: Configuration) u3 {
        const sys_freq = config.sys.frequency();
        const ahb_freq = config.ahb_frequency orelse sys_freq;
        const apb2_freq = config.apb1_frequency orelse if (ahb_freq <= 72 * MHz) ahb_freq else 72 * MHz;
        if (apb2_freq > 72 * MHz) {
            @compileError(comptimePrint("APB2 frequency is too high. Max frequency: 72 MHz, got {} MHz", .{apb2_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for APB2: {} Hz\n", .{apb2_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..5) |i| {
            msg = msg ++ comptimePrint("\t{} Hz\n", .{ahb_freq >> i});
        }

        const div = comptime std.math.divExact(u32, ahb_freq, apb2_freq) catch @compileError(msg);
        return switch (div) {
            1 => 0b000,
            2 => 0b100,
            4 => 0b101,
            8 => 0b110,
            16 => 0b111,
            else => @compileError(msg),
        };
    }
};

const CheckedConfig = struct {
    sys: Oscillator,
    hpre: u4,
    ppre1: u3,
    ppre2: u3,
    latency: u3,

    hsi: ?HSI = null,
    hse: ?HSE = null,
    pll: ?PLL = null,

    pub fn apply(comptime config: CheckedConfig) ConfigError!void {
        if (comptime config.hsi) |o| o.turnOn();
        if (comptime config.hse) |_| HSE.turnOn() else HSE.turnOff();
        if (comptime config.pll) |o| o.turnOn() else PLL.turnOff();

        if (config.latency > FLASH.ACR.read().LATENCY) {
            FLASH.ACR.modify(.{ .LATENCY = config.latency });
            if (FLASH.ACR.read().LATENCY != config.latency) return ConfigError.FailedToSetLatency;
        }

        // Make sure sys source is on
        while (!config.sys.isOn()) {}

        // Set the highest APBx dividers in order to ensure that we do not go through
        // a non-spec phase whatever we decrease or increase HCLK.
        RCC.CFGR.modify(.{
            .PPRE1 = 0b111,
            .PPRE2 = 0b111,
        });

        RCC.CFGR.modify(.{ .HPRE = config.hpre });

        const source_num: u2 = @intFromEnum(config.sys);
        RCC.CFGR.modify(.{ .SW = source_num });
        while (RCC.CFGR.read().SWS != source_num) {}

        RCC.CFGR.modify(.{
            .PPRE1 = config.ppre1,
            .PPRE2 = config.ppre2,
        });

        if (comptime config.hsi == null) {
            HSI.turnOff();
        }
    }
};

pub const HSI = struct {
    pub const Frequency = 8 * MHz;
    trim: u5 = 0x10,

    pub fn oscillator(comptime trim: ?u5) Oscillator {
        return .{
            .hsi = .{
                .trim = trim orelse 0x10,
            },
        };
    }

    pub fn turnOn(hsi: HSI) void {
        RCC.CR.modify(.{
            .HSITRIM = hsi.trim,
            .HSION = 1,
        });

        while (!isOn()) {}
    }

    pub fn turnOff() void {
        RCC.CR.modify(.{
            .HSION = 0,
        });

        while (RCC.CR.read().HSIRDY != 0) {}
    }

    pub fn isOn() bool {
        return RCC.CR.read().HSIRDY == 1;
    }
};

pub const HSE = struct {
    frequency: u32 = 8 * MHz,

    pub fn oscillator(comptime frequency: ?u32) Oscillator {
        return .{
            .hse = .{
                .frequency = frequency orelse 8 * MHz,
            },
        };
    }

    pub fn turnOn() void {
        RCC.CR.modify(.{
            .HSEON = 1,
        });

        while (!isOn()) {}
    }

    pub fn turnOff() void {
        RCC.CR.modify(.{
            .HSEON = 0,
        });

        while (RCC.CR.read().HSERDY != 0) {}
    }

    pub fn isOn() bool {
        return RCC.CR.read().HSERDY == 1;
    }
};

pub const PLL = struct {
    pub const Source = union(enum) {
        hsi_div2: HSI,
        hse: HSE,
        hse_div2: HSE,
    };
    oscillator: Source,
    frequency: u32,

    pub fn fromHSI(comptime hsi: HSI, comptime frequency: u32) PLL {
        return .{
            .oscillator = .{ .hsi_div2 = hsi },
            .frequency = frequency,
        };
    }

    pub fn fromHSE(comptime hse: HSE, comptime div2: bool, comptime frequency: u32) PLL {
        const s: Source = if (div2)
            .{ .hse_div2 = hse }
        else
            .{ .hse = hse };

        return .{
            .oscillator = s,
            .frequency = frequency,
        };
    }

    pub fn asOscillator(comptime pll: PLL) Oscillator {
        return .{ .pll = pll };
    }

    pub fn getHSI(comptime pll: PLL) ?HSI {
        return switch (pll.oscillator) {
            .hsi_div2 => |o| o,
            .hse, .hse_div2 => null,
        };
    }

    pub fn getHSE(comptime pll: PLL) ?HSE {
        return switch (pll.oscillator) {
            .hsi_div2 => null,
            .hse, .hse_div2 => |o| o,
        };
    }

    pub inline fn turnOn(comptime pll: PLL) void {
        turnOff();

        const m = comptime pll.multiplier();

        switch (pll.oscillator) {
            .hsi_div2 => {
                RCC.CFGR.modify(.{ .PLLSRC = 0, .PLLMUL = m });
            },
            .hse => {
                RCC.CFGR.modify(.{ .PLLSRC = 1, .PLLXTPRE = 0, .PLLMUL = m });
            },
            .hse_div2 => {
                RCC.CFGR.modify(.{ .PLLSRC = 1, .PLLXTPRE = 1, .PLLMUL = m });
            },
        }

        RCC.CR.modify(.{ .PLLON = 1 });
        while (!isOn()) {}
    }

    pub inline fn turnOff() void {
        RCC.CR.modify(.{ .PLLON = 0 });
        while (PLL.isOn()) {}
    }

    pub inline fn isOn() bool {
        return RCC.CR.read().PLLRDY == 1;
    }

    pub fn multiplier(comptime pll: PLL) u4 {
        const source_freq = switch (pll.oscillator) {
            .hsi_div2 => 4 * MHz,
            .hse => |o| o.frequency,
            .hse_div2 => |o| o.frequency / 2,
        };

        comptime var msg: []const u8 = comptimePrint(
            "Invalid PLL frequency {} MHz for source frequency {} MHz\n",
            .{
                pll.frequency / MHz,
                source_freq / MHz,
            },
        ) ++ "Valid frequencies are: \n";

        inline for (2..17) |i| {
            msg = msg ++ comptimePrint("\t{} MHz\n", .{(source_freq * i) / MHz});
        }

        const m = comptime std.math.divExact(u32, pll.frequency, source_freq) catch @compileError(msg);
        if (m < 2 or m > 16) {
            @compileError(msg);
        }
        return @truncate(m - 2);
    }
};

pub const Oscillator = union(enum) {
    hsi: HSI,
    hse: HSE,
    pll: PLL,

    pub fn getHSI(comptime oscillator: Oscillator) ?HSI {
        return switch (oscillator) {
            .hsi => |o| o,
            .hse => null,
            .pll => |pll| pll.getHSI(),
        };
    }

    pub fn getHSE(comptime oscillator: Oscillator) ?HSE {
        return switch (oscillator) {
            .hsi => null,
            .hse => |o| o,
            .pll => |pll| pll.getHSE(),
        };
    }

    pub fn getPLL(comptime oscillator: Oscillator) ?PLL {
        return switch (oscillator) {
            .pll => |pll| pll,
            else => null,
        };
    }

    pub inline fn turnOn(comptime oscillator: Oscillator) void {
        switch (oscillator) {
            .hsi => |o| o.turnOn(),
            .hse => HSE.turnOn(),
            .pll => |pll| pll.turnOn(),
        }
    }

    pub inline fn turnOff(comptime oscillator: Oscillator) void {
        switch (oscillator) {
            .hsi => HSI.turnOff(),
            .hse => HSE.turnOff(),
            .pll => |pll| pll.turnOff(),
        }
    }

    pub inline fn isOn(comptime oscillator: Oscillator) bool {
        return switch (oscillator) {
            .hsi => HSI.isOn(),
            .hse => HSE.isOn(),
            .pll => PLL.isOn(),
        };
    }

    pub inline fn frequency(comptime oscillator: Oscillator) u32 {
        return switch (oscillator) {
            .hsi => HSI.Frequency,
            .hse => |o| o.frequency,
            .pll => |pll| pll.frequency,
        };
    }
};
