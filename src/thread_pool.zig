//! This struct represents a threadpool, and acts as a namespace for
//! primitives that operate within a threadpool. For concurrency primitives that support
const Future = @import("Future.zig");
const std = @import("std");
const Order = std.math.Order;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Mutex = Thread.Mutex;

const Job = @import("Job.zig").Job;
const util = @import("util.zig");
const Worker = @import("Worker.zig");

const AtomicBool = std.atomic.Value(bool);
const JobQueue = ArrayListUnmanaged(Job);
const logger = std.log.scoped(.Threadpool);

const QueueingStrategy = union(enum) {
    /// Processes tasks in the order they were submitted (First In, First Out).
    ///
    /// Best for scenarios where:
    /// - Consistent response latency is important
    /// - Tasks have time sensitivity or "fairness" requirements
    /// - Maintaining chronological processing order matters
    ///
    /// Example: Web server request handling where each client should receive
    /// a response in the order requests were received, preventing older
    /// requests from experiencing excessive delays during traffic spikes.
    Fifo,

    /// Processes the most recently submitted tasks first (Last In, First Out).
    ///
    /// Best for scenarios where:
    /// - Overall throughput is more important than individual task latency
    /// - Tasks are independent and don't require ordering
    /// - Newer tasks might be more relevant than older ones
    ///
    /// Example: Batch processing system where completing the overall job quickly
    /// is the priority, regardless of which specific chunk is processed first.
    /// Or in work-stealing scenarios where recently enqueued tasks may have better
    /// cache locality.
    Lifo,
};
const ThreadPoolConfig = struct {
    /// Number of background worker threads in the thread pool.
    ///
    /// When null (default):
    /// - Uses the number of logical CPU cores available - 1
    /// - Determined at runtime via std.Thread.getCpuCount()
    background_worker_count: ?usize = null,

    /// Duration between worker heartbeats in nanoseconds.
    /// Workers periodically check for new tasks during each heartbeat.
    ///
    /// Heartbeats are staggered across workers to distribute polling overhead:
    /// Each worker's heartbeat occurs every [interval] nanoseconds.
    /// For N workers, every [interval/N]ns a heartbeat occurs.
    ///
    /// Example: With 10 workers and 1000ns interval:
    /// - Each worker polls every 1000ns
    /// - Workers are staggered so one poll occurs every 100ns
    /// - Total of 10 polls per 1000ns period
    heartbeat_interval: usize = 100 * std.time.ns_per_us,

    queueing_strategy: QueueingStrategy = .Lifo,
};

pub fn ThreadPool(comptime config: ThreadPoolConfig) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        heartbeat_interval: usize = config.heartbeat_interval,
        queueing_strategy: QueueingStrategy = config.queueing_strategy,

        threads: []Thread,
        workers: []Worker,

        mutex: Mutex = .{},
        is_running: AtomicBool = AtomicBool.init(true),
        job_ready: std.Thread.Condition = .{},

        future: Future(Self),

        // TODO: refactor, when should we use pointers and where are they stored.
        // Should we store them in the heap ourselves and pass pointers to the queueu
        // Should we let the queueue handle it?
        // Should we copy the value when popping?
        // ...
        shared_jobs: JobQueue,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .threads = undefined,
                .workers = undefined,
                .shared_jobs = undefined,
            };
        }

        /// Should only be called ONCE per instance.
        ///
        /// Should ALWAYS be accompanied by a `stop()`
        pub fn start(self: *Self) void {
            const thread_count = config.background_worker_count orelse (std.Thread.getCpuCount() catch @panic("CpuCountError")) - 1;

            self.threads = self.allocator.alloc(Thread, thread_count) catch @panic("OOM");
            self.workers = self.allocator.alloc(Worker, thread_count - 1) catch @panic("OOM");

            self.shared_jobs = JobQueue.initCapacity(self.allocator, thread_count) catch @panic("OOM");

            self.is_running.store(true, .monotonic);

            // One worker per thread but leave space for the heartbeat worker
            for (0..thread_count - 1) |i| {
                self.workers[i] = Worker.init(self);
                self.threads[i] = Thread.spawn(.{}, workerLoop, .{ self, &self.workers[i] }) catch @panic("spawn error");
            }

            // create a single heartbeat worker
            self.threads[thread_count - 1] = std.Thread.spawn(.{}, heartbeatLoop, .{self}) catch @panic("spawn error");

            logger.debug(".{any}", .{self.shared_jobs});
        }

        pub fn stop(self: *Self) void {
            // Todo: check what would happen if stop is called during the heartbeat of a worker.

            self.is_running.store(false, .monotonic);
            self.job_ready.broadcast();

            // Wait for all threads to stop:
            for (self.threads) |thread| {
                thread.join();
            }
            logger.debug(".{any}", .{self.shared_jobs});

            // free all memory
            self.allocator.free(self.threads);
            self.allocator.free(self.workers);

            // All jobs should be finished
            std.debug.assert(self.shared_jobs.items.len == 0);
            self.shared_jobs.deinit(self.allocator);

            self.* = undefined;
        }

        fn workerLoop(self: *Self, worker: *Worker) void {
            logger.debug("[{}] Starting worker loop.", .{Thread.getCurrentId()});
            _ = worker;

            // Lock everything, we dont want two worker loops to access the same job!
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.is_running.load(.monotonic)) {
                if (self.popReadyJob(config.queueing_strategy)) |job| {
                    // Unlock so the job can run freely
                    self.mutex.unlock();
                    defer self.mutex.lock();
                    logger.debug("[{}] Found a new job: [{s}]", .{ Thread.getCurrentId(), job.name });
                }
                self.job_ready.wait(&self.mutex);
            }
        }

        /// Controls the heartbeat mechanism that keeps workers responsive.
        ///
        /// To avoid lock contention, heartbeats are staggered evenly across all workers:
        /// - Each worker receives a heartbeat every [heartbeat_interval] nanoseconds
        /// - With N workers, a heartbeat is sent every [heartbeat_interval/N] nanoseconds,
        ///   rotating through all workers sequentially
        ///
        /// The heartbeat loop continues until the thread pool is shut down.
        fn heartbeatLoop(self: *Self) void {
            @branchHint(.cold);

            // No workers == no heartbeat
            std.debug.assert(self.workers.len > 0);
            logger.debug("[{}] Starting heartbeat loop.", .{Thread.getCurrentId()});

            var idx: usize = 0;
            const sleep_duration = self.heartbeat_interval / self.workers.len;

            while (self.is_running.load(.monotonic)) {
                idx %= self.workers.len;

                self.workers[idx].heartbeat.store(true, .monotonic);
                idx += 1;

                std.time.sleep(sleep_duration);
            }
        }

        pub fn popReadyJob(self: *Self, comptime strategy: QueueingStrategy) ?Job {
            switch (strategy) {
                .Fifo => {
                    var new_job: ?Job = null;
                    // Todo use linked list here using arraylist will result in O(n)
                    new_job = self.shared_jobs.orderedRemove(0);
                    return new_job;
                },
                .Lifo => {
                    var new_job: ?Job = null;
                    new_job = self.shared_jobs.pop();
                    return new_job;
                },
            }
        }

        /// Entrypoint for parallel running code.
        /// Will block until done.
        /// Should only be called once per pool.
        pub fn run(self: *Self, comptime function: anytype, args: anytype) util.returnType(function) {
            return @call(.always_inline, function, args);
        }
    };
}
