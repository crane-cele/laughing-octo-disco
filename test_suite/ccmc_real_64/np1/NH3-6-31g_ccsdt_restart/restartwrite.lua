sys = read_in {
    int_file = "INTDUMP",
    nel = 10,
    ms = 0,
    sym = 0,
}

ccmc {
    sys = sys,
    qmc = {
        tau = 0.0007,
        init_pop = 1000,
        rng_seed = 30513,
        mc_cycles = 10,
        nreports = 2000,
        target_population = 12000,
        real_amplitudes = true,
        state_size = -200,
        spawned_state_size = -200,
    },
    reference = {
        ex_level = 3,
    },
    -- restart uses real populations with POP_SIZE=32
    restart = { write = 0, },
}
-- Exact CCSDT energy: -0.124920 
-- Integrals obtained using the following settings in PSI4: 
-- molecule NH3  { 
--   X 
--   N 1 rX 
--   H 2 rNH 1 aXNH 
--   H 2 rNH 1 aXNH 3 a1 
--   H 2 rNH 1 aXNH 4 a1 
--  
--   rX = 1.0 
--   rNH = 0.95 
--   aXNH = 115.0 
--   a1 = 120.0 
-- } 
-- set globals { 
--   basis 6-31g* 
--   freeze_core true 
-- }
