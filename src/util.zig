pub fn returnType(comptime func: anytype) ?type {
    switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |x| return x.return_type,
        else => @compileError("Func should be a function"),
    }
}
