import "/engine/particles/common.pai"

const G = 9.8;

emitter ExplosionFlash {
	material "/tower_defense/particles/kenney_light.mat"
	init_emit_count 1
	emit_per_second 0

	out i_position : float3
	out i_scale : float
	out i_color : float4
	out i_rot : float
	out i_frame : float
	out i_emission : float

	var pos : float3
	var t : float
	var life : float

	fn emit() {
		pos = entity_position;
		t = 0;
		life = 0.12;
	}

	fn update() {
		t = t + time_delta;
		if t > life {
			kill();
		}
	}

	fn output() {
		let k = saturate(1 - t / life);
		i_position = pos;
		i_scale = 0.25 + 0.8 * (1 - k);
		i_color = {1, 0.9, 0.7, k};
		i_rot = 0;
		i_frame = 0;
		i_emission = 30 * k;
	}
}

emitter ExplosionSmoke {
	material "/tower_defense/particles/kenney_smoke.mat"
	init_emit_count 26
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
		vel.x = random(-1.6, 1.6);
		vel.y = random(0.8, 2.2);
		vel.z = random(-1.6, 1.6);
		life = random(0.8, 1.3);
		t = 0;
		rot = random(0, 2 * PI);
	}

	fn update() {
		t = t + time_delta;
		vel.y = vel.y - G * time_delta * 0.2;
		pos = pos + vel * time_delta;
		if t > life {
			kill();
		}
	}

	fn output() {
		let k = saturate(1 - t / life);
		i_position = pos;
		i_scale = 0.2 + 0.9 * (1 - k);
		i_color = {0.35, 0.35, 0.35, 0.7 * k};
		i_rot = rot;
		i_frame = 0;
		i_emission = 0;
	}
}
