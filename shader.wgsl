
struct UniformBuffer {
	projection: mat4x4f,
	view: mat4x4f,
	model: mat4x4f,
	color: vec4f,
	time: f32,
};
@group(0) @binding(0) var<uniform> uniform: UniformBuffer;

struct VertexInput {
	@location(0) position: vec3f,
	@location(1) color: vec3f,
};

struct VertexOutput {
	@builtin(position) position: vec4f,
	@location(0) color: vec3f,
};


@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;
	out.position = uniform.projection * uniform.view * uniform.model * vec4f(in.position, 1.0);
	out.color = in.color;
	return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
	let color = in.color * uniform.color.rgb;

	let corrected = pow(color, vec3f(2.2));
	return vec4f(corrected, uniform.color.a);
}
