const std = @import("std");
const ThreadPool = @import("threadpool.zig").ThreadPool;
const builtin = @import("builtin");
const Future = @import("future.zig").Future;

const sum_args = struct{a: u8, b: u8};

fn testFn(f: Future, args: sum_args) u8 {
    _ = f.fork(testFn);
    _ = f.fork(testFn);
    return args.a + args.b;
}


test "CreateThreadPool" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

    const gpa = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => debug_allocator.allocator(),
            .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator ,
        };
    };
    std.testing.log_level = .debug;
    var tp = ThreadPool.init(gpa, 4);
    tp.start();

    const result = tp.run(testFn, sum_args{.a=1, .b=2});
    std.debug.print("{}", .{result});
}
