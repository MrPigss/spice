const std = @import("std");
const Allocator = std.mem.Allocator;
const MemoryPool = std.heap.MemoryPoolExtra;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Future = @import("future.zig").Future;
const Task = @import("task.zig").Task;
const util = @import("util.zig");

const AtomicBool = std.atomic.Value(bool);
const TaskPool = MemoryPool(Task, .{.growable = false});
const TaskStack = ArrayListUnmanaged(Task);
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


// TODO check if order if allocation matters -> i think it does
// TODO check if separate allocators make a difference -> i think they might
pub const ThreadPool = struct {
    const Self = @This();
    allocator: Allocator,

    /// Number of background worker threads in the thread pool.
    ///
    /// When null (default):
    /// - Uses the number of logical CPU cores available - 1
    /// - Determined at runtime via std.Thread.getCpuCount()
    thread_count: usize,

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
    comptime heartbeat_interval: usize = 100 * std.time.ns_per_us,

    /// Strategy used for selecting the next task to run.
    comptime queueing_strategy: QueueingStrategy = .Lifo,

    threads: []Thread,
    // workers: []Worker,

    mutex: Mutex = .{},
    is_running: AtomicBool = AtomicBool.init(true),

    /// Signals waiting threads that a task is ready on the queue.
    task_ready: std.Thread.Condition = .{},

    /// Memorypool used for storing shared tasks. Not growable.
    task_pool: TaskPool,


    pub fn init(allocator: Allocator, thread_count: ?u8) Self {
        const worker_count = thread_count orelse (std.Thread.getCpuCount() catch @panic("CpuCountError")) - 1;

        return .{
            .thread_count = worker_count,
            .allocator = allocator,
            .threads = allocator.alloc(Thread, worker_count) catch @panic("OOM"),
            // .workers = allocator.alloc(Worker, thread_count - 1) catch @panic("OOM"),
            .task_pool = TaskPool.initPreheated(allocator, 2*worker_count) catch @panic("OOM"),
        };
    }

    /// Should only be called ONCE per instance.
    ///
    /// Should ALWAYS be accompanied by a `stop()`
    pub fn start(self: *Self) void {

        self.is_running.store(true, .monotonic);

        // One worker per thread but leave space for the heartbeat worker
        for (0..self.thread_count - 1) |i| {
            // self.workers[i] = Worker.init(self);
            self.threads[i] = Thread.spawn(.{}, workerLoop, .{ self }) catch @panic("spawn error");
        }

        // create a single heartbeat worker
        self.threads[self.thread_count - 1] = std.Thread.spawn(.{}, heartbeatLoop, .{self}) catch @panic("spawn error");

        logger.debug(".{any}", .{self.task_pool.arena.queryCapacity()});
    }

    pub fn deinit(self: *Self) void {
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
        // self.allocator.free(self.workers);

        self.task_pool.deinit();

        self.* = undefined;
    }

    pub fn run(self: *Self, func: anytype, args: anytype) util.returnType(func) {
        const fut: Future = .{
            .pool = self
        };
        return @call(.always_inline, func, .{fut, args});
    }

    fn workerLoop(self: *Self) void {
        logger.debug("[{}] Starting worker loop.", .{Thread.getCurrentId()});

        // Lock everything, we dont want two worker loops to access the same job!
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.is_running.load(.monotonic)) {
            if (self.popReadyTask(self.queueing_strategy)) |task| {
                // Unlock so the job can run freely
                self.mutex.unlock();
                defer self.mutex.lock();
                logger.debug("[{}] Found a new job: [{s}]", .{ Thread.getCurrentId(), task });
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

    pub fn popReadyJob(self: *Self, comptime strategy: QueueingStrategy) ?Task {
        switch (strategy) {
            .Fifo => {
                var new_job: ?Task = null;
                // Todo use linked list here using arraylist will result in O(n)
                new_job = self.task_pool.
                return new_job;
            },
            .Lifo => {
                var new_job: ?Task = null;
                new_job = self.shared_jobs.pop();
                return new_job;
            },
        }
    }
};

std.ArrayList(comptime T: type)
