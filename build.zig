const std = @import("std");
const wasm = @import("src/wasm.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rsrc_compiler = b.addExecutable(.{
        .name = "rsrc_compiler",
        .root_source_file = .{ .path = "src/gen/rsrc_compiler.zig" },
        .target = target,
        .optimize = optimize,
    });

    rsrc_compiler.linkLibC();
    rsrc_compiler.addIncludePath(.{ .path = "thirdparty" });
    rsrc_compiler.addCSourceFile(.{ .file = .{ .path = "src/gen/stb_impl.c" }, .flags = &.{} });

    const gen_cmd = b.addRunArtifact(rsrc_compiler);
    gen_cmd.step.dependOn(b.getInstallStep());
    const gen_step = b.step("gen", "Compile sprites");
    gen_step.dependOn(&gen_cmd.step);

    b.installArtifact(rsrc_compiler);

    const lib = b.addSharedLibrary(.{
        .name = "freecell",
        .root_source_file = .{ .path = "src/wasm.zig" },
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = optimize,
    });

    const heap_pages = 256;
    const stack_pages = 64;

    lib.rdynamic = true;
    lib.initial_memory = (heap_pages + stack_pages) * 64 * 1024;
    lib.global_base = heap_pages * 64 * 1024;

    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
