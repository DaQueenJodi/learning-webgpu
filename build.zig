pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "learning-webgl",
        .root_source_file = b.path("main.zig"),
        .optimize = optimize,
        .target = target,
    });
    exe.linkLibC();

    exe.linkLibCpp();

    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("glfw");

    const wgpu_dep = b.dependency("wgpu", .{});
    exe.addObjectFile(wgpu_dep.path("libwgpu_native.a"));
    exe.addIncludePath(wgpu_dep.path(""));

    const zmath_dep = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath_dep.module("root"));

    const check_step = b.step("check", "");
    check_step.dependOn(&exe.step);

    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "");
    run_step.dependOn(&run_exe.step);

    const docs_compile_step = b.addTest(.{
        .root_source_file = b.path("docs.zig"),
    });
    docs_compile_step.linkLibC();
    docs_compile_step.root_module.addImport("zmath", zmath_dep.module("root"));
    docs_compile_step.addIncludePath(wgpu_dep.path(""));
    docs_compile_step.linkSystemLibrary("glfw");
    const docs_step = b.step("docs", "");
    const serve_docs = b.addSystemCommand(&.{"python", "-m", "http.server", "-d"});
    serve_docs.addDirectoryArg(docs_compile_step.getEmittedDocs());
    docs_step.dependOn(&serve_docs.step);
}
const std = @import("std");
