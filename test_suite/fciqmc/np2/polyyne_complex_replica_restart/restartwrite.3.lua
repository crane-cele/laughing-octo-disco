system = {
    int_file = "FCIDUMP",
    nel = 24,
    ms = 0,
    sym = 1,
    complex = true,
    CAS = {8,8},
}

sys = read_in(system)

fciqmc {
    sys = sys,
    qmc = {
        tau = 1e-3,
        rng_seed = 23,
        init_pop = 10,
        mc_cycles = 20,
        nreports = 500,
        target_population = 2000,
        state_size = 750000,
        spawned_state_size = 500000,
        excit_gen = "power_pitzer_orderN",
        pattempt_update = true,
    },
    fciqmc = {
        replica_tricks = true,
    },
    restart = {
        write = 4,
    },
}
