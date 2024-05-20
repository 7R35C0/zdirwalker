const std = @import("std");
const print = std.debug.print;

const zdirwalker = @import("zdirwalker");
const DirWalker = zdirwalker.DirWalker;
const ArrayList = zdirwalker.ArrayList;
const Info = zdirwalker.Info;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() == .leak) print("{s}\n", .{"memory leak"});

    var tester = try DirWalker(ArrayList(Info)).init(allocator);
    defer tester.deinit();

    //+ `directory` is the executable directory
    //+ in this case `<some_path>/zdirwalker/zig-out/examples`
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const directory = try std.fs.selfExeDirPath(&buffer);

    tester = try tester.walk(directory);

    print(
        "root_name:  {s}\n  root_path:  {s}\n",
        .{ tester.root.name, tester.root.path },
    );

    for (tester.content.items) |cont| {
        print(
            "cont_name:  {s}\n  cont_path:  {s}\n",
            .{ cont.name, cont.path },
        );
    }
}
