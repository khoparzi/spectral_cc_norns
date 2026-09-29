-- spectral_cc
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

engine.name = 'SpectralCC'
local midi_out
local midi_channel = 1
local start_cc = 20

-- Pages: 1 = Stereo Master, 2 = 8-Band Strip
local page = 1

-- E2 edit modes: 1 = Attack, 2 = Gain
local e2_mode = 1
local sel_band = 1

local num_bands = 8
local freqs = { 60, 132, 290, 639, 1405, 3091, 6801, 14962 }
local band_amps = { 0, 0, 0, 0, 0, 0, 0, 0 }
local band_peaks = { 0, 0, 0, 0, 0, 0, 0, 0 }

-- Default parameters matching SC
local atks = {}
local dcys = {}
local gains = { 1.0, 1.0, 0.7, 0.6, 0.6, 0.7, 1.0, 1.0 }

for i = 1, num_bands do
  atks[i] = math.max(0.001, 0.015 - ((i - 1) * 0.0016))
  dcys[i] = math.max(0.01, 0.18 - ((i - 1) * 0.02))
end

-- Stereo Input Monitor variables (Page 1)
local poll_l, poll_r
local master_l, master_r = 0, 0
local peak_l, peak_r = 0, 0

local function amp_to_norm_db(amp)
  if amp == nil or amp <= 0.001 then return 0 end
  local db = 20 * math.log10(amp)
  return util.clamp(util.linlin(-60, 0, 0, 1, db), 0, 1)
end

function init()
  -- MIDI Setup (Connect to device index 1 by default)
  midi_out = midi.connect(1)

  -- Parameters setup
  params:add_group("8-BAND DYNAMICS", 26)
  params:add_control("master_gain", "Master Gain", controlspec.new(0.1, 10.0, "exp", 0.01, 2.0))
  params:set_action("master_gain", function(val) engine.setMasterGain(val) end)

  for i = 1, num_bands do
    params:add_control("atk_" .. i, "Band " .. i .. " Atk", controlspec.new(0.001, 0.75, "exp", 0.001, atks[i], "s"))
    params:set_action("atk_" .. i, function(v) atks[i] = v; engine.setAtk(i, v) end)

    params:add_control("dcy_" .. i, "Band " .. i .. " Dcy", controlspec.new(0.01, 3.0, "exp", 0.01, dcys[i], "s"))
    params:set_action("dcy_" .. i, function(v) dcys[i] = v; engine.setDcy(i, v) end)

    params:add_control("gain_" .. i, "Band " .. i .. " Gain", controlspec.new(0.01, 2.5, "lin", 0.01, gains[i]))
    params:set_action("gain_" .. i, function(v) gains[i] = v; engine.setBandGain(i, v) end)
  end

  -- OSC listener for SendReply from SuperCollider
  -- osc.event = function(path, args, from)
  --   if path == "/fftAmps" then
  --     for i = 1, num_bands do
  --       local amp = util.clamp(args[i + 2] or 0, 0.0, 1.0)
  --       band_amps[i] = amp
  --       if amp > band_peaks[i] then band_peaks[i] = amp end

  --       -- Send MIDI CC values (0 - 127)
  --       local cc_val = math.floor(amp * 127)
  --       midi_out:cc(start_cc + (i - 1), cc_val, midi_channel)
  --     end
  --   end
  -- end
  
  -- OSC listener for bridged data from SuperCollider
  osc.event = function(path, args, from)
    if path == "/bandAmps" then
      for i = 1, num_bands do
        local amp = util.clamp(args[i] or 0.0, 0.0, 1.0)
        band_amps[i] = amp
        if amp > band_peaks[i] then
          band_peaks[i] = amp
        end

        -- Transmit MIDI CC (20 - 27)
        if midi_out then
          local cc_val = math.floor(amp * 127)
          midi_out:cc(start_cc + (i - 1), cc_val, midi_channel)
        end
      end
    end
  end

  -- Page 1 stereo polls
  poll_l = poll.set("sc_amp_l")
  poll_l.time = 1 / 30
  poll_l.callback = function(val)
    master_l = master_l * 0.7 + amp_to_norm_db(val) * 0.3
    if master_l > peak_l then peak_l = master_l end
  end
  poll_l:start()

  poll_r = poll.set("sc_amp_r")
  poll_r.time = 1 / 30
  poll_r.callback = function(val)
    master_r = master_r * 0.7 + amp_to_norm_db(val) * 0.3
    if master_r > peak_r then peak_r = master_r end
  end
  poll_r:start()

  -- Screen refresh metro (30 fps)
  metro.init(function()
    peak_l = math.max(master_l, peak_l - 0.005)
    peak_r = math.max(master_r, peak_r - 0.005)
    for i = 1, num_bands do
      band_peaks[i] = math.max(band_amps[i], band_peaks[i] - 0.008)
    end
    redraw()
  end, 1 / 30):start()
end

function key(n, z)
  if z == 1 then
    if n == 3 then
      page = (page == 1) and 2 or 1
    elseif n == 2 then
      -- Toggle E2 mode
      e2_mode = (e2_mode == 1) and 2 or 1
    end
  end
end

function enc(n, d)
  if page == 2 then
    if n == 1 then
      -- Select band 1-8
      sel_band = util.clamp(sel_band + d, 1, num_bands)
    elseif n == 2 then
      if e2_mode == 1 then
        params:delta("atk_" .. sel_band, d)
      else
        params:delta("gain_" .. sel_band, d)
      end
    elseif n == 3 then
      params:delta("dcy_" .. sel_band, d)
    end
  elseif page == 1 then
    if n == 2 then
      params:delta("master_gain", d)
    end
  end
end

local function draw_page_1()
  screen.level(3)
  screen.move(4, 10)
  screen.text("MASTER STEREO LEVEL")
  screen.move(78, 10)
  screen.text("K3 -> BANDS")

  local function draw_bar(label, y, val, peak)
    screen.level(4)
    screen.move(4, y + 7)
    screen.text(label)

    local bx, bw, bh = 18, 104, 10
    screen.level(2)
    screen.rect(bx, y, bw, bh)
    screen.stroke()

    local fill = math.floor(val * (bw - 2))
    if fill > 0 then
      screen.level(fill > (bw * 0.85) and 15 or 8)
      screen.rect(bx + 1, y + 1, fill, bh - 2)
      screen.fill()
    end

    local px = math.floor(bx + 1 + peak * (bw - 3))
    if px >= bx + 1 then
      screen.level(15)
      screen.move(px, y)
      screen.line(px, y + bh - 1)
      screen.stroke()
    end
  end

  draw_bar("L", 18, master_l, peak_l)
  draw_bar("R", 32, master_r, peak_r)

  screen.level(3)
  screen.move(4, 52)
  screen.text(string.format("E2: Master Gain (%.2f)", params:get("master_gain")))
  screen.move(4, 62)
  screen.text("Routing: SoundIn -> 8 BPFs -> MIDI CC 20-27")
end

local function draw_page_2()
  -- Header info strip
  screen.level(3)
  screen.move(2, 7)
  screen.text(string.format("B%d: %dHz (CC %d)", sel_band, freqs[sel_band], start_cc + sel_band - 1))

  screen.level(15)
  screen.move(96, 7)
  screen.text(e2_mode == 1 and "[ATK]" or "[GAIN]")

  -- 8 Vertical Strips (Screen width is 128px; ~15px spacing per strip)
  local col_w = 14
  local meter_h = 32
  local base_y = 44

  for i = 1, num_bands do
    local x = (i - 1) * 16 + 2

    -- Highlight selected channel background
    if i == sel_band then
      screen.level(2)
      screen.rect(x - 1, 9, col_w, meter_h + 8)
      screen.fill()
    end

    -- Meter Frame
    screen.level(i == sel_band and 5 or 2)
    screen.rect(x + 2, 11, 8, meter_h)
    screen.stroke()

    -- Active Level fill
    local fill_h = math.floor(band_amps[i] * (meter_h - 2))
    if fill_h > 0 then
      screen.level(i == sel_band and 15 or 8)
      screen.rect(x + 3, 11 + (meter_h - 2 - fill_h), 6, fill_h)
      screen.fill()
    end

    -- Peak Hold Mark
    local py = 11 + math.floor((1 - band_peaks[i]) * (meter_h - 2))
    screen.level(15)
    screen.move(x + 2, py)
    screen.line(x + 9, py)
    screen.stroke()

    -- Band number label
    screen.level(i == sel_band and 15 or 3)
    screen.move(x + 4, 52)
    screen.text(tostring(i))
  end

  -- Dynamic Footer controls
  screen.level(2)
  screen.move(2, 62)
  if e2_mode == 1 then
    screen.text(string.format("A:%.3fs  D:%.2fs (K2:Gain)", atks[sel_band], dcys[sel_band]))
  else
    screen.text(string.format("G:%.2f   D:%.2fs (K2:Atk)", gains[sel_band], dcys[sel_band]))
  end
end

function redraw()
  screen.clear()
  if page == 1 then
    draw_page_1()
  else
    draw_page_2()
  end
  screen.update()
end

function cleanup()
  if poll_l then poll_l:stop() end
  if poll_r then poll_r:stop() end
end