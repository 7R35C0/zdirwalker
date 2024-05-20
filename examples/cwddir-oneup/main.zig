//^ WARNING
//^
//^ using `".."` as in this example, means to exit the project directory and can
//^ lead to very complicated situations, use it with caution

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

    print("Buy me a coffee, there's a lot of work here 😅\n", .{});

    //+ `".."` is one level up from the current working directory (cwd)
    //+ usually cwd is the project directory (i.e. the build.zig directory)
    tester = try tester.walk("..");

    print(
        "root_name:  {s}\n  root_path:  {s}\n",
        .{ tester.root.name, tester.root.path },
    );

    //+ this can be a very long list, we will only print the first 5 entries
    var index: usize = 0;
    for (tester.content.items) |cont| {
        if (index < 5) {
            print(
                "cont_name:  {s}\n  cont_path:  {s}\n",
                .{ cont.name, cont.path },
            );
            index += 1;
        } else break;
    }
}
