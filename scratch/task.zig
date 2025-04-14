const std = @import("std");

pub const Task = packed struct {
    const Self = @This();
    func: *const anyopaque,

    pub fn init(func: anytype) Self {
        std.debug.assert(@typeInfo(@TypeOf(func)).@"fn");

        return .{
            .func = func,
        };
    }
};
