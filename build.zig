const std = @import("std");
const print = std.debug.print;

// general configuration
const Config = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_source_file: std.Build.LazyPath,
    version: std.SemanticVersion,
};

pub fn build(b: *std.Build) void {
    // specific configuration for this build
    const cfg = Config{
        .name = "zdirwalker",
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .root_source_file = b.path("src/zdirwalker.zig"),
        .version = .{
            .major = 0,
            .minor = 1,
            .patch = 0,
        },
    };

    // Expose library module for later use with `@import("cfg.name")`
    const mod = setupModule(b, cfg);

    // Build static library (zig-out/lib)
    const lib = setupLibrary(b, cfg);

    // Run tests
    const tst = setupTest(b, cfg);

    // Generate code coverage (zig-out/cov)
    // This function assumes that kcov (https://github.com/SimonKagstrom/kcov)
    // is already installed on system.
    // For code coverage report (zig-out/cov/index.html), use a live http server.
    // The .vscode/extensions.json file contains an extension for this purpose.
    setupCoverage(b, tst);

    // Generate documentation (zig-out/doc)
    // For documentation (zig-out/doc/index.html), same as above.
    setupDocumentation(b, lib);

    // Silent formatting zig files
    setupFormat(b);

    // Remove specific directory (contain multiple steps):
    //  * zig-cache
    //  * zig-out
    //  * zig-out/bin
    //  * zig-out/doc
    //  * zig-out/cov
    //  * zig-out/lib
    setupRemove(b);

    // Run specific example (contain multiple steps):
    //  * examples/cwddir
    //  * examples/cwddir-oneup
    //  * examples/exedir
    //  * examples/exedir-oneup
    //  * examples/exedir-twoup-onedown
    setupExample(b, cfg, mod);
}

fn setupModule(b: *std.Build, cfg: Config) *std.Build.Module {
    return b.addModule(
        cfg.name,
        .{ .root_source_file = cfg.root_source_file },
    );
}

fn setupLibrary(b: *std.Build, cfg: Config) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = cfg.name,
        .target = cfg.target,
        .optimize = cfg.optimize,
        .root_source_file = cfg.root_source_file,
        .version = cfg.version,
    });
    const lib_install = b.addInstallArtifact(
        lib,
        .{},
    );

    const lib_step = b.step(
        "lib",
        "Build static library   (zig-out/lib)",
    );
    lib_step.dependOn(&lib_install.step);

    return lib;
}

fn setupTest(b: *std.Build, cfg: Config) *std.Build.Step.Compile {
    const tst = b.addTest(.{
        .name = cfg.name,
        .target = cfg.target,
        .optimize = cfg.optimize,
        .root_source_file = cfg.root_source_file,
        .version = cfg.version,
    });
    const tst_run = b.addRunArtifact(tst);

    const tst_step = b.step(
        "tst",
        "Run tests",
    );
    tst_step.dependOn(&tst_run.step);

    return tst;
}

fn setupCoverage(b: *std.Build, tst: *std.Build.Step.Compile) void {
    const cov_run = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-pattern=src/",
        "zig-cache/cov",
    });
    cov_run.addArtifactArg(tst);

    const cov_install = b.addInstallDirectory(.{
        .install_dir = .{ .custom = "cov" },
        .install_subdir = "",
        .source_dir = .{
            .src_path = .{
                .owner = b,
                .sub_path = "zig-cache/cov",
            },
        },
    });
    cov_install.step.dependOn(&cov_run.step);

    const cov_remove = b.addRemoveDirTree(b.pathJoin(
        &[_][]const u8{ b.cache_root.path.?, "cov" },
    ));
    cov_remove.step.dependOn(&cov_install.step);

    const cov_step = b.step(
        "cov",
        "Generate code coverage (zig-out/cov)",
    );
    cov_step.dependOn(&cov_remove.step);
}

fn setupDocumentation(b: *std.Build, lib: *std.Build.Step.Compile) void {
    const doc_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "doc",
        .source_dir = lib.getEmittedDocs(),
    });

    const doc_step = b.step(
        "doc",
        "Generate documentation (zig-out/doc)",
    );
    doc_step.dependOn(&doc_install.step);
}

fn setupFormat(b: *std.Build) void {
    const fmt = b.addFmt(.{
        .paths = &.{
            "examples",
            "src",
            "standalone",
            "build.zig",
            "build.zig.zon",
        },
        .check = false,
    });

    const fmt_step = b.step(
        "fmt",
        "Silent formatting",
    );
    fmt_step.dependOn(&fmt.step);
}

fn setupRemove(b: *std.Build) void {
    const rmdir_cache_step = b.step(
        "rm-cache",
        "Remove cache           (zig-cache)",
    );
    rmdir_cache_step.dependOn(&b.addRemoveDirTree(b.cache_root.path.?).step);

    const rmdir_out_step = b.step(
        "rm-out",
        "Remove output          (zig-out)",
    );
    rmdir_out_step.dependOn(&b.addRemoveDirTree(b.install_path).step);

    const rmdir_bin_step = b.step(
        "rm-bin",
        "Remove binary          (zig-out/bin)",
    );
    rmdir_bin_step.dependOn(&b.addRemoveDirTree(b.exe_dir).step);

    const rmdir_doc_step = b.step(
        "rm-doc",
        "Remove documentation   (zig-out/doc)",
    );
    rmdir_doc_step.dependOn(&b.addRemoveDirTree(b.pathJoin(
        &[_][]const u8{ b.install_path, "doc" },
    )).step);

    const rmdir_cov_step = b.step(
        "rm-cov",
        "Remove code coverage   (zig-out/cov)",
    );
    rmdir_cov_step.dependOn(&b.addRemoveDirTree(b.pathJoin(
        &[_][]const u8{ b.install_path, "cov" },
    )).step);

    const rmdir_lib_step = b.step(
        "rm-lib",
        "Remove library         (zig-out/lib)",
    );
    rmdir_lib_step.dependOn(&b.addRemoveDirTree(b.lib_dir).step);
}

fn setupExample(b: *std.Build, cfg: Config, mod: *std.Build.Module) void {
    var egs_dir = std.fs.openDirAbsolute(
        b.path("examples").getPath(b),
        .{ .iterate = true },
    ) catch |err| {
        print("{s}: {!}\n", .{ cfg.name, err });
        return;
    };
    defer egs_dir.close();

    var egs_walker = egs_dir.walk(b.allocator) catch |err| {
        print("{s}: {!}\n", .{ cfg.name, err });
        return;
    };
    defer egs_walker.deinit();

    while (egs_walker.next() catch |err| {
        print("{s}: {!}\n", .{ cfg.name, err });
        return;
    }) |egs| {
        if (egs.kind == .directory) {
            const egs_name = egs.basename;
            const egs_path = std.fs.path.resolve(
                b.allocator,
                &[_][]const u8{ "examples", egs.path, "main.zig" },
            ) catch |err| {
                print("{s}: {!}\n", .{ cfg.name, err });
                return;
            };

            const egs_exe = b.addExecutable(.{
                .name = egs_name,
                .target = cfg.target,
                .optimize = cfg.optimize,
                .root_source_file = .{
                    .src_path = .{
                        .owner = b,
                        .sub_path = egs_path,
                    },
                },
                .version = cfg.version,
            });

            egs_exe.root_module.addImport(cfg.name, mod);

            const egs_install = b.addInstallArtifact(
                egs_exe,
                .{
                    .dest_dir = .{
                        .override = .{
                            .custom = "examples",
                        },
                    },
                },
            );

            const egs_run = b.addRunArtifact(egs_exe);

            egs_run.step.dependOn(&egs_install.step);

            const egs_step = b.step(
                b.fmt("run-{s}", .{egs_name}),
                b.fmt("Run example {s}", .{egs_name}),
            );

            egs_step.dependOn(&egs_run.step);
        }
    }
}
