sys = read_in {
    int_file = "INTDUMP",
    nel = 14,
    ms = 0,
    sym = 0,
}

ccmc {
    sys = sys,
    qmc = {
        tau = 0.001,
        init_pop = 500,
        rng_seed = 13086,
        mc_cycles = 10,
        nreports = 1000,
        target_population = 11000,
        state_size = -500,
        spawned_state_size = -200,
    },
    reference = {
        ex_level = 2,
    },
    -- restart file uses real amplitudes (POP_SIZE=64)
    restart = { write = 1, },
}
-- Exact CCSD energy: -0.183629 
-- Integrals obtained using the following settings in PSI4: 
-- molecule HOCl { 
--   H 
--   O 1 1.0 
--   Cl 2 1.7 1 110.0 
-- } 
-- set globals { 
--   basis 6-31g 
--   freeze_core true 
-- } 
-- energy('ccsd') 
