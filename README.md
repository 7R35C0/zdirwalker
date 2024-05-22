## README

The repo provides a directory walker made with zig programming language.

Tested only with zig version 0.12.0 on Linux Fedora 39.

### 📌 About

This module is a small wrapper over `std.fs.Dir.Walker`.

From `std.fs.Dir.Walker.next` documentation:

> "After each call to this function, and on deinit(), the memory returned
> from this function becomes invalid. A copy must be made in order to keep
> a reference to the path."

`DirWalker` make that copy and store some extra information in a structure.

Note that all results are relative to the current working directory (cwd).

This is important because the same code can lead to different results
depending on where it is run from the final application.

### 📌 Implementation

General terms and their meaning:

* `root`, the walking directory
* `content`, entries in `root` directory
* `allocator`, memory allocator used (`std.mem.Allocator`)

`DirWalker` stores data for each directory and file in an `Info` structure:

* `name`, depends on the context in which `Info` is used:
  * for a directory is the last component of path

  ```txt
  e.g. /home/user/ztester                     => ztester
  ```

  * for a file is the last component of path without last extension

  ```txt
  e.g. /home/user/ztester/zig-out/bin/main    => main
       /home/user/ztester/build.zig           => build
       /home/user/ztester/build.zig.zon       => build.zig
  ```

* `path`, depends on the context in which `Info` is used:
  * for `root` is an absolute path:

  ```txt
  e.g. ztester        => /home/user/ztester
  ```

  * for `content` entries is a relative path to `root.path`

  ```txt
  e.g. main           => zig-out/bin/main
       build.zig      => build.zig
       build.zig.zon  => build.zig.zon
  ```

* `meta`, are extra information provided by zig standard library
  (`std.fs.File.Metadata`)

`DirWalker` itself uses unmanaged memory, user must provide an `allocator`.

However, `content` entries are stored in an:

* ArrayList(Info), (`std.ArrayList`)
  > "internally stores a `std.mem.Allocator` for memory management"
* ArrayListUnmanaged(Info), (`std.ArrayListUnmanaged`)
  > "allocator is passed as a parameter to the relevant functions rather than
  > stored in the struct itself"

Functions and their use:

* `init`, initializes memory with a specific `allocator`
* `deinit`, release all allocated memory
* `walk`, iterate over the `root` and return `content` entries:
  * `directory` parameter (the `root`):
    * must be a relative path to the current working directory (cwd)
    * must already exist in the operating system
    * must be of kind `.directory` (`std.fs.File.Kind`)
  * symlinks (of kind `.sym_link`) in `directory`, count as entries
    in `content`, but are not followed (`std.fs.Dir.Walker.next`)
  * the order of returned entries in `content` is undefined
  * `self` parameter will not be `deinit` after walking it

### 📌 Important

🔔 Note that `"."` or `".."` can lead to very long runs, especially when
are used to get the `directory` path.

The module repository contains some examples for such cases.
Use `zig build run-cwddir` and run them from different locations (cwd)
to see the differences.

```txt
zdirwalker$ zig build run-cwddir
...
zdirwalker$ cd zig-out
zdirwalker/zig-out$ ./examples/cwddir
...
```

### 📌 Final Note

The steps available to use are:

```txt
zdirwalker$ zig build -l
install (default)            Copy build artifacts to prefix path
uninstall                    Remove build artifacts from prefix path
lib                          Build static library   (zig-out/lib)
tst                          Run tests
cov                          Generate code coverage (zig-out/cov)
doc                          Generate documentation (zig-out/doc)
fmt                          Silent formatting
rm-cache                     Remove cache           (zig-cache)
rm-out                       Remove output          (zig-out)
rm-bin                       Remove binary          (zig-out/bin)
rm-doc                       Remove documentation   (zig-out/doc)
rm-cov                       Remove code coverage   (zig-out/cov)
rm-lib                       Remove library         (zig-out/lib)
run-cwddir                   Run example cwddir
run-cwddir-oneup             Run example cwddir-oneup
run-exedir                   Run example exedir
run-exedir-oneup             Run example exedir-oneup
run-exedir-twoup-onedown     Run example exedir-twoup-onedown
```

Examples are:

* `cwddir`, ... - use terminal directory as `cwd`
* `exedir`, ... - use executable directory as `cwd`

For documentation (`zig-out/doc/index.html`) and the code coverage report
(`zig-out/cov/index.html`), use a live http server.
The `.vscode/extensions.json` file contains an extension that can be used for
this purpose.

Step `zig build cov` assumes that [kcov](https://github.com/SimonKagstrom/kcov)
is already installed on system.

The `standalone` directory contains an example project with `zdirwalker` as a
dependency, you just need to add the hash.

The module was made in an attempt to learn the zig language and is not very
useful. Zig has such a solution by default and I used in `build.zig` module file (see `setupExamples()`).

However, for situations with many directories/files, and which need to be
traversed often, it can be useful.

That's all about this repo.

All the best!
