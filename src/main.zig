const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

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

    printAllChars(&request_buffer);
    var entire_request_iterator = std.mem.split(u8, &request_buffer, "\r\n");

    var request_line_iterator = std.mem.split(u8, entire_request_iterator.next() orelse "", " ");
    _ = request_line_iterator.next(); // Request type

    const target = request_line_iterator.next() orelse "";
    var target_iterator = std.mem.split(u8, target, "/");

    _ = target_iterator.next(); // ""
    const route = target_iterator.next() orelse "";

    _ = request_line_iterator.next(); // HTTP Version, \r\n hasn't been stripped out yet. Do I need to check for \r\n before moving on to the headers?

    var headers: [32]Header = undefined; // put this on the heap to not have a max size.
    var header_i: u16 = 0;
    while (entire_request_iterator.next()) |header| : (header_i += 1) { // check for double \r\n and then break.
        // std.debug.print("{!}\n", .{splitHeader(header)});
        if (header.len == 0) break;

        headers[header_i] = try splitHeader(header); // TODO: Catch this error
    }
    std.debug.print("ROUTE:: {s}", .{route});

    if (std.mem.eql(u8, route, "echo")) {
        const echo_value = target_iterator.next() orelse "";
        try connection.stream.writeAll(try std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ echo_value.len, echo_value }));
    } else if (std.mem.eql(u8, route, "user-agent")) {
        for (headers) |header| {
            if (std.mem.eql(u8, header.name, "User-Agent")) {
                try connection.stream.writeAll(try std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ header.value.len, header.value }));
                break;
            }
        } else {
            try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n"); //TODO: Change to an error return
        }
    } else if (std.mem.eql(u8, route, "")) {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }

    // var i: u8 = 0; // Is it possible to send the request that overflows this and crashes.
    // while (request_iterator.next()) |split| : (i += 1) {
    // }

    try stdout.print("client connected!", .{});
}

const Header = struct {
    name: []const u8,
    value: []const u8,
};

const splitHeaderError = error{NullFound};
fn splitHeader(string: []const u8) splitHeaderError!Header {
    var header_iterator = std.mem.split(u8, string, ": ");
    return Header{
        .name = header_iterator.next() orelse return splitHeaderError.NullFound,
        .value = header_iterator.next() orelse return splitHeaderError.NullFound,
    };
}

pub fn printAllChars(chars: []const u8) void {
    for (chars) |c| {
        if (c == '\n') {
            std.debug.print("{s}", .{"\\n"});
        } else if (c == '\r') {
            std.debug.print("{s}", .{"\\r"});
        } else {
            std.debug.print("{c}", .{c});
        }
    }
    std.debug.print("\n", .{});
}
