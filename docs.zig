const zm = @import("zmath");
const useful_c_stuff = @cImport({
    @cInclude("webgpu.h");
    @cInclude("wgpu.h");
    @cInclude("GLFW/glfw3.h");
});

test {
    _ = zm;
    _ = useful_c_stuff;
}
