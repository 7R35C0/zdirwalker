const std = @import("std");
const print = std.debug.print;

const zdirwalker = @import("zdirwalker");
const DirWalker = zdirwalker.DirWalker;
const ArrayList = zdirwalker.ArrayList;
const ArrayListUnmanaged = zdirwalker.ArrayListUnmanaged;
const Info = zdirwalker.Info;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) print(
        "{s}\n",
        .{"memory leak"},
    );

    var tester = try DirWalker(ArrayList(Info)).init(allocator);
    defer tester.deinit();

    tester = try tester.walk("dir_0000");

    print("========================================\n", .{});
    print("root_name: {s}\nroot_path: {s}\n", .{ tester.root.name, tester.root.path });
    print("========================================\n", .{});

    for (tester.content.items) |content| {
        const relative_path = try std.fs.path.resolve(
            allocator,
            &[_][]const u8{ tester.root.name, content.path },
        );
        defer allocator.free(relative_path);

        print("content_name: {s}\ncontent_path: {s}\nrelativ_path: {s}\n", .{ content.name, content.path, relative_path });
        print("----------------------------------------\n", .{});
    }
}

test "CWD ArrayList" {
    const allocator = std.testing.allocator;

    var tester = try DirWalker(ArrayList(Info)).init(allocator);
    defer tester.deinit();

    _ = try tester.walk("dir_0000");
}

test "CWD ArrayListUnmanaged" {
    const allocator = std.testing.allocator;

    var tester = try DirWalker(ArrayListUnmanaged(Info)).init(allocator);
    defer tester.deinit();

    _ = try tester.walk("dir_0000");
}
