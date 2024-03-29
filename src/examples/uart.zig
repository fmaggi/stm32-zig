const hal = @import("hal");
const USART = hal.USART;

pub fn main() void {
    hal.init();

    const uart = USART.USART1;
    uart.apply(.{});

    while (true) {
        uart.transmitBlocking("hello, world!", null) catch unreachable;
        var buf: [10]u8 = undefined;
        uart.readBlocking(&buf, null) catch unreachable;
    }
}
