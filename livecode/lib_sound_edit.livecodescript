script "lib_sound_edit"
-- LIB_AUDIO sound editor (24 Nov 2026, Priority Tube a1-01): the SOUND EDIT window, opened by
-- Edit... in the AUDIO window. A sound is LIB_SFX's 24 numbers (rfxgen, the sfxr family): the
-- window shows them as sliders, makes a new one from a preset, nudges it (Mutate), plays every
-- change at once (Hear), draws its wave, and goes back (Undo / Start again).
--
--   start using stack ".../LIB_AUDIO/livecode/lib_sound_edit.livecodescript"
--   SEdit.Open "Explode/Explode_42.wav", tSoundsFolder, "Canyon"
--
-- Which numbers a file opens with (SEdit.How()):
--   rfx    <file>.rfx beside the .wav (what Save writes: step 2)
--   kit    <Type>_<seed>.wav of the kit: preset + seed + overrides from kit.txt (as bake_kit made it)
--   preset any other file: the preset its folder uses in kit.txt (the numbers are a start, not the file)
-- Needs LIB_SFX (lib_sfx.livecodescript + C:/xtsfx/extension, made by LIB_SFX/build.bat). Without it
-- SEdit.Open says why in the result and nothing else happens.

constant kStack = "SOUND EDIT"
constant kSound = "edit"        -- the sound's name inside LIB_SFX
constant kRows = "attackTime,sustainTime,sustainPunch,decayTime,startFrequency,minFrequency,slide,deltaSlide,vibratoDepth,vibratoSpeed,changeAmount,changeSpeed,squareDuty,dutySweep,repeatSpeed,phaserOffset,phaserSweep,lpfCutoff,lpfCutoffSweep,lpfResonance,hpfCutoff,hpfCutoffSweep"
constant kSigned = "slide,deltaSlide,changeAmount,dutySweep,phaserOffset,phaserSweep,lpfCutoffSweep,hpfCutoffSweep"
constant kWaves = "Square,Saw,Sine,Noise"

local sEntry         -- the Sounds-relative file opened
local sRoot          -- the Sounds folder
local sGame          -- the game whose window opened it
local sHow           -- rfx | kit | preset
local sStartParams   -- the numbers it opened with
local sUndo          -- earlier numbers, newest last, separated by kUndoSep lines
local sUndoN
local sApplyMsg      -- the pending SEdit.ApplyNow
local sPending       -- [param] value waiting for SEdit.ApplyNow
local sSeed          -- for Mutate and the presets: a new sound each click
local sQuiet         -- true: changes are not played and the window is not shown (tests)

-------------------------------------------------------------------------------------------
-- Starting LIB_SFX

-- empty when LIB_SFX is ready, else why not (one line)
function SEdit.Start
   local tLib, tErr, tMyDir, tSfxDir
   put the effective filename of me into tMyDir
   replace "\" with "/" in tMyDir
   set the itemDel to "/"
   put item 1 to -2 of tMyDir into tMyDir
   set the itemDel to comma
   try
      if "lib_sfx" is not among the lines of the stacksInUse then
         -- an installed copy: lib_sfx beside this file; on the owner's PC: projects/LIB_SFX
         put tMyDir & "/lib_sfx.livecodescript" into tLib
         if there is not a file tLib then put SEdit.Projects() & "/LIB_SFX/livecode/lib_sfx.livecodescript" into tLib
         if there is not a file tLib then return "no LIB_SFX (" & tLib & ")"
         start using stack tLib
      end if
      -- the extension (xtsfx.dll): xtsfx/ beside this file when installed, else LIB_SFX's C:/xtsfx/extension
      if there is a file (tMyDir & "/xtsfx/module.lcm") then put tMyDir & "/xtsfx" into tSfxDir
      Sfx.Start tSfxDir
      if the result is not empty then return the result
   catch tErr
      return "LIB_SFX did not start:" && line 1 of tErr
   end try
   return empty
end SEdit.Start

-- the projects folder: three folders up from this file (projects/LIB_AUDIO/livecode/)
function SEdit.Projects
   local tFile
   put the effective filename of me into tFile
   replace "\" with "/" in tFile
   set the itemDel to "/"
   return item 1 to -4 of tFile
end SEdit.Projects

-- kit.txt (type <tab> preset <tab> seeds [<tab> overrides]): the Sounds folder's own, else LIB_SFX's
function SEdit.KitFile
   if sRoot is not empty and there is a file (sRoot & "/kit.txt") then return sRoot & "/kit.txt"
   if there is a file (SEdit.Projects() & "/LIB_SFX/kit/kit.txt") then return SEdit.Projects() & "/LIB_SFX/kit/kit.txt"
   return empty
end SEdit.KitFile

-- the kit.txt line of a type (empty: none)
function SEdit.KitLine pType
   local tFile, tLine
   put SEdit.KitFile() into tFile
   if tFile is empty then return empty
   set the itemDel to tab
   repeat for each line tLine in textDecode(URL ("binfile:" & tFile), "UTF-8")
      replace numToChar(13) with empty in tLine
      if char 1 of tLine is "#" then next repeat
      if item 1 of tLine is pType then return tLine
   end repeat
   return empty
end SEdit.KitLine

-------------------------------------------------------------------------------------------
-- Opening a sound

-- pEntry: Sounds-relative file, or a folder ending "/" (its first .wav). Returns empty or why not.
command SEdit.Open pEntry, pRoot, pGame
   local tWhy
   put SEdit.Start() into tWhy
   if tWhy is not empty then return tWhy
   if pRoot is not empty then put pRoot into sRoot
   put pGame into sGame
   if char -1 of pEntry is "/" then put SEdit.FirstWav(pEntry) into pEntry
   put SEdit.Load(pEntry) into tWhy
   if tWhy is not empty then return tWhy
   put pEntry into sEntry
   put Sfx.Params(kSound) into sStartParams
   put empty into sUndo
   put 0 into sUndoN
   SEdit.UIBuild
   SEdit.UIShow
   set the title of stack kStack to "FOR OWNER | SOUND EDIT:" && pEntry
   if sQuiet is not true then show stack kStack   -- quiet (tests): made but never shown
   SEdit.Status "opened" && pEntry && "(" & SEdit.HowWords() & ")"
   return empty
end SEdit.Open

function SEdit.FirstWav pFolder
   local tOld, tFiles
   if char -1 of pFolder is "/" then delete char -1 of pFolder
   if there is not a folder (sRoot & "/" & pFolder) then return pFolder & "/"
   put the folder into tOld
   set the folder to sRoot & "/" & pFolder
   put files() into tFiles
   set the folder to tOld
   filter tFiles with "*.wav"
   sort tFiles
   return pFolder & "/" & line 1 of tFiles
end SEdit.FirstWav

-- makes kSound from a file's numbers; sets sHow. Empty or why not.
function SEdit.Load pEntry
   local tFull, tRfx, tName, tType, tSeed, tLine, tFolder, tWhy
   put sRoot & "/" & pEntry into tFull
   put tFull into tRfx
   if tRfx ends with ".wav" then put char 1 to -5 of tRfx & ".rfx" into tRfx
   if there is a file tRfx then
      Sfx.Load kSound, tRfx
      if the result is empty then
         put "rfx" into sHow
         return empty
      end if
   end if
   set the itemDel to "/"
   put item -1 of pEntry into tName
   put item -2 of pEntry into tFolder
   set the itemDel to comma
   -- <Type>_<seed>.wav: the kit's own recipe
   if matchText(tName, "^([A-Za-z]+)_([0-9]+)\.wav$", tType, tSeed) then
      put SEdit.KitLine(tType) into tLine
      set the itemDel to tab
      if tLine is not empty and tSeed is among the items of (replaceText(item 3 of tLine, ",", tab)) then
         Sfx.Make kSound, item 2 of tLine, tSeed
         if item 4 of tLine is not empty then Sfx.SetParams kSound, replaceText(item 4 of tLine, ";", return)
         set the itemDel to comma
         put "kit" into sHow
         return empty
      end if
      set the itemDel to comma
   end if
   -- the preset its folder (category) uses
   put SEdit.KitLine(tFolder) into tLine
   set the itemDel to tab
   if tLine is not empty then
      Sfx.Make kSound, item 2 of tLine, item 1 of (replaceText(item 3 of tLine, ",", tab))
      put the result into tWhy
      if tWhy is empty and item 4 of tLine is not empty then
         Sfx.SetParams kSound, replaceText(item 4 of tLine, ";", return)
      end if
   else
      Sfx.Make kSound, "blip", 1
      put the result into tWhy
   end if
   set the itemDel to comma
   if tWhy is not empty then return tWhy
   put "preset" into sHow
   return empty
end SEdit.Load

function SEdit.How
   return sHow
end SEdit.How

function SEdit.HowWords
   switch sHow
      case "rfx"
         return "its own numbers"
      case "kit"
         return "the kit's numbers for it"
      default
         return "a start from its kind of sound, not the file itself"
   end switch
end SEdit.HowWords

function SEdit.Params
   return Sfx.Params(kSound)
end SEdit.Params

function SEdit.Entry
   return sEntry
end SEdit.Entry

-------------------------------------------------------------------------------------------
-- Changing it (every change can be undone; every change is heard unless sQuiet)

command SEdit.SetQuiet pOn
   put (pOn is true) into sQuiet
end SEdit.SetQuiet

command SEdit.Remember
   add 1 to sUndoN
   put Sfx.Params(kSound) into sUndo[sUndoN]
   if sUndoN > 50 then
      delete variable sUndo[sUndoN - 50]
   end if
end SEdit.Remember

command SEdit.Set pParam, pValue
   local tWhy
   SEdit.Remember
   Sfx.Set kSound, pParam, pValue
   put the result into tWhy
   SEdit.Changed "set" && pParam && pValue, tWhy
end SEdit.Set

command SEdit.Preset pPreset
   local tWhy
   SEdit.Remember
   add 1 to sSeed
   Sfx.Make kSound, pPreset, (the milliseconds mod 100000) + sSeed
   put the result into tWhy
   SEdit.Changed "new" && pPreset, tWhy
end SEdit.Preset

command SEdit.Mutate
   local tWhy
   SEdit.Remember
   add 1 to sSeed
   Sfx.Mutate kSound, (the milliseconds mod 100000) + sSeed
   put the result into tWhy
   SEdit.Changed "nudged", tWhy
end SEdit.Mutate

command SEdit.Wave pN
   SEdit.Set "waveType", pN
end SEdit.Wave

command SEdit.Undo
   local tWhy
   if sUndoN < 1 or sUndo[sUndoN] is empty then
      SEdit.Status "nothing to undo"
      exit SEdit.Undo
   end if
   Sfx.SetParams kSound, sUndo[sUndoN]
   put the result into tWhy
   delete variable sUndo[sUndoN]
   subtract 1 from sUndoN
   SEdit.Changed "undone", tWhy
end SEdit.Undo

command SEdit.StartAgain
   local tWhy
   SEdit.Remember
   Sfx.SetParams kSound, sStartParams
   put the result into tWhy
   SEdit.Changed "back to how it opened", tWhy
end SEdit.StartAgain

command SEdit.Hear
   if not Sfx.Has(kSound) then exit SEdit.Hear
   Sfx.Play kSound
end SEdit.Hear

-- after a change: sliders, wave, sound
command SEdit.Changed pWhat, pWhy
   if pWhy is not empty then
      SEdit.Status "not done:" && pWhy
      exit SEdit.Changed
   end if
   SEdit.UIShow
   if sQuiet is not true then SEdit.Hear
   SEdit.Status pWhat & "  (" & round(Sfx.Duration(kSound), 2) && "s)"
end SEdit.Changed

-- a slider moves: its number shows at once; the sound is made when it rests for 150 ms
command SEdit.Slid pParam, pPos
   put SEdit.FromPos(pParam, pPos) into sPending[pParam]
   if there is a field ("V_" & pParam) of card 1 of stack kStack then put format("%.3f", sPending[pParam]) into field ("V_" & pParam) of card 1 of stack kStack
   if sApplyMsg is not empty then cancel sApplyMsg
   send "SEdit.ApplyNow" to me in 150 milliseconds
   put the result into sApplyMsg
end SEdit.Slid

command SEdit.ApplyNow
   local p, tText, tWhy
   put empty into sApplyMsg
   if sPending is empty then exit SEdit.ApplyNow
   repeat for each key p in sPending
      put p & "=" & sPending[p] & return after tText
   end repeat
   put empty into sPending
   SEdit.Remember
   Sfx.SetParams kSound, tText
   put the result into tWhy
   SEdit.Changed "changed" && line 1 of tText, tWhy
end SEdit.ApplyNow

-- slider positions are 0..1000; signed numbers go -1..1, the rest 0..1
function SEdit.FromPos pParam, pPos
   if pParam is among the items of kSigned then return round((pPos - 500) / 500, 3)
   return round(pPos / 1000, 3)
end SEdit.FromPos

function SEdit.ToPos pParam, pValue
   if pValue is not a number then put 0 into pValue
   if pParam is among the items of kSigned then return max(0, min(1000, round(pValue * 500 + 500)))
   return max(0, min(1000, round(pValue * 1000)))
end SEdit.ToPos

-- plain words for the numbers
function SEdit.Label pParam
   switch pParam
      case "attackTime"
         return "Attack"
      case "sustainTime"
         return "Hold"
      case "sustainPunch"
         return "Punch"
      case "decayTime"
         return "Fade out"
      case "startFrequency"
         return "Pitch"
      case "minFrequency"
         return "Lowest pitch"
      case "slide"
         return "Slide"
      case "deltaSlide"
         return "Slide change"
      case "vibratoDepth"
         return "Wobble"
      case "vibratoSpeed"
         return "Wobble speed"
      case "changeAmount"
         return "Pitch jump"
      case "changeSpeed"
         return "Jump when"
      case "squareDuty"
         return "Square width"
      case "dutySweep"
         return "Width sweep"
      case "repeatSpeed"
         return "Repeat"
      case "phaserOffset"
         return "Phaser"
      case "phaserSweep"
         return "Phaser sweep"
      case "lpfCutoff"
         return "Muffle (low-pass)"
      case "lpfCutoffSweep"
         return "Muffle sweep"
      case "lpfResonance"
         return "Ring"
      case "hpfCutoff"
         return "Thin (high-pass)"
      case "hpfCutoffSweep"
         return "Thin sweep"
   end switch
   return pParam
end SEdit.Label

-------------------------------------------------------------------------------------------
-- Saving (step 2): always a NEW file, the old one stays (the owner keeps old builds).
--   this game:  Sounds/<Game>/<Category>/<Category>_<n>.wav  (the game's own: wins over the kit)
--   every game: Sounds/<Category>/<Category>_<n>.wav         (the shared kit)
-- with <same name>.rfx beside it, so it opens again with exactly these numbers. AUDIO is told
-- (Audio.EditSaved): the kit list shows it, and the word it was opened from gets it (then Save there).
-- pFor: "game" or "every" answers without asking (tests). Returns the Sounds-relative file, or empty.

command SEdit.Save pFor
   local tCat, tDir, tN, tBase, tRel, tWhy, tErr
   if not Sfx.Has(kSound) then exit SEdit.Save
   set the itemDel to "/"
   put item -2 of sEntry into tCat
   set the itemDel to comma
   if tCat is empty then put "Sounds" into tCat
   if pFor is empty then
      if sGame is empty then
         answer "Save this sound into the shared" && tCat && "folder (every game)?" with "Cancel" or "Every game"
      else
         answer "Save this" && tCat && "sound for" && sGame && "only, or for every game?" with "Cancel" or "Every game" or ("This game")
      end if
      if it is "Cancel" or it is empty then
         SEdit.Status "not saved"
         return empty
      end if
      if it is "Every game" then put "every" into pFor
      else put "game" into pFor
   end if
   if pFor is "game" and sGame is not empty then
      put sGame & "/" & tCat into tRel
   else
      put tCat into tRel
   end if
   put sRoot & "/" & tRel into tDir
   SEdit.MakeFolders tDir
   put 1 into tN
   repeat while there is a file (tDir & "/" & tCat & "_" & tN & ".wav") or there is a file (tDir & "/" & tCat & "_" & tN & ".rfx")
      add 1 to tN
   end repeat
   put tCat & "_" & tN into tBase
   Sfx.Export kSound, tDir & "/" & tBase & ".wav", 22050, 16, 1
   put the result into tWhy
   if tWhy is empty then
      Sfx.Save kSound, tDir & "/" & tBase & ".rfx"
      put the result into tWhy
   end if
   if tWhy is not empty then
      SEdit.Status "NOT saved:" && tWhy
      return empty
   end if
   put tRel & "/" & tBase & ".wav" into tRel
   put tRel into sEntry
   put "rfx" into sHow
   put Sfx.Params(kSound) into sStartParams
   if there is a stack kStack then
      put sEntry into field "Title" of card 1 of stack kStack
      set the title of stack kStack to "FOR OWNER | SOUND EDIT:" && sEntry
   end if
   try
      if "lib_audio" is among the lines of the stacksInUse then Audio.EditSaved tRel
   catch tErr
   end try
   SEdit.Status "saved" && tRel
   return tRel
end SEdit.Save

command SEdit.MakeFolders pPath
   local tSoFar, tPart, tErr
   set the itemDel to "/"
   repeat for each item tPart in pPath
      if tSoFar is empty and tPart is empty then
         put "/" into tSoFar
         next repeat
      end if
      if tSoFar is empty or tSoFar is "/" or char -1 of tSoFar is "/" then put tSoFar & tPart into tSoFar
      else put tSoFar & "/" & tPart into tSoFar
      if tSoFar ends with ":" or tPart is empty then next repeat
      try
         if there is not a folder tSoFar then create folder tSoFar
      catch tErr
      end try
   end repeat
   set the itemDel to comma
end SEdit.MakeFolders

-------------------------------------------------------------------------------------------
-- The window (made once, in memory). Template colours first (owner's rule), dark like AUDIO.

command SEdit.UIBuild
   local tDef, tY, p, tC, i, tX, tW
   if there is a stack kStack then exit SEdit.UIBuild
   put the defaultStack into tDef
   lock screen
   lock messages
   reset the templateStack
   set the backgroundColor of the templateStack to "18,18,22"
   create invisible stack kStack
   set the defaultStack to kStack
   set the destroyStack of stack kStack to true
   set the resizable of stack kStack to false
   -- beside the AUDIO window (200,32 .. 1100,632)
   set the rect of stack kStack to 1106, 32, 1526, 652
   set the script of stack kStack to "on closeStackRequest" & cr & "  SEdit.Close" & cr & "end closeStackRequest"
   reset the templateField
   set the textColor of the templateField to "220,220,220"
   set the backgroundColor of the templateField to "24,24,28"
   set the textFont of the templateField to "Courier New"
   set the textSize of the templateField to 12
   set the lockText of the templateField to true
   set the borderWidth of the templateField to 0
   set the traversalOn of the templateField to false
   reset the templateButton
   set the backgroundColor of the templateButton to "60,60,72"
   set the textColor of the templateButton to "230,230,230"
   set the textSize of the templateButton to 11
   reset the templateScrollbar
   set the backgroundColor of the templateScrollbar to "40,40,48"
   reset the templateGraphic
   set the foregroundColor of the templateGraphic to "120,220,160"
   put "on mouseUp" & cr & "  #" & cr & "end mouseUp" into tC
   create field "Title"
   set the rect of field "Title" to 10, 6, 410, 26
   -- presets
   put 10 into tX
   repeat for each item p in Sfx.Presets()
      create button ("P_" & p)
      set the label of button ("P_" & p) to p
      set the rect of button ("P_" & p) to tX, 30, tX + 48, 52
      set the script of button ("P_" & p) to replaceText(tC, "#", "SEdit.Preset" && quote & p & quote)
      set the toolTip of button ("P_" & p) to "a new" && p && "sound (each click another one)"
      add 50 to tX
   end repeat
   -- wave type
   create field "L_wave"
   set the rect of field "L_wave" to 10, 58, 120, 76
   put "Wave" into field "L_wave"
   put 122 into tX
   repeat with i = 1 to 4
      create button ("W_" & i - 1)
      set the label of button ("W_" & i - 1) to item i of kWaves
      set the rect of button ("W_" & i - 1) to tX, 56, tX + 68, 76
      set the script of button ("W_" & i - 1) to replaceText(tC, "#", "SEdit.Wave" && i - 1)
      add 70 to tX
   end repeat
   -- the sliders
   put 82 into tY
   repeat for each item p in kRows
      create field ("L_" & p)
      set the rect of field ("L_" & p) to 10, tY, 128, tY + 17
      put SEdit.Label(p) into field ("L_" & p)
      set the toolTip of field ("L_" & p) to p
      create scrollbar ("S_" & p)
      set the style of scrollbar ("S_" & p) to "scale"
      set the showValue of scrollbar ("S_" & p) to false
      set the startValue of scrollbar ("S_" & p) to 0
      set the endValue of scrollbar ("S_" & p) to 1000
      set the rect of scrollbar ("S_" & p) to 130, tY, 352, tY + 17
      set the toolTip of scrollbar ("S_" & p) to p
      set the script of scrollbar ("S_" & p) to "on scrollbarDrag pPos" & cr & "  SEdit.Slid" && quote & p & quote & ", pPos" & cr & "end scrollbarDrag"
      create field ("V_" & p)
      set the rect of field ("V_" & p) to 354, tY, 410, tY + 17
      set the textAlign of field ("V_" & p) to "right"
      add 19 to tY
   end repeat
   -- the wave picture
   create graphic "WaveBox"
   set the style of graphic "WaveBox" to "rectangle"
   set the filled of graphic "WaveBox" to true
   set the backgroundColor of graphic "WaveBox" to "10,10,12"
   set the foregroundColor of graphic "WaveBox" to "50,50,60"
   set the rect of graphic "WaveBox" to 10, tY + 2, 410, tY + 46
   create graphic "Wave"
   set the style of graphic "Wave" to "polygon"
   set the rect of graphic "Wave" to 10, tY + 2, 410, tY + 46
   set the uMid of graphic "Wave" to tY + 24
   add 50 to tY
   -- buttons
   put 10 into tX
   repeat for each item p in "Hear,Mutate,Undo,Start again,Save...,Close"
      put 62 into tW
      create button p
      set the rect of button p to tX, tY, tX + tW, tY + 24
      switch p
         case "Hear"
            set the script of button p to replaceText(tC, "#", "SEdit.Hear")
            break
         case "Mutate"
            set the script of button p to replaceText(tC, "#", "SEdit.Mutate")
            set the toolTip of button p to "nudge every number a little"
            break
         case "Undo"
            set the script of button p to replaceText(tC, "#", "SEdit.Undo")
            break
         case "Start again"
            set the script of button p to replaceText(tC, "#", "SEdit.StartAgain")
            set the toolTip of button p to "back to the numbers it opened with"
            break
         case "Save..."
            set the script of button p to replaceText(tC, "#", "SEdit.Save")
            set the toolTip of button p to "a new sound file for this game, or for every game (the old one stays)"
            break
         case "Close"
            set the script of button p to replaceText(tC, "#", "SEdit.Close")
            break
      end switch
      add tW + 6 to tX
   end repeat
   create field "Status"
   set the rect of field "Status" to 10, tY + 30, 410, tY + 48
   reset the templateField
   reset the templateButton
   reset the templateScrollbar
   reset the templateGraphic
   reset the templateStack
   unlock messages
   unlock screen
   set the defaultStack to tDef
end SEdit.UIBuild

-- the numbers onto the sliders, the wave type hilited, the wave drawn
command SEdit.UIShow
   local p, v, w
   if there is not a stack kStack then exit SEdit.UIShow
   lock screen
   lock messages
   put sEntry into field "Title" of card 1 of stack kStack
   repeat for each item p in kRows
      put Sfx.Get(kSound, p) into v
      set the thumbPosition of scrollbar ("S_" & p) of card 1 of stack kStack to SEdit.ToPos(p, v)
      if v is a number then put format("%.3f", v) into field ("V_" & p) of card 1 of stack kStack
   end repeat
   put Sfx.Get(kSound, "waveType") into w
   repeat with v = 0 to 3
      if v = w then set the backgroundColor of button ("W_" & v) of card 1 of stack kStack to "90,140,110"
      else set the backgroundColor of button ("W_" & v) of card 1 of stack kStack to "60,60,72"
   end repeat
   SEdit.DrawWave
   unlock messages
   unlock screen
end SEdit.UIShow

command SEdit.DrawWave
   local tPeaks, tPts, tX, tMid, tPeak, tTall
   put Sfx.Peaks(kSound, 200) into tPeaks
   put 10 into tX
   put the uMid of graphic "Wave" of card 1 of stack kStack into tMid
   repeat for each item tPeak in tPeaks
      put max(1, round(tPeak * 20 / 1000)) into tTall
      put tX & "," & (tMid - tTall) & return & tX & "," & (tMid + tTall) & return & return after tPts
      add 2 to tX
   end repeat
   set the points of graphic "Wave" of card 1 of stack kStack to tPts
end SEdit.DrawWave

command SEdit.Status pMsg
   if there is a stack kStack and there is a field "Status" of card 1 of stack kStack then put pMsg into field "Status" of card 1 of stack kStack
end SEdit.Status

function SEdit.IsOpen
   return there is a stack kStack and the visible of stack kStack
end SEdit.IsOpen

command SEdit.Close
   local tErr
   if sApplyMsg is not empty then cancel sApplyMsg
   put empty into sApplyMsg
   try
      Sfx.Stop
   catch tErr
   end try
   if there is a stack kStack then
      set the destroyStack of stack kStack to true
      close stack kStack
      if there is a stack kStack then delete stack kStack
   end if
end SEdit.Close
