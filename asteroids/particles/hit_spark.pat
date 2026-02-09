import "/engine/particles/common.pai"

const G = 9.8;

emitter HitSpark {
	material "/asteroids/particles/kenney_spark.mat"
	init_emit_count 18
	emit_per_second 0

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
		vel.x = random(-4, 4);
		vel.y = random(1, 5);
		vel.z = random(-4, 4);
		life = random(0.18, 0.35);
		t = 0;
		rot = random(0, 2 * PI);
	}

	fn update() {
		t = t + time_delta;
		vel.y = vel.y - G * time_delta;
		pos = pos + vel * time_delta;
		if t > life {
			kill();
		}
	}

	fn output() {
		let k = saturate(1 - t / life);
		i_position = pos;
		i_scale = 0.07 + 0.12 * k;
		i_color = {1, 0.75, 0.2, k};
		i_rot = rot;
		i_frame = 0;
		i_emission = 10 * k;
	}
}
