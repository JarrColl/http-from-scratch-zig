//TODO: Support the oha test while using keep-alive
const std = @import("std");
const net = std.net;
const thread = std.Thread;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Logs from your program will appear here!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var thread_pool: thread.Pool = undefined;
    try thread_pool.init(.{ .allocator = alloc });
    defer thread_pool.deinit();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();
        try stdout.print("client connected!\n", .{});

        try thread_pool.spawn(processConnection, .{connection});
        std.debug.print("Queue Size: {}\n", .{thread_pool.run_queue.len()});
        // const handle = try thread.spawn(.{}, processConnection, .{connection});
        // handle.detach();
    }
}

pub fn handleError(connection: net.Server.Connection) void {
    connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
}

pub fn processConnection(connection: net.Server.Connection) void {
    defer connection.stream.close();

    var request_buffer: [1024]u8 = undefined;
    _ = connection.stream.read(&request_buffer) catch handleError(connection);

    // printAllChars(&request_buffer);
    var entire_request_iterator = std.mem.split(u8, &request_buffer, "\r\n");

    var request_line_iterator = std.mem.split(u8, entire_request_iterator.next() orelse "", " ");
    _ = request_line_iterator.next(); // Request type
    const route = request_line_iterator.next() orelse "";
    _ = request_line_iterator.next(); // HTTP Version, \r\n hasn't been stripped out yet. Do I need to check for \r\n before moving on to the headers?

    var headers: [32]Header = undefined; // put this on the heap to not have a max size????
    extractHeaders(&headers, &entire_request_iterator) catch handleError(connection);

    get(route, &headers, connection) catch handleError(connection);
}

pub fn get(route: []const u8, headers: []const Header, connection: net.Server.Connection) !void {
    // std.debug.print("\nROUTE:: {s}\n", .{route});
    var buf: [128]u8 = undefined;

    if (std.mem.startsWith(u8, route, "/echo/")) {
        try connection.stream.writer().print("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ route[6..].len, route[6..] });
    } else if (std.mem.startsWith(u8, route, "/user-agent")) {
        for (headers) |header| {
            // std.debug.print("\n{s}\n", .{header.name});
            if (std.mem.eql(u8, std.ascii.lowerString(&buf, header.name), "user-agent")) {
                try connection.stream.writer().print("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ header.value.len, header.value });
                return;
            }
        }
        try connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n");
    } else if (std.mem.eql(u8, route, "/")) {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

pub fn extractHeaders(headers: []Header, header_iterator: *std.mem.SplitIterator(u8, std.mem.DelimiterType.sequence)) !void {
    var header_i: u16 = 0;
    while (header_iterator.next()) |header| : (header_i += 1) { // check for double \r\n and then break.
        // std.debug.print("{!}\n", .{splitHeader(header)});
        if (header.len == 0) break;

        headers[header_i] = try splitHeader(header); // TODO: Catch this error
    }
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
