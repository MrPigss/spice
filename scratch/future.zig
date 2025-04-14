const util = @import("util.zig");
const std = @import("std");
const Task = @import("task.zig").Task;

const logger = std.log.scoped(.Future);

pub const Future = struct {
    const Self = @This();
    pool: *anyopaque,

    pub fn init(pool: anytype) Self {
        return .{ .pool = pool };
    }

    pub fn deinit(self: *const Self) void {
        self.* = undefined;
    }

    pub fn fork(self: *const Self, comptime func: anytype) util.returnType(func) {
        _ = self;
        logger.debug("forked: {}", .{@TypeOf(func)});
        return 1;
        // const task: *Task() = self.pool.taskpool.create();
        // TODO: setup task like `task.* = .{func=func, blablabla}
    }
};
