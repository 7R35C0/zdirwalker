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

    // Build and install library (zig-out/lib)
    const lib = setupLibrary(b, cfg);

    // Run tests suite
    const tst = setupTest(b, cfg);

    // Generate code coverage with kcov (zig-out/kcov)
    setupCoverage(b, tst);

    // Generate documentation (zig-out/docs)
    setupDocumentation(b, lib);

    // Silent formatting zig files
    setupFormat(b);

    // Remove cache directory (zig-cache)
    setupRemoveCache(b);

    // Remove output directory (zig-out)
    setupRemoveOutput(b);

    // Run specific example
    setupExamples(b, cfg, mod);
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
    const lib_install = b.addInstallArtifact(lib, .{});

    const lib_step = b.step("lib", "Build and install library");
    lib_step.dependOn(&lib_install.step);

    return lib;
}

fn setupTest(b: *std.Build, cfg: Config) *std.Build.Step.Compile {
    const tst = b.addTest(.{
        .name = "freetype-tests",
        .target = cfg.target,
        .optimize = cfg.optimize,
        .root_source_file = cfg.root_source_file,
        .version = cfg.version,
    });
    const tst_run = b.addRunArtifact(tst);

    const tst_step = b.step("test", "Run tests suite");
    tst_step.dependOn(&tst_run.step);

    return tst;
}

fn setupCoverage(b: *std.Build, tst: *std.Build.Step.Compile) void {
    const cov_run = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-pattern=src/",
        "zig-out/kcov",
    });
    cov_run.addArtifactArg(tst);

    const cov_step = b.step("kcov", "Code coverage with kcov");
    cov_step.dependOn(&cov_run.step);
}

fn setupDocumentation(b: *std.Build, lib: *std.Build.Step.Compile) void {
    const doc_install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .install_subdir = "docs",
        .source_dir = lib.getEmittedDocs(),
    });

    const doc_step = b.step("docs", "Generate documentation");
    doc_step.dependOn(&doc_install.step);
}

fn setupFormat(b: *std.Build) void {
    const fmt = b.addFmt(.{
        .paths = &.{
            "examples",
            "src",
            "build.zig",
            "build.zig.zon",
        },
        .check = false,
    });

    const fmt_step = b.step("fmt", "Silent formatting zig files");
    fmt_step.dependOn(&fmt.step);
}

fn setupRemoveCache(b: *std.Build) void {
    const rmc_step = b.step("rmc", "Remove cache directory");
    rmc_step.dependOn(&b.addRemoveDirTree("zig-cache").step);
}

fn setupRemoveOutput(b: *std.Build) void {
    const rmo_step = b.step("rmo", "Remove output directory");
    rmo_step.dependOn(&b.addRemoveDirTree("zig-out").step);
}

fn setupExamples(b: *std.Build, cfg: Config, mod: *std.Build.Module) void {
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
                b.fmt("Run '{s}' example", .{egs_name}),
            );

            egs_step.dependOn(&egs_run.step);
        }
    }
}
