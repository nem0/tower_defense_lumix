import "/engine/particles/common.pai"

emitter ShipExhaust {
	material "/asteroids/particles/kenney_trace.mat"
	max_ribbons 1
	init_ribbons_count 1
	max_ribbon_length 60
	emit_move_distance 0.02

	out i_position : float3
	out i_scale : float
	out i_color : float4
	out i_emission : float
	
	var pos : float3
	var t : float

	fn emit() {
		t = 1;
		pos = entity_position;
	}

	fn update() {
		t = t - time_delta * 2;
		t = max(t, 0);
	}

	fn output() {
		i_position = pos;
		i_scale = 0.15;
		i_color = {0.5, 0.7, 1.0, t * t};
		i_emission = 5 * t;
	}
}
