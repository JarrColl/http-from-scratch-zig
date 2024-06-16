const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    defer connection.stream.close();

    var request_buffer: [1024]u8 = undefined;

    _ = try connection.stream.read(&request_buffer);

    var it = std.mem.split(u8, &request_buffer, " ");
    var i: u8 = 0; // Is it possible to send the request that overflows this and crashes.
    while (it.next()) |split| : (i += 1) {
        if (i == 1) {
            if (std.mem.eql(u8, split, "/")) {
                try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
            } else {
                try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
            }

            std.debug.print("{s}", .{split});
        }
    }

    try stdout.print("client connected!", .{});
}
