# Steps

1. Initiate threadpool
2. Start a task in the threadpool and pass a `Future` object to the function.
3. use a future object to fork other tasks.

# Context
## Threadpool
The Threadpool manages resources (threads, memory allocators, mutexes) required for parallel execution. It serves as the entry point to a parallel context.

```zig
// Create a threadpool with default configuration
var pool = ThreadPool(.{}).init(gpa.allocator());
defer pool.deinit();

// start the threadpool
pool.start();

// Enter parallel execution context
try pool.run(mainTask);
```

### Key Functions

- `init(config: Config) Threadpool`: Creates a new threadpool with specified Allocator
- `deinit() void`: Releases all resources
- `run(function: anytype) !anytype`: Enters parallel execution context

**Note:** Using `run()` establishes a context for parallelism but doesn't automatically execute code in parallel.

## Future

The Future represents the parallel execution context and provides mechanisms to spawn and synchronize parallel tasks.

### Key Functions

- `fork(function: anytype, args: anytype) !Task`: Spawns a potentially parallel task
- `join(task: Task) !ReturnType`: Waits for task completion and returns its result
- `nonBlockingJoin(task: Task) ?ReturnType`: Returns the result of the task if available, else returns null.

```zig
fn mainTask(future: *Future) !void {
    // Fork tasks that may run in parallel
    const task1 = try future.fork(someFunction, .{arg1, arg2});
    const task2 = try future.fork(otherFunction, .{});

    // Wait for tasks to complete
    const result1 = try future.join(task1);
    const result2 = try future.join(task2);
}
```

## Task

A Task represents a unit of work that can be executed in parallel.

## Task
`Future.fork(otherfunction1)` will return a `Task` wich can later be joined using `Future.join(sometask)` or `Future.NonBlockingJoin(sometask)`.

# Implementation Details
## Join

Consider the following code.
```zig
fn mainTask(future: *Future) !void {
    // Fork tasks that may run in parallel
    const task1 = try future.fork(someFunction, .{arg1, arg2});

    // Wait for tasks to complete
    const result1 = try future.join(task1);
}
```

`future.fork(someFunction)` will add `someFunction` to a taskqueue.
If no other thread started `task1` by the time `future.join(task1)` is called.
`join` will run it immediatly.

`join` will be inlined resulting in following pseudocode.

```zig
fn mainTask(future: *Future) !void {
    // Fork tasks that may run in parallel
    const task1 = try future.fork(someFunction, .{arg1, arg2});

    if (future.NonBlockingJoin(task1)) |returnValue| {
        return returnValue
    } else {
        return somefunction()
    }
}
```
Most of the time the job will _not_ be picked up by another thread (which is a good thing).
In this case, our program nicely turns into the sequential version with a few extra branches which are all very predictable.
This is friendly both for the code optimizer (e.g. inlineing) and the CPU (branch prediction).

## Shared State
### Taskpool
A memorypool with all (shared) tasks -> SMP Alloc has a a freelist PER THREAD, what does this mean exactly?
The shared_tasks will store their tasks here.
1. pop task from stack
2. run task
3. free used mem

__Note:__ Between popping a Task from the stack and freeing the mem, that task might add a new shared Task to the stack, the mempool should have `(2 * Workers.len)* @sizeOf(tasks)` space allocated.

###
