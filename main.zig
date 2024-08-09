pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) die("failed to initialize GLFW", .{});
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(640, 480, "learn-webgpu", null, null) orelse die("failed to create GLFW window", .{});
    defer c.glfwDestroyWindow(window);
    const instance = c.wgpuCreateInstance(&.{}) orelse die("failed to create wgpu instance", .{});
    defer c.wgpuInstanceRelease(instance);

    const surface = createSurfaceX11(instance, window);
    defer c.wgpuSurfaceRelease(surface);
    const adapter_opts: c.WGPURequestAdapterOptions = .{
        .compatibleSurface = surface,
    };
    const adapter = getAdapterSync(instance, &adapter_opts) orelse die("failed to create wgpu adapter", .{});
    defer c.wgpuAdapterRelease(adapter);

    const required_limits = getRequiredLimits(adapter);
    const device = getDeviceSync(adapter, &.{
        .requiredLimits = &required_limits,
        .deviceLostCallback = deviceLostCallback,
    }) orelse die("failed to create wgpu adapter", .{});
    defer c.wgpuDeviceRelease(device);

    c.wgpuDeviceSetUncapturedErrorCallback(device, deviceErrorCallback, null);

    const queue = c.wgpuDeviceGetQueue(device);
    defer c.wgpuQueueRelease(queue);

    c.wgpuSurfaceConfigure(surface, &.{
        .height = 480,
        .width = 640,
        .format = c.wgpuSurfaceGetPreferredFormat(surface, adapter),
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .device = device,
        .presentMode = c.WGPUPresentMode_Fifo,
        .alphaMode = c.WGPUCompositeAlphaMode_Auto,
    });

    const shader_src = @embedFile("shader.wgsl");
    const wgsl_desc: c.WGPUShaderModuleWGSLDescriptor = .{
        .chain = .{
            .sType = c.WGPUSType_ShaderModuleWGSLDescriptor,
        },
        .code = shader_src,
    };
    const shader_module = c.wgpuDeviceCreateShaderModule(device, &.{
        .nextInChain = &wgsl_desc.chain,
    });

    const point_data = [_]f32{
        -0.5, -0.5, -0.3, 1.0, 1.0, 1.0,
         0.5, -0.5, -0.3, 1.0, 1.0, 1.0,
         0.5,  0.5, -0.3, 1.0, 1.0, 1.0,
        -0.5,  0.5, -0.3, 1.0, 1.0, 1.0,

         0.0,  0.0,  0.5, 0.5, 0.5, 0.5,
    };
    const index_data = [_]u16{
        0, 1, 2,
        0, 2, 3,

        0, 1, 4,
        1, 2, 4,
        2, 3, 4,
        3, 0, 4,
    };

    const index_count = index_data.len;

    const point_buffer = c.wgpuDeviceCreateBuffer(device, &.{
        .label = "point",
        .size = @sizeOf(@TypeOf(point_data)),
        .usage = c.WGPUBufferUsage_CopyDst | c.WGPUBufferUsage_Vertex,
    });
    c.wgpuQueueWriteBuffer(queue, point_buffer, 0, &point_data, @sizeOf(@TypeOf(point_data)));

    const index_buffer = c.wgpuDeviceCreateBuffer(device, &.{
        .label = "index",
        .size = @sizeOf(@TypeOf(index_data)),
        .usage = c.WGPUBufferUsage_CopyDst | c.WGPUBufferUsage_Index,
    });
    c.wgpuQueueWriteBuffer(queue, index_buffer, 0, &index_data, @sizeOf(@TypeOf(index_data)));

    const uniform_buffer = c.wgpuDeviceCreateBuffer(device, &.{
        .label = "uniform",
        .size = @sizeOf(UniformBuffer),
        .usage = c.WGPUBufferUsage_CopyDst | c.WGPUBufferUsage_Uniform,
    });
    
    {


        const view = blk: {
            const angle = 3.0 * std.math.pi / 4.0;
            const R = zm.rotationX(-angle);
            const T = zm.translation(0.0, 0.0, -2.0);
            const view = zm.mul(T, R);
            break :blk zm.transpose(view);
        };

        const projection = zm.identity(); //zm.transpose(zm.perspectiveFovLh(1, 640 / 480, 0.001, 100.0),);

        const v: UniformBuffer = .{
            // filled in in the main loop
            .model = undefined,
            .view = @bitCast(view),
            .projection = @bitCast(projection),
            .color = .{0.5, 0.5, 1.0, 1.0},
            .time = 45,
        };
        c.wgpuQueueWriteBuffer(queue, uniform_buffer, 0, &v, @sizeOf(UniformBuffer));
    }

    const bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(device, &.{
        .entryCount = 1,
        .entries = &.{
            .visibility = c.WGPUShaderStage_Vertex | c.WGPUShaderStage_Fragment,
            .buffer = .{
                .type = c.WGPUBufferBindingType_Uniform,
                .minBindingSize = @sizeOf(UniformBuffer),
            },
            .sampler = .{
                .type = c.WGPUSamplerBindingType_Undefined,
            },
            .texture = .{
                .sampleType = c.WGPUTextureSampleType_Undefined,
                .viewDimension = c.WGPUTextureViewDimension_Undefined,
            },
            .storageTexture = .{
                .access = c.WGPUStorageTextureAccess_Undefined,
                .format = c.WGPUTextureFormat_Undefined,
                .viewDimension = c.WGPUTextureViewDimension_Undefined,
            },
        },
    });
    const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(device, &.{
        .bindGroupLayoutCount = 1,
        .bindGroupLayouts = &bind_group_layout,
    });


    const bind_group = c.wgpuDeviceCreateBindGroup(device, &.{
        .layout = bind_group_layout,
        .entryCount = 1,
        .entries = &.{
            .binding = 0,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(UniformBuffer),
        },
    });

    const depth_texture_format = c.WGPUTextureFormat_Depth24Plus;
    const default_stencil_state: c.WGPUStencilFaceState = .{
        .compare = c.WGPUCompareFunction_Always,
        .failOp = c.WGPUStencilOperation_Keep,
        .depthFailOp = c.WGPUStencilOperation_Keep,
        .passOp = c.WGPUStencilOperation_Keep,
    };
    const depth_texture = c.wgpuDeviceCreateTexture(device, &.{
        .dimension = c.WGPUTextureDimension_2D,
        .format = depth_texture_format,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .size = .{.width = 640, .height = 480, .depthOrArrayLayers = 1},
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .viewFormatCount = 1,
        .viewFormats = @ptrCast(&depth_texture_format),
    });
    defer c.wgpuTextureRelease(depth_texture);
    defer c.wgpuTextureDestroy(depth_texture);
    const depth_texture_view = c.wgpuTextureCreateView(depth_texture, &.{
        .aspect = c.WGPUTextureAspect_DepthOnly,
        .baseArrayLayer = 0,
        .arrayLayerCount = 1,
        .baseMipLevel = 0,
        .mipLevelCount = 1,
        .dimension = c.WGPUTextureViewDimension_2D,
        .format = depth_texture_format,
    });
    defer c.wgpuTextureViewRelease(depth_texture_view);

    const pipeline = c.wgpuDeviceCreateRenderPipeline(device, &.{
        .layout = pipeline_layout,
        .depthStencil = &.{
            .depthCompare = c.WGPUCompareFunction_Less,
            .depthWriteEnabled = 1,
            .format = depth_texture_format,
            .stencilFront = default_stencil_state,
            .stencilBack = default_stencil_state,
            .stencilReadMask = 0,
            .stencilWriteMask = 0,
        },
        .multisample = .{
            .count = 1,
            .mask = ~@as(u32, 0),
            .alphaToCoverageEnabled = 0,
        },
        .vertex = .{
            .module = shader_module,
            .entryPoint = "vs_main",
            .bufferCount = 1,
            .buffers = &.{
                .attributeCount = 2,
                .attributes = &[2]c.WGPUVertexAttribute{
                    .{
                        .shaderLocation = 0,
                        .format = c.WGPUVertexFormat_Float32x3,
                        .offset = 0,
                    },
                    .{
                        .shaderLocation = 1,
                        .format = c.WGPUVertexFormat_Float32x3,
                        .offset = 3 * @sizeOf(f32),
                    }
                },
                .arrayStride = 6 * @sizeOf(f32),
                .stepMode = c.WGPUVertexStepMode_Vertex,
            },
        },
        .primitive = .{
            .topology = c.WGPUPrimitiveTopology_TriangleList,
            .stripIndexFormat = c.WGPUIndexFormat_Undefined,
            .frontFace = c.WGPUFrontFace_CCW,
            .cullMode = c.WGPUCullMode_None,
        },
        .fragment = &.{
            .module = shader_module,
            .entryPoint = "fs_main",
            .targetCount = 1,
            .targets = &.{
                .format = c.wgpuSurfaceGetPreferredFormat(surface, adapter),
                .blend = &.{
                    .color = .{
                        .srcFactor = c.WGPUBlendFactor_SrcAlpha,
                        .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha,
                        .operation = c.WGPUBlendOperation_Add,
                    },
                    .alpha = .{
                        .srcFactor = c.WGPUBlendFactor_Zero,
                        .dstFactor = c.WGPUBlendFactor_One,
                        .operation = c.WGPUBlendOperation_Add,
                    },
                },
                .writeMask = c.WGPUColorWriteMask_All,
            },
        },
    });
    defer c.wgpuRenderPipelineRelease(pipeline);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();

        const model = blk: {
            const angle: f32 = @floatCast(c.glfwGetTime());
            const S = zm.scaling(0.3, 0.3, 0.3);
            const T = zm.translation(0.5, 0.0, 0.0);
            const R = zm.rotationX(angle);
            var model = R;
            model = zm.mul(model, T);
            model = zm.mul(model, S);
            break :blk zm.transpose(model);
        };
        c.wgpuQueueWriteBuffer(queue, uniform_buffer, @offsetOf(UniformBuffer, "model"), &model, @sizeOf(@TypeOf(model)));

        const texture_view = nextTextureView(surface) orelse continue;
        defer c.wgpuTextureViewRelease(texture_view);

        {
            const encoder = c.wgpuDeviceCreateCommandEncoder(device, &.{});
            defer c.wgpuCommandEncoderRelease(encoder);

            const render_pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &.{
                .colorAttachmentCount = 1,
                .colorAttachments = &.{
                    .view = texture_view,
                    .loadOp = c.WGPULoadOp_Clear,
                    .storeOp = c.WGPUStoreOp_Store,
                    .clearValue = .{.r = 0.05, .g = 0.05, .b = 0.05, .a = 1.0},
                },
                .depthStencilAttachment = &.{
                    .view = depth_texture_view,
                    .depthClearValue = 1.0,
                    .depthLoadOp = c.WGPULoadOp_Clear,
                    .depthStoreOp = c.WGPUStoreOp_Store,

                    .stencilClearValue = 0.0,
                    .stencilLoadOp = c.WGPULoadOp_Clear,
                    .stencilStoreOp = c.WGPUStoreOp_Store,
                    .stencilReadOnly = 1,
                },
            });

            c.wgpuRenderPassEncoderSetPipeline(render_pass, pipeline);
            c.wgpuRenderPassEncoderSetVertexBuffer(render_pass, 0, point_buffer, 0, c.wgpuBufferGetSize(point_buffer));
            c.wgpuRenderPassEncoderSetIndexBuffer(render_pass, index_buffer, c.WGPUIndexFormat_Uint16, 0, c.wgpuBufferGetSize(index_buffer));

            c.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, bind_group, 0, null);
            c.wgpuRenderPassEncoderDrawIndexed(render_pass, index_count, 1, 0, 0, 0);

            c.wgpuRenderPassEncoderEnd(render_pass);
            c.wgpuRenderPassEncoderRelease(render_pass);

            const command = c.wgpuCommandEncoderFinish(encoder, &.{});
            defer c.wgpuCommandBufferRelease(command);
            c.wgpuQueueSubmit(queue, 1, &command);

            _ = c.wgpuDevicePoll(device, 0, null);
        }

        c.wgpuSurfacePresent(surface);
    }
}

const UniformBuffer = extern struct {
    projection: [16]f32,
    view: [16]f32,
    model: [16]f32,
    color: [4]f32,
    time: f32,
    _pad: [3]f32 = undefined,
};

fn nextTextureView(surface: c.WGPUSurface) c.WGPUTextureView {
    var res: c.WGPUSurfaceTexture = undefined;
    c.wgpuSurfaceGetCurrentTexture(surface, &res);
    switch (res.status) {
        c.WGPUSurfaceGetCurrentTextureStatus_Success => {}, 
        else => return null,
    }

    return c.wgpuTextureCreateView(res.texture, &.{
        .format = c.wgpuTextureGetFormat(res.texture),
        .dimension = c.WGPUTextureViewDimension_2D,
        .baseMipLevel = 0,
        .mipLevelCount = 1,
        .baseArrayLayer = 0,
        .arrayLayerCount = 1,
        .aspect = c.WGPUTextureAspect_All,
    });
}

fn getAdapterSync(instance: c.WGPUInstance, options: *const c.WGPURequestAdapterOptions) c.WGPUAdapter {
    const callback = struct {
        pub fn f(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.C) void {
            if (status == c.WGPURequestAdapterStatus_Success) {
                const adapter_to_set: *c.WGPUAdapter = @ptrCast(@alignCast(user_data));
                adapter_to_set.* = adapter;
            } else {
                std.io.getStdErr().writer().print("{s}\n", .{message.?}) catch {};
            }
        }
    }.f;

    var adapter: c.WGPUAdapter = null;
    c.wgpuInstanceRequestAdapter(instance, options, callback, @ptrCast(&adapter));
    return adapter;
}

fn getDeviceSync(adapter: c.WGPUAdapter, desc: *const c.WGPUDeviceDescriptor) c.WGPUDevice {
    const callback = struct {
        pub fn f(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.C) void {
            if (status == c.WGPURequestAdapterStatus_Success) {
                const device_to_set: *c.WGPUDevice = @ptrCast(@alignCast(user_data));
                device_to_set.* = device;
            } else {
                std.io.getStdErr().writer().print("{s}\n", .{message.?}) catch {};
            }
        }
    }.f;

    var device: c.WGPUDevice = null;
    c.wgpuAdapterRequestDevice(adapter, desc, callback, @ptrCast(&device));
    return device;
}

fn deviceLostCallback(reason: c.WGPUDeviceLostReason, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    std.log.err("device lost: {d}: {s}", .{reason, message orelse "(no message)"});
}

fn deviceErrorCallback(flavor: c.WGPUErrorType, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    std.log.err("uncaptured device error: {d}: {s}", .{flavor, message orelse "(no message)"});
}

fn createSurfaceX11(instance: c.WGPUInstance, window: *c.GLFWwindow) c.WGPUSurface {
    const display = c.glfwGetX11Display();
    const x_window = c.glfwGetX11Window(window);
    const from_xlib_window: c.WGPUSurfaceDescriptorFromXlibWindow = .{
        .chain = .{
            .sType = c.WGPUSType_SurfaceDescriptorFromXlibWindow,
        },
        .display = display,
        .window = x_window,
    };

    const surface_desc: c.WGPUSurfaceDescriptor = .{
        .nextInChain = &from_xlib_window.chain,
    };
    return c.wgpuInstanceCreateSurface(instance, &surface_desc);
}

fn getRequiredLimits(adapter: c.WGPUAdapter) c.WGPURequiredLimits {
    var supported: c.WGPUSupportedLimits = .{};
    if (c.wgpuAdapterGetLimits(adapter, &supported) != 1) die("welp", .{});

    var required: c.WGPURequiredLimits = .{};
    const fields = @typeInfo(@TypeOf(required.limits)).Struct.fields;
    inline for (fields) |field| {
        const v = switch (field.type) {
            u32 => c.WGPU_LIMIT_U32_UNDEFINED,
            u64 => c.WGPU_LIMIT_U64_UNDEFINED,
            else => unreachable,
        };
        @field(required.limits, field.name) = v;
    }
    required.limits.minUniformBufferOffsetAlignment = supported.limits.minUniformBufferOffsetAlignment;
    required.limits.minStorageBufferOffsetAlignment = supported.limits.minStorageBufferOffsetAlignment;

    required.limits.maxVertexAttributes = 2;
    required.limits.maxVertexBuffers = 1;
    required.limits.maxBufferSize = @max(@sizeOf(UniformBuffer), 5 * 6 * @sizeOf(f32));
    required.limits.maxVertexBufferArrayStride = 6 * @sizeOf(f32);

    required.limits.maxBindGroups = 1;
    required.limits.maxUniformBuffersPerShaderStage = 1;
    required.limits.maxUniformBufferBindingSize = @sizeOf(UniformBuffer);

    required.limits.maxTextureDimension1D = 480;
    required.limits.maxTextureDimension2D = 640;
    required.limits.maxTextureArrayLayers = 1;

    return required;
}


fn die(comptime fmt: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer().print(fmt, args) catch {};
    std.process.exit(1);
}

const std = @import("std");
const zm = @import("zmath");
const c = @import("c.zig");
const assert = std.debug.assert;
