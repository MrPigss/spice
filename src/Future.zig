const std = @import("std");

const Job = @import("Job.zig");
const Task = @import("Task.zig");
const util = @import("util.zig");
/// Represents the parallel execution context and provides mechanisms to spawn and synchronize parallel tasks.
///
/// __@param__ _`Tp : type`_ The Actual ThreadPool type. Needed because it's a generic.
pub fn Future(Tp: type) type {
    return struct {
        const Self = @This();

        pool: *Tp,

        pub fn fork(self: *Self, comptime func: anytype) util.returnType(func) {
            _ = self;
            // Todo add to taskqueue
        }

        pub inline fn join(self: *Self, t: *Task) util.returnType(t.func) {
            _ = self;
            // TODO: remove from threadlocal taskqueue
            if (!t.started) {
                return @call(.always_inline, t.func, t.args);
            } else {
                // the result should be a lock that returns the value when unlocked
                return t.done.wait();
            }
        }

        pub inline fn NonBlockingJoin(self: *Self, t: *Task) util.returnType(t.func) {
            _ = self;
            if (!t.done) {
                return t.result.wait();
            }
        }
    };
}


// pub fn Future(comptime Input: type, Output: type) type {
//     return struct {
//         const Self = @This();

//         job: Job,
//         input: Input,

//         pub inline fn init() Self {
//             return Self{ .job = Job.pending(), .input = undefined };
//         }

//         /// Schedules a piece of work to be executed by another thread.
//         /// After this has been called you MUST call `join` or `tryJoin`.
//         pub inline fn fork(
//             self: *Self,
//             task: *Task,
//             comptime func: fn (task: *Task, input: Input) Output,
//             input: Input,
//         ) void {
//             const handler = struct {
//                 fn handler(t: *Task, job: *Job) void {
//                     const fut: *Self = @fieldParentPtr("job", job);
//                     const exec_state = job.getExecuteState();
//                     const value = t.call(Output, func, fut.input);
//                     exec_state.resultPtr(Output).* = value;
//                     exec_state.done.set();
//                 }
//             }.handler;
//             self.input = input;
//             self.job.push(&task.job_tail, handler);
//         }

//         /// Waits for the result of `fork`.
//         /// This is only safe to call if `fork` was _actually_ called.
//         /// Use `tryJoin` if you conditionally called it.
//         pub inline fn join(
//             self: *Self,
//             task: *Task,
//         ) ?Output {
//             std.debug.assert(self.job.state() != .pending);
//             return self.tryJoin(task);
//         }

//         /// Waits for the result of `fork`.
//         /// This function is safe to call even if you didn't call `fork` at all.
//         pub inline fn tryJoin(
//             self: *Self,
//             task: *Task,
//         ) ?Output {
//             switch (self.job.state()) {
//                 .pending => return null,
//                 .queued => {
//                     self.job.pop(&task.job_tail);
//                     return null;
//                 },
//                 .executing => return self.joinExecuting(task),
//             }
//         }

//         fn joinExecuting(self: *Self, task: *Task) ?Output {
//             @branchHint(.cold);

//             const w = task.worker;
//             const pool = w.pool;
//             const exec_state = self.job.getExecuteState();

//             if (pool.waitForJob(w, &self.job)) {
//                 const result = exec_state.resultPtr(Output).*;
//                 pool.destroyExecuteState(exec_state);
//                 return result;
//             }

//             return null;
//         }

//         pub fn map(self: *Self, task: *Task, comptime mapper: fn(Output) anyopaque) Future(Input, @TypeOf(mapper(undefined))) {
//             const MapOutput = @TypeOf(mapper(undefined));
//             var future = Future(Input, MapOutput).init();

//             if (self.tryJoin(task)) |result| {
//                 future.fork(task, struct {
//                     fn mapFunc(_: *Task, _: Input) MapOutput {
//                         return mapper(result);
//                     }
//                 }.mapFunc, self.input);
//             }

//             return future;
//         }
//     };
// }
