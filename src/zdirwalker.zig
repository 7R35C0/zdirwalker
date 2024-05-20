//!
//! Tested only with zig version 0.12.0 on Linux Fedora 39.
//!
//! #### 📌 About
//!
//! This module is a small wrapper over `std.fs.Dir.Walker`.
//!
//! From `std.fs.Dir.Walker.next` documentation:
//!
//! "After each call to this function, and on deinit(), the memory returned
//! from this function becomes invalid. A copy must be made in order to keep
//! a reference to the path."
//!
//! `DirWalker` make that copy and store some extra information in a structure.
//!
//! Note that all results are relative to the current working directory (cwd).
//!
//! This is important because the same code can lead to different results
//! depending on where it is run from the final application.
//!
//! #### 📌 Implementation
//!
//! General terms and their meaning:
//!
//! * `root`, the walking directory
//! * `content`, entries in `root` directory
//! * `allocator`, memory allocator used (`std.mem.Allocator`)
//!
//! `DirWalker` stores data for each directory and file in an `Info` structure:
//!
//! * `name`, depends on the context in which `Info` is used:
//!   * for a directory is the last component of path
//!
//!   ```txt
//!   e.g. /home/user/ztester                     => ztester
//!   ```
//!
//!   * for a file is the last component of path without last extension
//!
//!   ```txt
//!   e.g. /home/user/ztester/zig-out/bin/main    => main
//!        /home/user/ztester/build.zig           => build
//!        /home/user/ztester/build.zig.zon       => build.zig
//!   ```
//!
//! * `path`, depends on the context in which `Info` is used:
//!   * for `root` is an absolute path:
//!
//!   ```txt
//!   e.g. ztester        => /home/user/ztester
//!   ```
//!
//!   * for `content` entries is a relative path to `root.path`
//!
//!   ```txt
//!   e.g. main           => zig-out/bin/main
//!        build.zig      => build.zig
//!        build.zig.zon  => build.zig.zon
//!   ```
//!
//! * `meta`, are extra information provided by zig standard library
//!   (`std.fs.File.Metadata`)
//!
//! `DirWalker` itself uses unmanaged memory, user must provide an `allocator`.
//!
//! However, `content` entries are stored in an:
//!
//! * ArrayList(Info), (`std.ArrayList`)
//! > "internally stores a `std.mem.Allocator` for memory management"
//! * ArrayListUnmanaged(Info), (`std.ArrayListUnmanaged`)
//! > "allocator is passed as a parameter to the relevant functions rather than
//! > stored in the struct itself"
//!
//! Functions and their use:
//!
//! * `init`, initializes memory with a specific `allocator`
//! * `deinit`, release all allocated memory
//! * `walk`, iterate over the `root` and return `content` entries:
//!   * `directory` parameter (the `root`):
//!     * must be a relative path to the current working directory (cwd)
//!     * must already exist in the operating system
//!     * must be of kind `.directory` (`std.fs.File.Kind`)
//!   * symlinks (of kind `.sym_link`) in `directory`, count as entries
//!     in `content`, but are not followed (`std.fs.Dir.Walker.next`)
//!   * the order of returned entries in `content` is undefined
//!   * `self` parameter will not be `deinit` after walking it
//!
//! #### 📌 Important
//!
//! 🔔 Note that `"."` or `".."` can lead to very long runs, especially when
//! are used to get the `directory` path.
//!
//! The module repository contains some examples for such cases.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;

// export for easy usage
pub const ArrayList = std.ArrayList;
pub const ArrayListUnmanaged = std.ArrayListUnmanaged;

const DirWalkerError = error{InvalidType};

pub const Info = struct {
    /// depends on the context in which `Info` is used:
    /// * for a directory is the last component of path
    /// * for a file is the last component of path without last extension
    name: []const u8 = undefined,
    /// depends on the context in which `Info` is used:
    /// * for `root` is an absolute path
    /// * for `content` entries is a relative path to `root.path`
    path: []const u8 = undefined,
    /// are extra information provided by zig standard library
    /// (`std.fs.File.Metadata`)
    meta: std.fs.File.Metadata = undefined,
};

/// `DirWalker` itself uses unmanaged memory, user must provide an `allocator`.
///
/// Accepted types for T parameter are:
/// * ArrayList(Info), (`std.ArrayList`)
/// * ArrayListUnmanaged(Info), (`std.ArrayListUnmanaged`)
pub fn DirWalker(comptime T: type) type {
    return struct {
        /// the walking directory
        root: Info,
        /// entries in `root` directory
        content: T,
        /// memory allocator used (`std.mem.Allocator`)
        allocator: Allocator,

        const Self = @This();

        /// initializes memory with a specific `allocator`
        pub fn init(allocator: Allocator) !Self {
            return Self{
                .root = Info{},
                .content = switch (T) {
                    ArrayList(Info) => ArrayList(Info).init(allocator),
                    ArrayListUnmanaged(Info) => try ArrayListUnmanaged(Info).initCapacity(allocator, 0),
                    else => return error.InvalidType,
                },
                .allocator = allocator,
            };
        }

        /// release all allocated memory
        pub fn deinit(self: *Self) void {
            switch (@TypeOf(self.content)) {
                ArrayList(Info) => {
                    for (self.content.items) |info| {
                        self.allocator.free(info.name);
                        self.allocator.free(info.path);
                    }
                    self.content.deinit();
                },
                ArrayListUnmanaged(Info) => {
                    for (self.content.items) |info| {
                        self.allocator.free(info.name);
                        self.allocator.free(info.path);
                    }
                    self.content.deinit(self.allocator);
                },
                else => {},
            }

            self.* = undefined;
        }

        /// iterate over the `root` and return `content` entries:
        /// * `directory` parameter (the `root`):
        ///     * must be a relative path to the current working directory (cwd)
        ///     * must already exist in the operating system
        ///     * must be of kind `.directory` (`std.fs.File.Kind`)
        /// * symlinks (of kind `.sym_link`) in `directory`, count as entries
        ///   in `content`, but are not followed (`std.fs.Dir.Walker.next`)
        /// * the order of returned entries in `content` is undefined
        /// * `self` parameter will not be `deinit` after walking it
        pub fn walk(self: *Self, directory: []const u8) !Self {
            var root: std.fs.Dir = undefined;
            {
                //^ no matter if `OpenDirOptions.no_follow` is true or false,
                //^ `std.fs.Dir.Walker.next` does not follow symbolic links
                root = try std.fs.cwd().openDir(
                    directory,
                    .{ .iterate = true },
                );
                errdefer root.close();
            }
            defer root.close();

            var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

            var walker = try root.walk(self.allocator);
            defer walker.deinit();

            return Self{
                .root = .{
                    .name = std.fs.path.stem(
                        try std.fs.realpath(
                            directory,
                            &buffer,
                        ),
                    ),
                    .path = try std.fs.realpath(
                        directory,
                        &buffer,
                    ),
                    .meta = try root.metadata(),
                },
                .content = switch (@TypeOf(self.content)) {
                    ArrayList(Info) => blk: {
                        while (try walker.next()) |entry| {
                            try self.content.append(
                                try getContent(
                                    self.allocator,
                                    entry,
                                ),
                            );
                        }
                        break :blk self.content;
                    },
                    ArrayListUnmanaged(Info) => blk: {
                        while (try walker.next()) |entry| {
                            try self.content.append(
                                self.allocator,
                                try getContent(
                                    self.allocator,
                                    entry,
                                ),
                            );
                        }
                        break :blk self.content;
                    },
                    else => return error.InvalidType,
                },
                .allocator = self.allocator,
            };
        }

        fn getContent(allocator: Allocator, entry: std.fs.Dir.Walker.Entry) !Info {
            return Info{
                .name = try allocator.dupe(
                    u8,
                    std.fs.path.stem(entry.basename),
                ),
                .path = try allocator.dupe(
                    u8,
                    entry.path,
                ),
                .meta = try entry.dir.metadata(),
            };
        }
    };
}

test "CWD ArrayList" {
    const allocator = std.testing.allocator;

    var tester = try DirWalker(ArrayList(Info)).init(allocator);
    defer tester.deinit();

    _ = try tester.walk(".");
}

test "CWD ArrayListUnmanaged" {
    const allocator = std.testing.allocator;

    var tester = try DirWalker(ArrayListUnmanaged(Info)).init(allocator);
    defer tester.deinit();

    _ = try tester.walk(".");
}
