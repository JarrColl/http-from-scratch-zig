const std = @import("std");
const gzip = std.compress.gzip;

pub fn main() !void {
    //
    const string: []const u8 = "abc";
    var fba = std.io.fixedBufferStream(string);
    // var stdout = std.io.getStdOut();

    var buffer_test: [1024]u8 = undefined;
    var fba_test = std.io.fixedBufferStream(&buffer_test);

    try gzip.compress(fba.reader(), fba_test.writer(), .{});

    std.debug.print("DEBUGGGGERING: {d}", .{buffer_test});
}
