const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;

const Job = @import("Job.zig").Job;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;

fn testFn(a: u8, b: u8) u8 {
    std.Thread.sleep(std.time.ns_per_s);
    return a+b;
}

test "threadpool" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

    const gpa = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => debug_allocator.allocator(),
            .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator ,
        };
    };
    std.testing.log_level = .debug;

    defer if (gpa.deinit() == .leak) expect(false) catch @panic("MEMLEAK");

    var pool = ThreadPool(.{}).init(gpa.allocator());

    pool.start();
    defer pool.stop();

    const ret = pool.run(u8, testFn, .{1, 2});
    const a = pool.run(u8, testFn, .{1, 2});
    const b = pool.run(u8, testFn, .{1, 2});
    const c = pool.run(u8, testFn, .{1, 2});
    const d = pool.run(u8, testFn, .{1, 2});

    std.log.debug("ret: {}", .{ret});
    std.log.debug("a: {}", .{a});
    std.log.debug("b: {}", .{b});
    std.log.debug("c: {}", .{c});
    std.log.debug("d: {}", .{d});


    std.time.sleep(100 * std.time.ns_per_us);

}
