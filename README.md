# spectral_cc_norns
A Norns patch that outputs eight channels of midi cc based on amplitude levels from a stereo audio signal. This midi data would be used to modulate parameters for a visual performance system. The amplitude levels would be analysed through envelope followers with variable timing for the attack and decay of sound from different fft bins.

This is all based on the engine made from the analysis code from [spectral_cc](https://github.com/khoparzi/spectral_cc)

-- 8-band dynamics visualizer & MIDI CC sender
--
-- PAGE 1: Master Stereo In/Out Level Monitor
-- PAGE 2: 8-Band Strips UI
--
-- CONTROLS:
-- K3: Switch Page (1 <-> 2)
-- K2: Switch E2 Mode (Attack <-> Gain)
-- E1: Select Band (1 - 8)
-- E2: Adjust Attack (ms) OR Gain
-- E3: Adjust Decay (s)
