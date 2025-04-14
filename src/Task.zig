const Worker = @import("Worker.zig");
const Job = @import("Job.zig");

const Task = struct {



    // The following function's signature is actually extremely critical. We take in all of
    // the task state (worker, last_heartbeat, job_tail) as parameters. The reason for this
    // is that Zig/LLVM is really good at passing parameters in registers, but struggles to
    // do the same for "fields in structs". In addition, we then return the changed value
    // of last_heartbeat and job_tail.
    fn callWithContext(
        worker: *Worker,
        job_tail: *Job,
        comptime T: type,
        func: anytype,
        arg: anytype,
    ) T {
        return @call(.always_inline, func, .{
            &F,
            arg,
        });
    }
};


// const Task = @This();

// worker: *Worker,
// job_tail: *Job,

// pub inline fn tick(self: *Task) void {
//     if (self.worker.heartbeat.load(.monotonic)) {
//         self.worker.pool.heartbeat(self.worker);
//     }
// }

// pub inline fn call(self: *Task, comptime T: type, func: anytype, arg: anytype) T {
//     return callWithContext(
//         self.worker,
//         self.job_tail,
//         T,
//         func,
//         arg,
//     );
// }

// fn callWithContext(
//     worker: *Worker,
//     job_tail: *Job,
//     comptime T: type,
//     func: anytype,
//     arg: anytype,
// ) T {
//     var t = Task{
//         .worker = worker,
//         .job_tail = job_tail,
//     };
//     t.tick();
//     return @call(.always_inline, func, .{
//         &t,
//         arg,
//     });
// }
