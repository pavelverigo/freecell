const std = @import("std");

pub fn build(b: *std.Build) void {
    const sprites_compiler = b.addExecutable(.{
        .name = "sprites_compiler",
        .root_source_file = b.path("src/sprites_compiler.zig"),
        .target = b.host,
    });

    sprites_compiler.linkLibC();
    sprites_compiler.addIncludePath(b.path("thirdparty/stb_image-2.29"));
    sprites_compiler.addCSourceFile(.{ .file = b.path("thirdparty/stb_image-2.29/stb_image_impl.c"), .flags = &.{} });

    const sprites_compiler_step = b.addRunArtifact(sprites_compiler);
    const sprites_zig_output = sprites_compiler_step.addOutputFileArg("Sprite.zig");
    const sprites_data_output = sprites_compiler_step.addOutputFileArg("sprites.data");

    const sprites_module = b.addModule("Sprite", .{
        .root_source_file = sprites_zig_output,
    });
    sprites_module.addAnonymousImport("sprites_data", .{
        .root_source_file = sprites_data_output,
    });

    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });
    const game = b.addExecutable(.{
        .name = "freecell",
        .root_source_file = b.path("src/wasm_main.zig"),
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

    game.root_module.addImport("Sprite", sprites_module);

    game.rdynamic = true;
    game.entry = .disabled;

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(game.getEmittedBin(), game.out_filename);
    _ = wf.addCopyFile(b.path("src/index.html"), "index.html");
    _ = wf.addCopyFile(b.path("src/index.js"), "index.js");
    _ = wf.addCopyDirectory(b.path("audio"), "audio", .{});

    const www_dir = b.addInstallDirectory(.{ .source_dir = wf.getDirectory(), .install_dir = .prefix, .install_subdir = "www" });
    b.getInstallStep().dependOn(&www_dir.step);
}
