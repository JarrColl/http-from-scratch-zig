//TODO: Support the oha test while using keep-alive
//TODO: Check for accidental copies
const std = @import("std");
// const clap = @import("clap");
const net = std.net;
const thread = std.Thread;

const ServerError = error{ArgsError};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    // try stdout.print("Logs from your program will appear here!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    // const args = parseArgs(alloc) catch |err| {
    //     if (err == ServerError.ArgsError) return;
    //     return err;
    // };
    // std.debug.print("file: {s}\n", .{args.directory});
    const args = parseArgs() catch |err| {
        if (err == ServerError.ArgsError) return;
        return err;
    };
    // std.debug.print("file: {s}\n", .{args.directory});

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

        try thread_pool.spawn(processConnection, .{ args, connection, alloc });
        std.debug.print("Queue Size: {}\n", .{thread_pool.run_queue.len()});
        // const handle = try thread.spawn(.{}, processConnection, .{connection});
        // handle.detach();
    }
}

const Args = struct { directory: ?[]const u8 };

pub fn parseArgs() !Args {
    const help_message = comptime 
    \\-h, --help                            Display this help and exit.
    \\-d, --directory <str> *Required       Choose the directory to make available to the /files endpoint.\n
    ;
    const stderr = std.io.getStdErr();

    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h")) {
            try std.io.getStdIn().writeAll(help_message);
        } else if (std.mem.eql(u8, arg, "--directory") or std.mem.eql(u8, arg, "-d")) {
            if (args.next()) |directory| {
                return Args{ .directory = directory };
            } else {
                try stderr.writeAll("Please provide an argument to the --directory (-d) argument.\n");
                return ServerError.ArgsError;
            }
        }
    }

    // try stderr.writeAll(help_message);
    // return ServerError.ArgsError;
    return Args{ .directory = null };
}

// pub fn parseArgs(alloc: std.mem.Allocator) !Args {
//
//     const params = comptime clap.parseParamsComptime(
//         \\-h, --help             Display this help and exit.
//         \\-d, --directory <str>       An option parameter which can be specified multiple times.
//     );
//
//     var diag = clap.Diagnostic{};
//     var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
//         .diagnostic = &diag,
//         .allocator = alloc,
//     }) catch |err| {
//         // Report useful error and exit
//         diag.report(std.io.getStdErr().writer(), err) catch {};
//         return err;
//     };
//
//     defer res.deinit();
//
//     if (res.args.help != 0) {
//         try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
//         return ServerError.ArgsError;
//     }
//     if (res.args.directory) |f| {
//         std.fs.cwd().access(f, .{}) catch {
//             try std.io.getStdErr().writeAll("The directory could not be accessed. Please check if it exists.");
//             return ServerError.ArgsError;
//         };
//         return .{ .directory = f };
//     } else {
//         try std.io.getStdErr().writeAll("-d, --directory argument is required.");
//         return ServerError.ArgsError;
//     }
// }

pub fn handleError(connection: net.Server.Connection) void {
    connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
}

pub fn processConnection(args: Args, connection: net.Server.Connection, alloc: std.mem.Allocator) void {
    defer connection.stream.close();

    var request_buffer: [1024]u8 = undefined;
    _ = connection.stream.read(&request_buffer) catch {
        handleError(connection);
        return;
    };

    printAllChars(&request_buffer);
    var entire_request_iterator = std.mem.splitSequence(u8, &request_buffer, "\r\n");

    var info_line_iterator = std.mem.splitScalar(u8, entire_request_iterator.next() orelse "", ' ');
    const method = info_line_iterator.next() orelse ""; // Request method
    const route = info_line_iterator.next() orelse "";
    _ = info_line_iterator.next(); // HTTP Version, \r\n hasn't been stripped out yet. Do I need to check for \r\n before moving on to the headers?

    var headers_buf: [32]Header = undefined; // put this on the heap to not have a max size????
    const headers = extractHeaders(&headers_buf, &entire_request_iterator) catch {
        handleError(connection);
        return;
    };

    const body = entire_request_iterator.next() orelse "";
    std.debug.print("\nbody len: {}\n", .{body.len});

    if (std.mem.eql(u8, method, "GET")) {
        get(route, headers, args, connection, alloc) catch |err| {
            std.debug.print("Get error: {}", .{err});
            handleError(connection);
            return;
        };
    } else if (std.mem.eql(u8, method, "POST")) {
        post(route, headers, body, args, connection, alloc) catch |err| {
            std.debug.print("Post error: {}", .{err});
            handleError(connection);
            return;
        };
    } else {
        connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n") catch handleError(connection);
        return;
    }
}

pub fn get(route: []const u8, headers: []const Header, args: Args, connection: net.Server.Connection, alloc: std.mem.Allocator) !void {
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
    } else if (std.mem.startsWith(u8, route, "/files/")) {
        if (args.directory) |directory| {
            var dir = std.fs.cwd().openDir(directory, .{}) catch |err| {
                return err;
            };
            defer dir.close();

            //TODO: Ensure the file is only in the allowed dir, no ../'ing
            const file = dir.readFileAlloc(alloc, route[7..], 2000) catch |err| {
                if (err == error.FileNotFound) {
                    try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
                } else {
                    handleError(connection);
                }
                return err;
            };
            std.debug.print("{s}", .{file});

            const content_type = "application/octet-stream"; //if (std.mem.endsWith(u8, route, ".html")) "text/html" else "text/plain";

            try connection.stream.writer().print("HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}", .{ content_type, file.len, file });
        } else { // A file is requested but the directory arg was not set.
            handleError(connection);
        }
    } else if (std.mem.eql(u8, route, "/")) {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

pub fn post(route: []const u8, headers: []const Header, body: []const u8, args: Args, connection: net.Server.Connection, alloc: std.mem.Allocator) !void {
    var buf: [128]u8 = undefined;
    const stderr = std.io.getStdErr();
    _ = alloc;
    std.debug.print("POSTING", .{});
    if (std.mem.startsWith(u8, route, "/files/")) {
        if (args.directory) |directory| {
            var dir = std.fs.cwd().openDir(directory, .{}) catch |err| {
                return err;
            };
            defer dir.close();

            for (headers) |header| { // how do I stop it looping over the undefined areas
                std.debug.print("\nhello, {s}", .{header.name});
                if (std.mem.eql(u8, std.ascii.lowerString(&buf, header.name), "content-length")) {
                    const content_length = std.fmt.parseUnsigned(u32, header.value, 10) catch |err| {
                        try connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n");
                        return err;
                    }; // error means that it was invalid int.

                    // Check for issues in the request;
                    if (body.len <= 0) {
                        stderr.writeAll("/files/ post request with a 0 length body occured.") catch {};
                        break;
                    }

                    const file: std.fs.File = try dir.createFile(route[7..], .{});
                    defer file.close();
                    try file.writeAll(body[0..content_length]);

                    try connection.stream.writeAll("HTTP/1.1 201 Created\r\n\r\n");
                    return;
                }
            }

            try connection.stream.writeAll("HTTP/1.1 400 Bad Request\r\n\r\n");
        } else { // A file is requested but the directory arg was not set.
            handleError(connection);
        }
    }
}

pub fn extractHeaders(headers: []Header, header_iterator: *std.mem.SplitIterator(u8, std.mem.DelimiterType.sequence)) ![]const Header {
    var header_i: u16 = 0;
    while (header_iterator.next()) |header| : (header_i += 1) { // check for double \r\n and then break.
        std.debug.print("{s}\n", .{header});
        if (header.len == 0) break;

        headers[header_i] = try splitHeader(header); // TODO: Catch this error
    }
    return headers[0..header_i];
}

const Header = struct {
    name: []const u8,
    value: []const u8,
};

const splitHeaderError = error{NullFound};
fn splitHeader(string: []const u8) splitHeaderError!Header {
    var header_iterator = std.mem.splitSequence(u8, string, ": ");
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
