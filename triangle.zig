extern var vs_in_position: Vec2 addrspace(.input);
extern var vs_in_color: Vec3 addrspace(.input);
extern var vs_out_position: Vec4 addrspace(.output);
extern var fs_out_color: Vec4 addrspace(.output);

export fn vs_main() callconv(.Vertex) void {
    std.gpu.location(&vs_in_position, 0);
    std.gpu.location(&vs_in_color, 1);
    std.gpu.position(&vs_out_position);
    vs_out_position = @as(Vec4, .{vs_in_position[0], vs_in_position[1], 0.0, 1.0});
}

export fn fs_main() callconv(.Fragment) void {
    std.gpu.location(&fs_out_color, 0);
    std.gpu.location(&vs_in_color, 1);
    fs_out_color = @as(Vec4, .{vs_in_color[0], vs_in_color[1], vs_in_color[2], 1.0});
}

const std = @import("std");
const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);
const Vec4 = @Vector(4, f32);


