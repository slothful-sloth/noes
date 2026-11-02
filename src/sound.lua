-- sound.lua: short effects through TTS's MusicPlayer (heard by everyone).
local C = require("config")

local Sound = {}

local CLIPS = {
  knock = { file = "sounds/knock.wav", title = "¡Paso!" },
  slam = { file = "sounds/slam.wav", title = "¡Pa'fuera!" },
  spin = { file = "sounds/spin.wav", title = "Spin" },
}

function Sound.play(name)
  local clip = CLIPS[name]
  if not clip or MusicPlayer == nil then return end
  pcall(function()
    MusicPlayer.setCurrentAudioclip({ url = C.asset(clip.file), title = clip.title })
    Wait.time(function() pcall(function() MusicPlayer.play() end) end, 0.1)
  end)
end

return Sound
