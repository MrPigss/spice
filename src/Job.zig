const std = @import("std");

/// A job represents something which _potentially_ could be executed on a different thread.
/// The jobs forms a doubly-linked list: You call `push` to append a job and `pop` to remove it.
pub const Job = struct {
    // handler: ?*const fn (t: *Task, job: *Job) void,
    prev_or_null: ?*anyopaque = null,
    next_or_state: ?*anyopaque = null,
    handle: *const fn () void,
    name: []const u8,


    // This struct gets placed on the stack in _every_ frame so we're very cautious
    // about the size of it. There's three possible states, but we don't use a union(enum)
    // since this would actually increase the size.
    //
    // 1. pending: handler is null. a/b is undefined.
    // 2. queued: handler is set. prev_or_null is `prev`, next_or_state is `next`.
    // 3. executing: handler is set. prev_or_null is null, next_or_state is `*JobExecuteState`.

    /// Returns a new job which can be used for the head of a list.
    fn head() Job {
        return Job{
            .handler = undefined,
            .prev_or_null = null,
            .next_or_state = null,
        };
    }

    pub fn pending() Job {
        return Job{
            .handler = null,
            .prev_or_null = undefined,
            .next_or_state = undefined,
        };
    }

    // pub fn state(self: Job) JobState {
    //     if (self.handler == null) return .pending;
    //     if (self.prev_or_null != null) return .queued;
    //     return .executing;
    // }

    pub fn isTail(self: Job) bool {
        return self.next_or_state == null;
    }

    // fn getExecuteState(self: *Job) *JobExecuteState {
    //     std.debug.assert(self.state() == .executing);
    //     return @ptrCast(@alignCast(self.next_or_state));
    // }

    // pub fn setExecuteState(self: *Job, execute_state: *JobExecuteState) void {
    //     std.debug.assert(self.state() == .executing);
    //     self.next_or_state = execute_state;
    // }

    /// Pushes the job onto a stack.
    // fn push(self: *Job, tail: **Job, handler: *const fn (task: *Task, job: *Job) void) void {
    //     std.debug.assert(self.state() == .pending);
    //     defer std.debug.assert(self.state() == .queued);

    //     self.handler = handler;
    //     tail.*.next_or_state = self; // tail.next = self
    //     self.prev_or_null = tail.*; // self.prev = tail
    //     self.next_or_state = null; // self.next = null
    //     tail.* = self; // tail = self
    // }

    fn pop(self: *Job, tail: **Job) void {
        std.debug.assert(self.state() == .queued);
        std.debug.assert(tail.* == self);
        const prev: *Job = @ptrCast(@alignCast(self.prev_or_null));
        prev.next_or_state = null; // prev.next = null
        tail.* = @ptrCast(@alignCast(self.prev_or_null)); // tail = self.prev
        self.* = undefined;
    }

    fn shift(self: *Job) ?*Job {
        const job = @as(?*Job, @ptrCast(@alignCast(self.next_or_state))) orelse return null;

        std.debug.assert(job.state() == .queued);

        const next: ?*Job = @ptrCast(@alignCast(job.next_or_state));
        // Now we have: self -> job -> next.

        // If there is no `next` then it means that `tail` actually points to `job`.
        // In this case we can't remove `job` since we're not able to also update the tail.
        if (next == null) return null;

        defer std.debug.assert(job.state() == .executing);

        next.?.prev_or_null = self; // next.prev = self
        self.next_or_state = next; // self.next = next

        // Turn the job into "executing" state.
        job.prev_or_null = null;
        job.next_or_state = undefined;
        return job;
    }
};
