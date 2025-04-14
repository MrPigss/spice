const std = @import("std");

fn abc(a: u8) u8 {
    return a;
}
test "sometest" {
    const return_type = returnType(abc);
    if (return_type) |rt| {
        std.debug.print("{}", .{rt});
    }
}

fn returnType(comptime func: anytype) ?type {
    switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |x| return x.return_type,
        else => @compileError("Func should be a function"),
    }
}
