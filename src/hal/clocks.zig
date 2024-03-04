const std = @import("std");

const assert = std.debug.assert;
const comptimePrint = std.fmt.comptimePrint;

const hal = @import("hal.zig");
const time = @import("time.zig");

const chip = @import("chip");
const peripherals = chip.peripherals;
const RCC = peripherals.RCC;
const FLASH = peripherals.FLASH;

const MHz = 1_000_000;

const Tick = struct {
    count: u32 = 0,
    frequency: u32 = 0,
};

// System core clk start with HSI as source
var system_core_clock_frequency: u32 = 8 * MHz;

pub fn systemCoreClockFrequency() u32 {
    return system_core_clock_frequency;
}

pub const ConfigError = error{
    FailedToSetLatency,
    TimeoutSys,
    TimeoutHSI,
    TimeoutHSE,
    TimeoutPLL,
    NoPLLMultiplier,
};

pub const Timeouts = struct {
    sys: u32 = 5000,
    hsi: u32 = 2,
    hse: u32 = 1000,
    pll: u32 = 2,
};

pub const Config = struct {
    sys: Oscillator = HSI.oscillator(null),
    pll: ?PLL = null,
    hclk_frequency: ?u32 = null,
    pclk1_frequency: ?u32 = null,
    pclk2_frequency: ?u32 = null,
    adc_frequency: ?u32 = null,

    pub fn apply(comptime config: Config, comptime timeouts: Timeouts) ConfigError!void {
        const checked = comptime config.check();
        try checked.apply(timeouts);
    }

    fn check(comptime config: Config) CheckedConfig {
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
            .adcpre = comptime config.getADCPRE(),
        };
    }

    fn getHSI(comptime config: Config) ?HSI {
        if (config.sys.getHSI()) |hsi| {
            return hsi;
        }

        if (config.pll) |pll| {
            return pll.getHSI();
        }

        return null;
    }

    fn getHSE(comptime config: Config) ?HSE {
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

    fn getPLL(comptime config: Config) ?PLL {
        var pll = blk: {
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

        pll.calculateMultiplier();

        return pll;
    }

    fn getHPRE(comptime config: Config) u4 {
        const sys_freq = config.sys.frequency();
        const ahb_freq = config.hclk_frequency orelse sys_freq;

        if (ahb_freq > 72 * MHz) {
            @compileError(comptimePrint("AHB frequency is too high. Max frequency: 72 MHz, got {} MHz", .{ahb_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for AHB: {} Hz\n", .{ahb_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..10) |i| {
            if (i != 5) {
                const value = sys_freq >> i;
                msg = msg ++ comptimePrint("\t{} Hz\n", .{value});
                if (value == ahb_freq) {
                    return switch (i) {
                        0 => 0b0000,
                        1 => 0b1000,
                        2 => 0b1001,
                        3 => 0b1011,
                        4 => 0b1011,
                        6 => 0b1100,
                        7 => 0b1101,
                        8 => 0b1101,
                        9 => 0b1111,
                        else => unreachable,
                    };
                }
            }
        }

        @compileError(msg);
    }

    fn getPPRE1(comptime config: Config) u3 {
        const apb1_freq = config.pclk1_frequency orelse return 0b111;
        const ahb_freq = config.hclk_frequency orelse config.sys.frequency();

        if (apb1_freq > 36 * MHz) {
            @compileError(comptimePrint("APB1 frequency is too high. Max frequency: 36 MHz, got {} MHz", .{apb1_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for APB1: {} Hz\n", .{apb1_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..5) |i| {
            const value = ahb_freq >> i;
            msg = msg ++ comptimePrint("\t{} Hz\n", .{value});
            if (apb1_freq == value) {
                return switch (i) {
                    0 => 0b000,
                    1 => 0b100,
                    2 => 0b101,
                    3 => 0b110,
                    4 => 0b111,
                    else => unreachable,
                };
            }
        }

        @compileError(msg);
    }

    fn getPPRE2(comptime config: Config) u3 {
        const apb2_freq = config.pclk2_frequency orelse return 0b111;
        const ahb_freq = config.hclk_frequency orelse config.sys.frequency();

        if (apb2_freq > 72 * MHz) {
            @compileError(comptimePrint("APB2 frequency is too high. Max frequency: 72 MHz, got {} MHz", .{apb2_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for APB2: {} Hz\n", .{apb2_freq}) ++
            "Valid frequenies are: \n";

        inline for (0..5) |i| {
            const value = ahb_freq >> i;
            msg = msg ++ comptimePrint("\t{} Hz\n", .{value});
            if (apb2_freq == value) {
                return switch (i) {
                    0 => 0b000,
                    1 => 0b100,
                    2 => 0b101,
                    3 => 0b110,
                    4 => 0b111,
                    else => unreachable,
                };
            }
        }

        @compileError(msg);
    }

    pub fn getADCPRE(comptime config: Config) u2 {
        const adc_freq = config.adc_frequency orelse return 0b11;
        const apb2_freq = config.pclk2_frequency orelse @compileError("You need to set the PCLK2 frequency to use ADC");

        if (adc_freq > 14 * MHz) {
            @compileError(comptimePrint("ADC frequency is too high. Max frequency: 14 MHz, got {} MHz", .{adc_freq / MHz}));
        }

        comptime var msg: []const u8 = comptimePrint("Invalid frequency for ADC: {} Hz\n", .{adc_freq}) ++
            "Valid frequenies are: \n";

        inline for (1..5) |i| {
            const value = apb2_freq / (2 * i);
            msg = msg ++ comptimePrint("\t{} Hz\n", .{value});
            if (adc_freq == value) return i - 1;
        }

        @compileError(msg);
    }
};

const CheckedConfig = struct {
    sys: Oscillator,
    hpre: u4,
    ppre1: u3,
    ppre2: u3,
    adcpre: u2,
    latency: u3,

    hsi: ?HSI = null,
    hse: ?HSE = null,
    pll: ?PLL = null,

    pub fn apply(config: CheckedConfig, timeouts: Timeouts) ConfigError!void {
        if (config.hsi) |o| try o.turnOn(timeouts.hsi);
        if (config.hse) |_| try HSE.turnOn(timeouts.hse) else try HSE.turnOff(timeouts.hse);
        if (config.pll) |o| try o.turnOn(timeouts.pll) else try PLL.turnOff(timeouts.pll);

        if (config.latency > FLASH.ACR.read().LATENCY) {
            FLASH.ACR.modify(.{ .LATENCY = config.latency });
            if (FLASH.ACR.read().LATENCY != config.latency) return ConfigError.FailedToSetLatency;
        }

        {
            // Make sure sys source is on
            const delay = time.timeout_ms(timeouts.sys);
            while (config.sys.isOn()) {
                if (delay.isReached()) return ConfigError.TimeoutSys;
            }
        }

        // Set the highest APBx dividers in order to ensure that we do not go through
        // a non-spec phase whatever we decrease or increase HCLK.
        RCC.CFGR.modify(.{
            .PPRE1 = 0b111,
            .PPRE2 = 0b111,
            .ADCPRE = 0b11,
        });

        RCC.CFGR.modify(.{ .HPRE = config.hpre });

        const source_num: u2 = @intFromEnum(config.sys);
        if (RCC.CFGR.read().SWS != source_num) {
            RCC.CFGR.modify(.{ .SW = source_num });
            // Make sure sys source is selected
            const delay = time.timeout_ms(timeouts.sys);
            while (RCC.CFGR.read().SWS != source_num) {
                if (delay.isReached()) return ConfigError.TimeoutSys;
            }
        }

        RCC.CFGR.modify(.{
            .PPRE1 = config.ppre1,
            .PPRE2 = config.ppre2,
            .ADCPRE = config.adcpre,
        });

        // aparently system core clock is after ahb
        const hpre_table = [16]u4{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 6, 7, 8, 9 };
        system_core_clock_frequency = config.sys.frequency() >> hpre_table[config.hpre];

        if (config.hsi == null) {
            try HSI.turnOff(timeouts.hsi);
        }

        hal.configTick();
    }
};

pub const HSI = struct {
    pub const Frequency = 8 * MHz;
    trim: u5 = 0x10,

    pub fn oscillator(trim: ?u5) Oscillator {
        return .{
            .hsi = .{
                .trim = trim orelse 0x10,
            },
        };
    }

    pub fn turnOn(hsi: HSI, timeout: u32) !void {
        RCC.CR.modify(.{
            .HSITRIM = hsi.trim,
            .HSION = 1,
        });

        const delay = time.timeout_ms(timeout);
        while (!isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutHSI;
        }
    }

    pub fn turnOff(timeout: u32) !void {
        RCC.CR.modify(.{
            .HSION = 0,
        });

        const delay = time.timeout_ms(timeout);
        while (isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutHSI;
        }
    }

    pub fn isOn() bool {
        return RCC.CR.read().HSIRDY == 1;
    }
};

pub const HSE = struct {
    frequency: u32 = 8 * MHz,

    pub fn oscillator(frequency: ?u32) Oscillator {
        return .{
            .hse = .{
                .frequency = frequency orelse 8 * MHz,
            },
        };
    }

    pub fn turnOn(timeout: u32) !void {
        RCC.CR.modify(.{
            .HSEON = 1,
        });

        const delay = time.timeout_ms(timeout);
        while (!isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutHSE;
        }
    }

    pub fn turnOff(timeout: u32) !void {
        RCC.CR.modify(.{
            .HSEON = 0,
        });

        const delay = time.timeout_ms(timeout);
        while (isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutHSE;
        }
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
    source: Source,
    frequency: u32,
    multiplier: ?u4 = null,

    pub fn fromHSI(hsi: HSI, frequency: u32) PLL {
        return .{
            .source = .{ .hsi_div2 = hsi },
            .frequency = frequency,
        };
    }

    pub fn fromHSE(hse: HSE, div2: bool, frequency: u32) PLL {
        const s: Source = if (div2)
            .{ .hse_div2 = hse }
        else
            .{ .hse = hse };

        return .{
            .oscillator = s,
            .frequency = frequency,
        };
    }

    pub fn asOscillator(pll: PLL) Oscillator {
        return .{ .pll = pll };
    }

    pub fn getHSI(pll: PLL) ?HSI {
        return switch (pll.source) {
            .hsi_div2 => |o| o,
            .hse, .hse_div2 => null,
        };
    }

    pub fn getHSE(pll: PLL) ?HSE {
        return switch (pll.source) {
            .hsi_div2 => null,
            .hse, .hse_div2 => |o| o,
        };
    }

    pub inline fn turnOn(pll: PLL, timeout: u32) ConfigError!void {
        try turnOff(timeout);

        const m = pll.multiplier orelse return ConfigError.NoPLLMultiplier;

        switch (pll.source) {
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

        const delay = time.timeout_ms(timeout);
        while (!isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutPLL;
        }
    }

    pub inline fn turnOff(timeout: u32) !void {
        RCC.CR.modify(.{ .PLLON = 0 });

        const delay = time.timeout_ms(timeout);
        while (isOn()) {
            if (delay.isReached()) return ConfigError.TimeoutPLL;
        }
    }

    pub inline fn isOn() bool {
        return RCC.CR.read().PLLRDY == 1;
    }

    pub fn calculateMultiplier(comptime pll: *PLL) void {
        const source_freq = switch (pll.source) {
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

        inline for (2..17) |m| {
            msg = msg ++ comptimePrint("\t{} MHz\n", .{(source_freq * m) / MHz});
            if (source_freq * m == pll.frequency) {
                pll.multiplier = @truncate(m - 2);
                return;
            }
        }

        @compileError(msg);
    }
};

pub const Oscillator = union(enum) {
    hsi: HSI,
    hse: HSE,
    pll: PLL,

    pub fn getHSI(oscillator: Oscillator) ?HSI {
        return switch (oscillator) {
            .hsi => |o| o,
            .hse => null,
            .pll => |pll| pll.getHSI(),
        };
    }

    pub fn getHSE(oscillator: Oscillator) ?HSE {
        return switch (oscillator) {
            .hsi => null,
            .hse => |o| o,
            .pll => |pll| pll.getHSE(),
        };
    }

    pub fn getPLL(oscillator: Oscillator) ?PLL {
        return switch (oscillator) {
            .pll => |pll| pll,
            else => null,
        };
    }

    pub inline fn turnOn(oscillator: Oscillator, timeout: u32) !void {
        switch (oscillator) {
            .hsi => |o| try o.turnOn(timeout),
            .hse => try HSE.turnOn(timeout),
            .pll => |pll| try pll.turnOn(timeout),
        }
    }

    pub inline fn turnOff(oscillator: Oscillator, timeout: u32) !void {
        switch (oscillator) {
            .hsi => try HSI.turnOff(timeout),
            .hse => try HSE.turnOff(timeout),
            .pll => |pll| try pll.turnOff(timeout),
        }
    }

    pub inline fn isOn(oscillator: Oscillator) bool {
        return switch (oscillator) {
            .hsi => HSI.isOn(),
            .hse => HSE.isOn(),
            .pll => PLL.isOn(),
        };
    }

    pub inline fn frequency(oscillator: Oscillator) u32 {
        return switch (oscillator) {
            .hsi => HSI.Frequency,
            .hse => |o| o.frequency,
            .pll => |pll| pll.frequency,
        };
    }
};
