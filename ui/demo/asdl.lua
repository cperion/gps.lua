-- ui/demo/asdl.lua
-- Domain schema for the DAW-as-compiler mock demo.
--
-- Structural authored data (phases, tracks, devices, clips) is kept separate from
-- live UI/control state so the demo can illustrate the architecture split.

local pvm = require("pvm")

local M = {}
local T = pvm.context()
M.T = T

T:Define [[
    module Demo {
        Phase = (string key,
                 string title,
                 string verb,
                 string consumes,
                 string summary) unique

        Clip = (string id,
                string label,
                number start_beat,
                number length_beat,
                number lane,
                number color,
                boolean warped) unique

        Device = (string id,
                  string name,
                  string family,
                  boolean active) unique

        Track = (string id,
                 string name,
                 string role,
                 string destination,
                 Demo.Device* devices,
                 Demo.Clip* clips) unique

        State = (number rev,
                 number time,
                 boolean playing,
                 string selected_view,
                 number selected_phase,
                 number selected_track,
                 number compile_gen,
                 number transport_beat,
                 number bpm,
                 number cpu_usage,
                 number semantic_reuse,
                 number terra_reuse,
                 number structural_edits,
                 number live_edits,
                 string last_compile_kind,
                 number* gains_db,
                 number* pans,
                 Demo.Phase* phases,
                 Demo.Track* tracks,
                 string* logs)
    }
]]

local D = T.Demo

function D.State:current_phase()
    return self.phases[self.selected_phase]
end

function D.State:current_track()
    return self.tracks[self.selected_track]
end

function D.Track:device_summary()
    local out = {}
    for i = 1, #self.devices do
        out[i] = self.devices[i].name
    end
    return table.concat(out, " → ")
end

return M
