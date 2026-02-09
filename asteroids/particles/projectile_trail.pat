import "/engine/particles/common.pai"

emitter ProjectileTrail {
	material "/asteroids/particles/projectile_trace.mat"
	init_emit_count 0
	emit_per_second 60

	out i_position : float3
	out i_scale : float
	out i_color : float4
	out i_rot : float
	out i_frame : float
	out i_emission : float

	var pos : float3
	var vel : float3
	var t : float
	var life : float
	var rot : float

	fn emit() {
		pos = entity_position;
		vel.x = random(-0.5, 0.5);
		vel.y = random(-0.2, 0.2);
		vel.z = random(-0.5, 0.5);
		life = random(0.12, 0.22);
		t = 0;
		rot = random(0, 2 * PI);
	}

	fn update() {
		t = t + time_delta;
		pos = pos + vel * time_delta;
		if t > life {
			kill();
		}
	}

	fn output() {
		let k = saturate(1 - t / life);
		i_position = pos;
		i_scale = 0.02 + 0.05 * k;
		i_color = {1, 1, 1, 0.35 * k};
		i_rot = rot;
		i_frame = 0;
		i_emission = 2 * k;
	}
}
