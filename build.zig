const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("spice", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const parg = b.dependency("parg", .{});

    const example = b.addExecutable(.{
        .name = "spice-example",
        .root_source_file = b.path("examples/zig-parallel-example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("spice", mod);
    example.root_module.addImport("parg", parg.module("parg"));

    b.installArtifact(example);
}
