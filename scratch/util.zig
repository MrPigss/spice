pub fn returnType(comptime func: anytype) type {
    return switch (@typeInfo(@TypeOf(func))) {
        .@"fn" => |x| x.return_type orelse void,
        else => @compileError("Func should be a function"),
    };
}
