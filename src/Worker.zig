const std = @import("std");
const Job = @import("Job.zig");
const ThreadPool = @import("thread_pool.zig").ThreadPool;

const Self = @This();

const AtomicBool = std.atomic.Value(bool);

heartbeat: AtomicBool = AtomicBool.init(true),
pool: *anyopaque,
shared_job: *?Job,

pub fn init(pool: *anyopaque) Self {
    return Self {
        .pool = pool,
    };
}

pub fn beat(self: *Self) void {
    @branchHint(.cold);

    self.mutex.lock();
    defer self.mutex.unlock();

    // If no job is being shared
    if (self.shared_job == null) {
        // And there are jobs available to start
        if (self.next_job) |job|{
            // then share that job and delete it from our list
            self.shared_job.* = job;
            self.next_job = null;
            // also signal the pool that a job is ready for starting
            self.pool.job_ready.signal();
        }
    }
    // heartbeat done.
    self.heartbeat.store(false, .monotonic);
}

pub inline fn tick(self: *Task) void {
    if (self.worker.heartbeat.load(.monotonic)) {
        self.worker.pool.heartbeat(self.worker);
    }
}
