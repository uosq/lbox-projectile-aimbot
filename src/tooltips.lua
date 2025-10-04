return {
    enabled = "",
    autoshoot = "",
    fov = "Max FOV allowed",
    max_sim_time = "Max simulation time",
    draw_time = "Max seconds the projectile/player path can be drawn",
    draw_proj_path = "If we should draw the projectile path",
    draw_player_path = "If we should draw the player path",
    draw_bounding_box = "If we should draw the bounding box",
    draw_only = "If we should only draw the visuals",
    draw_multipoint_target = "If we should draw the multipoint target",
    max_distance = "Maximum distance to select targets",
    allow_aim_at_teammates = "If we can shoot at teammates",
    ping_compensation = "Compensate for high ping",
    min_priority = "Minimal priority",
    close_distance = "Max distance to check for visibility (%)", --- %
    draw_quads = "Draw filled bounding box",
    show_angles = "Show real viewangles",
    max_targets = "Maximum amount of targets",
    draw_scores = "If we draw the player scores",
    smart_targeting = "Enable weight system",

    sim = {
        use_detonate_time = "If we should use stickybomb's detonation time",
        can_rotate = "If we can rotate the simulation",
        stay_on_ground = "If we lock the simulation to the ground",
    },

    max_percent = "Can charge weapon until this percentage",
    wait_for_charge = "If we can charge the weapon",
    cancel_shot = "Try to cancel the shot",

    ents = {
        ["aim players"] = "Should we aim at players",
        ["aim sentries"] = "Should we aim at sentries",
        ["aim dispensers"] = "Should we aim at dispensers",
        ["aim teleporters"] = "Should we aim at teleporters",
    },

    psilent = "Use silent+ when possible",

    ignore_conds = {
        cloaked = "Should we ignore cloaked players",
        disguised = "Should we ignore disguised players",
        ubercharged = "Should we ignore ubercharged players",
        bonked = "Should we ignore bonked players",
        taunting = "Should we ignore taunting players",
        friends = "Should we ignore friends players",
        bumper_karts = "Should we ignore bumper_karts players",
        kritzkrieged = "Should we ignore kritzkrieged players",
        jarated = "Should we ignore jarated players",
        milked = "Should we ignore milked players",
        vaccinator = "Should we ignore vaccinator players",
        ghost = "Should we ignore ghost players",
    },

    colors = {
        bounding_box = "The color of the bounding box",
        player_path = "The color of the player path",
        projectile_path = "The color of the projectile path",
        multipoint_target = "The color of the multipoint target",
        target_glow = "The color of the target glow",
        quads = "The color of the filled bounding box",
    },

    thickness = {
        bounding_box = "The thickness of the bounding box",
        player_path = "The thickness of the player path",
        projectile_path = "The thickness of the projectile path",
        multipoint_target = "The thickness of the multipoint target",
    },

    weights = {
        health_weight = "The weight of player health",
        distance_weight = "The weight of player distance",
        fov_weight = "The weight of player's distance to the crossahir",
        visibility_weight = "The weight of player being visible",
        speed_weight = "The weight of player speed",
        medic_priority = "The weight of player being a medic",
        sniper_priority = "The weight of player being a sniper",
        uber_penalty = "The weight of a player being ubered",
    },

    min_score = "The minimal score to actually try shooting",
    onfov_only = "Only select players below fov",
}
