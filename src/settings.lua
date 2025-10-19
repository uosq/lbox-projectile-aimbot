return {
	enabled = true,
	autoshoot = true,
	fov = gui.GetValue("aim fov"),
	max_sim_time = 2.0,
	draw_time = 1.0,
	draw_proj_path = true,
	draw_player_path = true,
	draw_bounding_box = true,
	draw_only = false,
	draw_multipoint_target = false,
	max_distance = 1024,
	allow_aim_at_teammates = true,
	ping_compensation = true,
	min_priority = 0,
	explosive = true,
	close_distance = 10, --- %
	draw_quads = true,
	show_angles = true,
	max_targets = 2,
	draw_scores = true,
	smart_targeting = true,

	sim = {
		use_detonate_time = true,
		can_rotate = true,
		stay_on_ground = false,
		fast_mode = true,
	},

	max_percent = 90,
	wait_for_charge = false,
	cancel_shot = false,

	ents = {
		["aim players"] = true,
		["aim sentries"] = true,
		["aim dispensers"] = true,
		["aim teleporters"] = true,
	},

	psilent = true,

	ignore_conds = {
		cloaked = true,
		disguised = false,
		ubercharged = true,
		bonked = true,
		taunting = true,
		friends = true,
		bumper_karts = false,
		kritzkrieged = false,
		jarated = false,
		milked = false,
		vaccinator = false,
		ghost = true,
	},

	colors = {
		bounding_box = 360, --{136, 192, 208, 255},
		player_path = 360, --{136, 192, 208, 255},
		projectile_path = 360, --{235, 203, 139, 255}
		multipoint_target = 20,
		target_glow = 360,
		quads = 360,
	},

	thickness = {
		bounding_box = 1,
		player_path = 1,
		projectile_path = 1,
		multipoint_target = 1,
	},

	weights = {
		health_weight = 1.0, -- prefer lower player health
		distance_weight = 1.1, -- prefer closer players
		fov_weight = 2,
		visibility_weight = 1.2,
		speed_weight = 0.6, -- prefer slower targets
		medic_priority = 0.0, -- bonus if Medic
		sniper_priority = 0.0, -- bonus if Sniper
		uber_penalty = -2.0, -- skip/penalize Ubercharged targets
		teammate_weight = 5.0, -- on weapons that can shoot teammates, they have priority
	},

	min_score = 2,
	onfov_only = true,
}
