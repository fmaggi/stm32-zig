const std = @import("std");

const chip = @import("chip");

const SCB = chip.peripherals.SCB;
const NVIC = chip.peripherals.NVIC;
const NVIC_PRIO_BITS = chip.properties.@"cpu.nvic_prio_bits";

// TODO: Handle cortex m3 interrupts
pub const DeviceInterrupt = enum(u16) {
    WWDG = 0,
    PVD = 1,
    TAMPER = 2,
    RTC = 3,
    FLASH = 4,
    RCC = 5,
    EXTI0 = 6,
    EXTI1 = 7,
    EXTI2 = 8,
    EXTI3 = 9,
    EXTI4 = 10,
    DMA1_Channel1 = 11,
    DMA1_Channel2 = 12,
    DMA1_Channel3 = 13,
    DMA1_Channel4 = 14,
    DMA1_Channel5 = 15,
    DMA1_Channel6 = 16,
    DMA1_Channel7 = 17,
    ADC1_2 = 18,
    USB_HP_CAN1_TX = 19,
    USB_LP_CAN1_RX0 = 20,
    CAN1_RX1 = 21,
    CAN1_SCE = 22,
    EXTI9_5 = 23,
    TIM1_BRK = 24,
    TIM1_UP = 25,
    TIM1_TRG_COM = 26,
    TIM1_CC = 27,
    TIM2 = 28,
    TIM3 = 29,
    TIM4 = 30,
    I2C1_EV = 31,
    I2C1_ER = 32,
    I2C2_EV = 33,
    I2C2_ER = 34,
    SPI1 = 35,
    SPI2 = 36,
    USART1 = 37,
    USART2 = 38,
    USART3 = 39,
    EXTI15_10 = 40,
    RTC_Alarm = 41,
    USBWakeUp = 42,
    TIM8_BRK = 43,
    TIM8_UP = 44,
    TIM8_TRG_COM = 45,
    TIM8_CC = 46,
    ADC3 = 47,
    FSMC = 48,
    SDIO = 49,
    TIM5 = 50,
    SPI3 = 51,
    UART4 = 52,
    UART5 = 53,
    TIM6 = 54,
    TIM7 = 55,
    DMA2_Channel1 = 56,
    DMA2_Channel2 = 57,
    DMA2_Channel3 = 58,
    DMA2_Channel4_5 = 59,

    pub fn enable(interrupt: DeviceInterrupt) void {
        var isers: [*]volatile u32 = @ptrCast(&NVIC.ISER0);
        const index: u32 = @intFromEnum(interrupt);
        isers[index >> 5] = @as(u32, 1) << (index & 0x1f);
    }

    pub fn setPriority(interrupt: DeviceInterrupt, priority: Priority) void {
        const encoded: u16 = (@as(u16, priority.encode()) << (@as(u4, 8) - NVIC_PRIO_BITS));
        const index: u32 = @intFromEnum(interrupt);
        var ips: [*]volatile u8 = @ptrCast(&NVIC.IPR0);
        ips[index] = @truncate(encoded & 0xff);
    }
};

pub const NVICPriorityGroup = enum(u3) {
    g0 = 7,
    g1 = 6,
    g2 = 5,
    g3 = 4,
    g4 = 3,
};

pub fn setNVICPriorityGroup(group: NVICPriorityGroup) void {
    SCB.AIRCR.modify(.{
        .PRIGROUP = @intFromEnum(group),
        .VECTKEYSTAT = 0x5fA,
    });
}

pub const Priority = packed struct(u8) {
    preemptive: u4,
    sub: u4,

    pub fn encode(priority: Priority) u8 {
        const grouping = SCB.AIRCR.read().PRIGROUP;
        // grouping -> [0, 7]
        // NVIC_PRIO_BITS -> 4
        // 7 - [0-7] -> [7, 0]
        // preempt_bits -> [0, 4]
        const preempt_bits: u3 = if (@as(u3, 7) - grouping > NVIC_PRIO_BITS)
            NVIC_PRIO_BITS
        else
            @as(u3, 7 - grouping);

        // grouping -> [0, 7]
        // NVIC_PRIO_BITS -> 4
        // grouping + NVIC_PRIO_BITS -> [4, 11]
        // sub_bits -> [0, 4]
        const sub_bits: u3 = if (grouping + NVIC_PRIO_BITS < 7)
            0
        else
            (grouping - 7) + NVIC_PRIO_BITS;

        std.debug.assert(preempt_bits <= 4);
        std.debug.assert(sub_bits <= 4);

        // preempt_bits -> [0, 4]
        // sub_bits -> [0, 4]
        // mask -> [0, 15]
        // high -> u8
        const high: u8 = h_blk: {
            const mask: u4 = @truncate((@as(u5, 1) << preempt_bits) - 1);
            const high = priority.preemptive & mask;
            break :h_blk @as(u8, high) << sub_bits;
        };

        const low: u8 = l_blk: {
            const mask: u4 = @truncate((@as(u5, 1) << sub_bits) - 1);
            const low = priority.sub & mask;
            break :l_blk @as(u8, low);
        };

        return high | low;
    }
};
