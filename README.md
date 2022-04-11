# SwiftInMemoryLoading

Swift implementation of in-memory Mach-O execution. Tt should be noted that this is not truly file-less on macOS Monterey (see blogpost).
- ```./SwiftInMemoryLoading /full/path/to/binary arg1 arg2 arg3```


## Blogpost
fill_in


## Example

![Example](https://raw.githubusercontent.com/slyd0g/SwiftInMemoryLoading/main/example.png)

## Credit
- https://github.com/its-a-feature/macos_execute_from_memory
- https://github.com/djhohnstein/macos_shell_memory
- https://gist.github.com/johnkhbaek/771a98212045f327cc1c86aaac63a4e3
- https://hackd.net/posts/macos-reflective-code-loading-analysis/
- [Timo Schmid](https://twitter.com/bluec0re) and [Carl Svensson](https://twitter.com/zetatwo) for discovering the changes in NSLinkModule's return value on Monterey