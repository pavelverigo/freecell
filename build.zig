const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

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

    const wasm = b.addExecutable(.{
        .name = "freecell",
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            // TODO .cpu_model = .bleeding_edge non-viable
            // https://webassembly.org/features/
            .cpu_features_add = std.Target.wasm.featureSet(&.{
                .atomics,
                .bulk_memory,
                .exception_handling,
                // .extended_const,
                .multivalue,
                .mutable_globals,
                .nontrapping_fptoint,
                .reference_types,
                // .relaxed_simd,
                .sign_ext,
                .simd128,
                // .tail_call,
            }),
            .os_tag = .freestanding,
        }),
        .optimize = optimize,
    });

    const heap_pages = 256;
    const stack_pages = 64;

    wasm.rdynamic = true;
    wasm.entry = .disabled;
    wasm.initial_memory = (heap_pages + stack_pages) * 64 * 1024;
    wasm.global_base = heap_pages * 64 * 1024;

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(wasm.getEmittedBin(), wasm.out_filename);
    _ = wf.addCopyFile(b.path("index.html"), "index.html");
    _ = wf.addCopyFile(b.path("index.js"), "index.js");
    _ = wf.addCopyDirectory(b.path("audio"), "audio", .{});

    const www_dir = b.addInstallDirectory(.{ .source_dir = wf.getDirectory(), .install_dir = .prefix, .install_subdir = "www" });
    b.getInstallStep().dependOn(&www_dir.step);
}
