script "lib_audio"
-- LIB_AUDIO (23 Nov 2026): the hidden AUDIO stack. A pool of ready-made players, a card of
-- "words" per game (sound name -> file), the files given to players ONE PER TICK (send in time,
-- never a repeat loop over the disk), so nothing freezes. Plan: LIB_AUDIO/PLAN.md.
--
--   start using stack ".../LIB_AUDIO/livecode/lib_audio.livecodescript"
--   Audio.Open                          -- AUDIO.livecode beside this file, hidden
--   Audio.Refresh tGamesFolder          -- a card per Vibecode3D_Play_<Game>.livecodescript
--   Audio.Select "Canyon", tScriptFile  -- its words, then the filling starts
--   Audio.Play "Explode"                -- silent when not there or not ready: never an error
--   Audio.Music "start"                 -- pause / resume / stop / next / theme
--
-- Sounds live in the Data folder: Sounds/<Category>/ (shared), Sounds/<Game>/<Category>/ (a game's
-- own, wins over the shared one), Sounds/Music/ (shared songs, a game's own Music/ overrides),
-- Sounds/Games/<Game>.txt (the words you chose; without it they are read from the game's script).
-- A words line: name <tab> entry <tab> copies <tab> volume. entry = a file or a folder ending "/",
-- relative to Sounds/. copies = players for that name (empty: one per file, at least 2).

constant kStack = "AUDIO"
constant kPool = "Pool"
constant kGrow = 20          -- players added when the pool is full
constant kTickMS = 20

local sRoot              -- Sounds folder in use (empty: the Data folder's)
local sGame              -- the chosen game
local sQueue             -- what is still to fill: lines of name <tab> entry <tab> copies, or name <tab> file
local sFillLine          -- the last line of sQueue done
local sFillMsg           -- the pending Audio.Fill message
local sNamePlayers       -- [name] player ids, one a line, in turn order
local sNameNext          -- [name] the last one played
local sVolume            -- [name] 0..100
local sFileIndex         -- [file] ids of players holding that file (kept between games)
local sPlayerFile        -- [id] its file
local sUsedNow           -- [id] true when the chosen game uses it
local sFileUse           -- [file] how many of its players the chosen game took so far
local sFailed            -- names whose file did not open, one a line
local sDiskReads         -- files given to players since the last Audio.Select (for tests)
local sSong, sMusicWanted, sMusicPaused, sMusicMsg

-------------------------------------------------------------------------------------------
-- Where the sounds are

command Audio.SetRoot pFolder
   put pFolder into sRoot
end Audio.SetRoot

function Audio.Root
   local tRoot, tErr
   if sRoot is not empty then return sRoot
   try
      put Data.Folder("Sounds") into tRoot      -- LIB_DATA, when in use
   catch tErr
      put empty into tRoot
   end try
   if tRoot is empty then put specialFolderPath("documents") & "/Data/Sounds" into tRoot
   replace "\" with "/" in tRoot
   return tRoot
end Audio.Root

-- An installed copy brings the kit (Vibecode3D Common/Sounds + /Music, Comfy's Player/Sounds + /Music).
-- Each category the Sounds folder does not have yet is copied there once, never over what is there,
-- so the AUDIO window and the sound editor save beside them. Returns how many files were copied.
command Audio.Seed pFrom, pMusicFrom
   local tRoot, tCat, tN, f
   put Audio.Root() into tRoot
   put 0 into tN
   if pFrom is empty or there is not a folder pFrom then return 0
   Audio.SeedMake tRoot
   repeat for each line tCat in Audio.Subfolders(pFrom)
      if tCat is "Games" or there is a folder (tRoot & "/" & tCat) then next repeat
      add Audio.SeedCopy(pFrom & "/" & tCat, tRoot & "/" & tCat) to tN
   end repeat
   if pMusicFrom is not empty and there is a folder pMusicFrom and there is not a folder (tRoot & "/Music") then
      add Audio.SeedCopy(pMusicFrom, tRoot & "/Music") to tN
   end if
   if there is a file (pFrom & "/kit.txt") and there is not a file (tRoot & "/kit.txt") then
      put URL ("binfile:" & pFrom & "/kit.txt") into URL ("binfile:" & tRoot & "/kit.txt")
      add 1 to tN
   end if
   return tN
end Audio.Seed

function Audio.SeedCopy pFrom, pTo
   local tOld, tFiles, f, tN
   put 0 into tN
   Audio.SeedMake pTo
   put the folder into tOld
   set the folder to pFrom
   put files() into tFiles
   set the folder to tOld
   repeat for each line f in tFiles
      if f is empty or char 1 of f is "." then next repeat
      put URL ("binfile:" & pFrom & "/" & f) into URL ("binfile:" & pTo & "/" & f)
      if the result is empty then add 1 to tN
   end repeat
   return tN
end Audio.SeedCopy

-- a folder and the ones above it
command Audio.SeedMake pPath
   local tSoFar, tPart, tErr
   set the itemDel to "/"
   repeat for each item tPart in pPath
      if tSoFar is empty and tPart is empty then
         put "/" into tSoFar
         next repeat
      end if
      if tSoFar is empty or char -1 of tSoFar is "/" then put tSoFar & tPart into tSoFar
      else put tSoFar & "/" & tPart into tSoFar
      if tPart is empty or tSoFar ends with ":" then next repeat
      try
         if there is not a folder tSoFar then create folder tSoFar
      catch tErr
      end try
   end repeat
   set the itemDel to comma
end Audio.SeedMake

-------------------------------------------------------------------------------------------
-- The AUDIO stack

function Audio.StackFile
   local tFile
   put the effective filename of me into tFile
   set the itemDel to "/"
   return item 1 to -2 of tFile & "/AUDIO.livecode"
end Audio.StackFile

function Audio.IsOpen
   return there is a stack kStack and kStack is among the lines of the openStacks
end Audio.IsOpen

-- Opens AUDIO hidden (built in memory when the file is missing). Never waits for sounds.
command Audio.Open pFile
   local tErr
   if Audio.IsOpen() then return empty
   if pFile is empty then put Audio.StackFile() into pFile
   if there is not a stack kStack then
      if there is a file pFile then
         try
            put the name of stack pFile into tErr   -- loads it
         catch tErr
            Audio.Build empty, 100
         end try
      else
         Audio.Build empty, 100
      end if
   end if
   lock messages
   go invisible stack kStack
   unlock messages
   return empty
end Audio.Open

command Audio.Close
   Audio.Music "stop"
   Audio.StopFill
   if there is a stack kStack then
      set the destroyStack of stack kStack to true
      close stack kStack
      -- built in memory (no file): close alone may leave it
      if there is a stack kStack then delete stack kStack
   end if
   put empty into sFileIndex
   put empty into sPlayerFile
   put empty into sNamePlayers
   put empty into sUsedNow
end Audio.Close

-- Makes the stack: card "Kit", background group "Pool" (pCount players), background group
-- "View" (fields Title and Words, text per card). pFile: save it there (empty: memory only).
-- A one-time build; the saved file is what apps open.
command Audio.Build pFile, pCount
   local tDef, i
   if pCount is not an integer then put 100 into pCount
   put the defaultStack into tDef
   if there is a stack kStack then delete stack kStack
   reset the templateStack
   create invisible stack kStack
   set the defaultStack to kStack
   set the title of stack kStack to "AUDIO"
   set the rect of stack kStack to 200, 32, 760, 532
   set the backgroundColor of stack kStack to "24,24,28"
   set the name of card 1 to "Kit"
   reset the templateGroup
   create group kPool     -- card 1 only (not a background: see Audio.Refresh)
   reset the templatePlayer
   repeat with i = 1 to pCount
      create player ("P" & i) in group kPool
      set the rect of player ("P" & i) to -40, -40, -8, -8
      set the visible of player ("P" & i) to false
   end repeat
   reset the templateField
   set the textColor of the templateField to "220,220,220"
   set the backgroundColor of the templateField to "24,24,28"
   set the textFont of the templateField to "Courier New"
   set the textSize of the templateField to 12
   create group "View"
   set the backgroundBehavior of group "View" to true
   create field "Title" in group "View"
   set the rect of field "Title" to 10, 8, 550, 34
   set the sharedText of field "Title" to false
   set the textSize of field "Title" to 16
   set the lockText of field "Title" to true
   create field "Words" in group "View"
   set the rect of field "Words" to 10, 40, 550, 490
   set the sharedText of field "Words" to false
   set the vScrollbar of field "Words" to true
   set the tabStops of field "Words" to 120, 330, 380
   set the lockText of field "Words" to true
   reset the templateField
   put "AUDIO: the sound kit" into field "Title"
   set the destroyStack of stack kStack to true
   set the script of stack kStack to "on closeStackRequest" & cr & "  hide me" & cr & "end closeStackRequest"
   if pFile is not empty then
      set the fileName of stack kStack to pFile
      save stack kStack
   end if
   set the defaultStack to tDef
end Audio.Build

-- How many players the pool has.
function Audio.PoolSize
   if there is not a stack kStack then return 0
   return the number of players of group kPool of card 1 of stack kStack
end Audio.PoolSize

-------------------------------------------------------------------------------------------
-- Cards and words

-- A card per game (text only): the Vibecode3D_Play_<Game>.livecodescript files of pFolder,
-- one folder a line (Comfy Games reads two: games/ and the player's own builds). A name in two
-- folders keeps the first folder's script.
command Audio.Refresh pFolder
   local tFiles, tFile, tGame, tDef, tDir, tWas, tSeen
   if not Audio.IsOpen() then Audio.Open
   put the defaultStack into tDef
   set the defaultStack to kStack
   lock screen
   lock messages
   go card 1 of stack kStack
   put the folder into tWas
   repeat for each line tDir in pFolder
      if tDir is empty or there is not a folder tDir then next repeat
      set the folder to tDir
      put files() into tFiles
      filter tFiles with "Vibecode3D_Play_*.livecodescript"
      repeat for each line tFile in tFiles
         put char 17 to -16 of tFile into tGame
         if tSeen[tGame] is true then next repeat
         put true into tSeen[tGame]
         if there is not a card tGame of stack kStack then
            create card tGame
            -- Only the words view. The pool stays on card 1 alone: on Windows every card that
            -- shows 100 players sets them all up again (0.38 s a card, 23 Nov), so AUDIO never
            -- leaves card 1 while hidden and the game cards are text only.
            if there is a group kPool of card tGame then remove group kPool from card tGame
            if there is not a group "View" of card tGame then place group "View" of card 1 onto card tGame
            put tGame into field "Title" of card tGame
         end if
         set the uScriptFile of card tGame of stack kStack to tDir & "/" & tFile
      end repeat
   end repeat
   set the folder to tWas
   go card 1 of stack kStack
   unlock messages
   unlock screen
   set the defaultStack to tDef
end Audio.Refresh

-- The names a game script plays: every Sound.Play "<name>" in it.
function Audio.ScriptNames pScriptFile
   local tText, tName, tList, tOff
   if there is not a file pScriptFile then return empty
   put textDecode(URL ("binfile:" & pScriptFile), "UTF-8") into tText
   put 0 into tOff
   repeat forever
      put offset("Sound.Play" && quote, tText, tOff) into tName
      if tName is 0 then exit repeat
      add tName + 11 to tOff
      put char tOff + 1 to tOff + 40 of tText into tName
      put char 1 to offset(quote, tName) - 1 of tName into tName
      if tName is not empty and tName is not among the lines of tList then put tName & cr after tList
   end repeat
   return line 1 to -1 of tList
end Audio.ScriptNames

-- A game's words: the saved file (Audio.WordsFile), else made from its script and the kit.
-- Words borrowed from the family or the remix source get the script's other names added (kit).
function Audio.Words pGame, pScriptFile
   local tFile, tWords, tName, tEntry, tHave, tLine
   put Audio.WordsFile(pGame, pScriptFile) into tFile
   if tFile is not empty then
      put textDecode(URL ("binfile:" & tFile), "UTF-8") into tWords
      replace numToChar(13) with empty in tWords
      put line 1 to -1 of tWords into tWords
      if tFile ends with ("/" & pGame & ".txt") then return tWords
      set the itemDel to tab
      repeat for each line tLine in tWords
         put true into tHave[item 1 of tLine]
      end repeat
      set the itemDel to comma
      repeat for each line tName in Audio.ScriptNames(pScriptFile)
         if tHave[tName] is true then next repeat
         put cr & tName & tab & Audio.Entry(pGame, tName) & tab & Audio.DefaultCopies(tName) & tab & 80 after tWords
      end repeat
      return tWords
   end if
   repeat for each line tName in Audio.ScriptNames(pScriptFile)
      put Audio.Entry(pGame, tName) into tEntry
      put tName & tab & tEntry & tab & Audio.DefaultCopies(tName) & tab & 80 & cr after tWords
   end repeat
   put "Music" & tab & Audio.Entry(pGame, "Music") & tab & tab & 60 after tWords
   return tWords
end Audio.Words

-- Which saved words a game uses, the first there of: Games/<Game>.txt; its family
-- Games/<Game without trailing digits>.txt (ComfyPhoton937801948 -> ComfyPhoton.txt); the game
-- it was remixed from, named in its header ("remixed in ComfyUI from Photon Ball" -> PhotonBall.txt).
-- Empty: none, the words come from the script.
function Audio.WordsFile pGame, pScriptFile
   local tDir, tName
   put Audio.Root() & "/Games/" into tDir
   if there is a file (tDir & pGame & ".txt") then return tDir & pGame & ".txt"
   put Audio.Family(pGame) into tName
   if tName is not pGame and there is a file (tDir & tName & ".txt") then return tDir & tName & ".txt"
   put Audio.RemixSource(pScriptFile) into tName
   if tName is not empty and there is a file (tDir & tName & ".txt") then return tDir & tName & ".txt"
   return empty
end Audio.WordsFile

-- The game's name without its trailing digits (a Comfy game's seed); the name itself when none.
function Audio.Family pGame
   local tName
   put pGame into tName
   repeat while tName is not empty and char -1 of tName is in "0123456789"
      delete char -1 of tName
   end repeat
   if tName is empty then return pGame
   return tName
end Audio.Family

-- "remixed in ComfyUI from Photon Ball" in the first lines of the script -> PhotonBall
function Audio.RemixSource pScriptFile
   local tText, tName
   if pScriptFile is empty or there is not a file pScriptFile then return empty
   put line 1 to 12 of textDecode(URL ("binfile:" & pScriptFile), "UTF-8") into tText
   if not matchText(tText, "remixed in ComfyUI from ([A-Za-z0-9 ]+)", tName) then return empty
   replace space with empty in tName
   return tName
end Audio.RemixSource

-- The folder for a name: the game's own first, then the shared kit; empty when neither.
function Audio.Entry pGame, pName
   if there is a folder (Audio.Root() & "/" & pGame & "/" & pName) then return pGame & "/" & pName & "/"
   if there is a folder (Audio.Root() & "/" & pName) then return pName & "/"
   return empty
end Audio.Entry

function Audio.DefaultCopies pName
   if pName is "PlayerLaser" then return 10
   if pName is "Explode" then return 3
   return empty
end Audio.DefaultCopies

-------------------------------------------------------------------------------------------
-- Choosing a game: the words show, the filling starts

command Audio.Select pGame, pScriptFile
   local tWords, tLine, tDef
   if not Audio.IsOpen() then Audio.Open
   Audio.StopFill
   Audio.Music "stop"
   if pScriptFile is empty and there is a card pGame of stack kStack then put the uScriptFile of card pGame of stack kStack into pScriptFile
   put pGame into sGame
   put Audio.Words(pGame, pScriptFile) into tWords
   put empty into sNamePlayers
   put empty into sNameNext
   put empty into sUsedNow
   put empty into sFileUse
   put empty into sFailed
   put empty into sVolume
   put 0 into sDiskReads
   put empty into sQueue
   set the itemDel to tab
   repeat for each line tLine in tWords
      if item 1 of tLine is empty or char 1 of tLine is "#" then next repeat
      if item 4 of tLine is a number then put item 4 of tLine into sVolume[item 1 of tLine]
      else put 80 into sVolume[item 1 of tLine]
      if item 2 of tLine is empty then next repeat
      put item 1 to 3 of tLine & tab & "E" & cr after sQueue   -- E: an entry, still to be made into slots
   end repeat
   set the itemDel to comma
   put 0 into sFillLine
   put the defaultStack into tDef
   -- the words go on the game's card without going there (see Audio.Refresh), and on card 1
   if there is a card pGame of stack kStack then put tWords into field "Words" of card pGame of stack kStack
   put tWords into field "Words" of card 1 of stack kStack
   put pGame into field "Title" of card 1 of stack kStack
   set the defaultStack to tDef
   Audio.Fill
end Audio.Select

command Audio.StopFill
   if sFillMsg is not empty then cancel sFillMsg
   put empty into sFillMsg
end Audio.StopFill

-- One step: everything that needs no disk, then at most ONE disk job (a folder listed or a
-- file given to a player), then again in kTickMS. Stops when the queue is done.
command Audio.Fill
   local tLine, tName, tEntry, tCopies, tFiles, tSlots, n, c, tFile, tId, tFull, tOld
   put empty into sFillMsg
   if not Audio.IsOpen() then exit Audio.Fill
   set the itemDel to tab
   repeat while sFillLine < the number of lines of sQueue
      put line sFillLine + 1 of sQueue into tLine
      put item 1 of tLine into tName
      put item 2 of tLine into tEntry
      if item 4 of tLine is "E" then
         -- an entry: a folder becomes its files (one listing = the disk job), copies -> slots
         put item 3 of tLine into tCopies
         if char -1 of tEntry is "/" then
            put Audio.FolderFiles(Audio.Root() & "/" & char 1 to -2 of tEntry) into tFiles
         else
            put tEntry into tFiles
         end if
         put empty into tSlots
         if tFiles is not empty then
            put the number of lines of tFiles into n
            if tCopies is not an integer then put max(n, 2) into tCopies
            if tName is "Music" then put n into tCopies
            repeat with c = 1 to tCopies
               put line ((c - 1) mod n) + 1 of tFiles into tFile
               if char -1 of tEntry is "/" then put tEntry & tFile into tFile
               put tName & tab & tFile & cr after tSlots
            end repeat
         else
            Audio.MarkFailed tName
         end if
         if tSlots is not empty then delete char -1 of tSlots
         put tSlots into line sFillLine + 1 of sQueue
         if tSlots is empty then add 1 to sFillLine
         if char -1 of tEntry is "/" then exit repeat   -- that listing was this tick's disk job
         next repeat
      end if
      -- a slot: name <tab> file
      add 1 to sFillLine
      put tEntry into tFile
      add 1 to sFileUse[tFile]
      put line sFileUse[tFile] of sFileIndex[tFile] into tId
      if tId is not empty then
         Audio.Give tName, tId      -- already holds that file: no disk
         next repeat
      end if
      put Audio.FreePlayer() into tId
      put sPlayerFile[tId] into tOld
      if tOld is not empty then Audio.Unindex tId, tOld
      put Audio.Root() & "/" & tFile into tFull
      set the fileName of player id tId of stack kStack to tFull
      add 1 to sDiskReads
      if Audio.Opened(tId, tFull) then
         put tFile into sPlayerFile[tId]
         put tId & cr after sFileIndex[tFile]
         Audio.Give tName, tId
      else
         set the fileName of player id tId of stack kStack to empty
         put empty into sPlayerFile[tId]
         Audio.MarkFailed tName
      end if
      exit repeat     -- one file a tick
   end repeat
   set the itemDel to comma
   if sFillLine < the number of lines of sQueue then
      send "Audio.Fill" to me in kTickMS milliseconds
      put the result into sFillMsg
   else
      Audio.ShowState
   end if
end Audio.Fill

-- Did the file open? Windows/Mac: its duration is there at once (step 1, 23 Nov). Elsewhere
-- (Linux, no window) players have no media: the file being there counts.
function Audio.Opened pId, pFull
   if the platform is among the items of "Win32,MacOS" then return the duration of player id pId of stack kStack > 0
   return there is a file pFull
end Audio.Opened

function Audio.FolderFiles pFolder
   local tOld, tFiles, tOut, f
   if there is not a folder pFolder then return empty
   put the folder into tOld
   set the folder to pFolder
   put files() into tFiles
   set the folder to tOld
   set the itemDel to "."
   repeat for each line f in tFiles
      if item -1 of f is among the items of "wav.mp3.aif.aiff.m4a.ogg" then put f & cr after tOut
   end repeat
   set the itemDel to comma
   sort tOut
   return line 1 to -1 of tOut
end Audio.FolderFiles

command Audio.Give pName, pId
   put pId & cr after sNamePlayers[pName]
   put true into sUsedNow[pId]
   if pName is "Music" and sMusicWanted is true and sSong is empty then Audio.Music "start"
end Audio.Give

command Audio.MarkFailed pName
   if pName is not among the lines of sFailed then put pName & cr after sFailed
end Audio.MarkFailed

command Audio.Unindex pId, pFile
   local tList, tLine
   repeat for each line tLine in sFileIndex[pFile]
      if tLine is not pId then put tLine & cr after tList
   end repeat
   put tList into sFileIndex[pFile]
end Audio.Unindex

-- A player the chosen game does not use: an empty one first; the pool grows when all are taken.
function Audio.FreePlayer
   local i, tId, tSpare, tCount
   put Audio.PoolSize() into tCount
   repeat with i = 1 to tCount
      put the short id of player i of group kPool of card 1 of stack kStack into tId
      if sUsedNow[tId] is true then next repeat
      if sPlayerFile[tId] is empty then return tId
      if tSpare is empty then put tId into tSpare
   end repeat
   if tSpare is not empty then return tSpare
   Audio.Grow kGrow
   return the short id of player (tCount + 1) of group kPool of card 1 of stack kStack
end Audio.FreePlayer

command Audio.Grow pCount
   local tDef, i, n
   put the defaultStack into tDef
   set the defaultStack to kStack
   put Audio.PoolSize() into n
   reset the templatePlayer
   repeat with i = n + 1 to n + pCount
      create player ("P" & i) in group kPool of card 1 of stack kStack
      set the rect of player ("P" & i) of card 1 of stack kStack to -40, -40, -8, -8
      set the visible of player ("P" & i) of card 1 of stack kStack to false
   end repeat
   set the defaultStack to tDef
end Audio.Grow

command Audio.ShowState
   local tDef
   if sGame is empty or there is not a card sGame of stack kStack then exit Audio.ShowState
   put the defaultStack into tDef
   put sGame && "|" && Audio.Progress() into field "Title" of card sGame of stack kStack
   if sFailed is not empty then put " | silent:" && line 1 to -1 of sFailed after field "Title" of card sGame of stack kStack
   set the defaultStack to tDef
   Audio.UIStatus
end Audio.ShowState

function Audio.Done
   return sQueue is not empty and sFillLine >= the number of lines of sQueue
end Audio.Done

-- "12/40": queue lines done / all (a folder counts as one until it is listed)
function Audio.Progress
   return sFillLine & "/" & the number of lines of sQueue
end Audio.Progress

function Audio.Failed
   return line 1 to -1 of sFailed
end Audio.Failed

function Audio.DiskReads
   return sDiskReads
end Audio.DiskReads

function Audio.Names
   local tList
   repeat for each key k in sNamePlayers
      put k & cr after tList
   end repeat
   sort tList
   return line 1 to -1 of tList
end Audio.Names

function Audio.Players pName
   return line 1 to -1 of sNamePlayers[pName]
end Audio.Players

-------------------------------------------------------------------------------------------
-- Playing

-- The next player of that name, from the start. Silent when none (yet): never an error.
command Audio.Play pName
   local tCount, tId
   if sNamePlayers[pName] is empty then exit Audio.Play
   if there is not a stack kStack then exit Audio.Play
   put the number of lines of sNamePlayers[pName] into tCount
   add 1 to sNameNext[pName]
   if sNameNext[pName] > tCount then put 1 into sNameNext[pName]
   put line sNameNext[pName] of sNamePlayers[pName] into tId
   if there is not a player id tId of stack kStack then exit Audio.Play
   set the playLoudness of player id tId of stack kStack to sVolume[pName]
   set the currentTime of player id tId of stack kStack to 0
   start player id tId of stack kStack
end Audio.Play

-- start (a song, or the first one ready), pause, resume, stop, next, theme
command Audio.Music pWhat
   local tList, tId, tFile
   switch pWhat
      case "start"
      case "next"
      case "theme"
         Audio.Music "stop"
         put true into sMusicWanted
         put empty into tList
         repeat for each line tId in sNamePlayers["Music"]
            put sPlayerFile[tId] into tFile
            if (tFile contains "theme") is (pWhat is "theme") then put tId & cr after tList
         end repeat
         if tList is empty then exit Audio.Music     -- not ready: Audio.Give starts it
         put line random(the number of lines of tList) of tList into sSong
         put false into sMusicPaused
         set the playLoudness of player id sSong of stack kStack to sVolume["Music"]
         set the currentTime of player id sSong of stack kStack to 0
         start player id sSong of stack kStack
         Audio.MusicCheck
         break
      case "pause"
         put true into sMusicPaused
         if sSong is not empty and there is a player id sSong of stack kStack then stop player id sSong of stack kStack
         break
      case "resume"
         put false into sMusicPaused
         if sSong is empty then
            Audio.Music "start"
         else if there is a player id sSong of stack kStack then
            start player id sSong of stack kStack
            Audio.MusicCheck
         end if
         break
      case "stop"
         put false into sMusicWanted
         if sMusicMsg is not empty then cancel sMusicMsg
         put empty into sMusicMsg
         if sSong is not empty and there is a stack kStack and there is a player id sSong of stack kStack then stop player id sSong of stack kStack
         put empty into sSong
         break
   end switch
end Audio.Music

-- Once a second while a song plays: when it has ended, the next one.
command Audio.MusicCheck
   put empty into sMusicMsg
   if sSong is empty or sMusicPaused is true then exit Audio.MusicCheck
   if there is not a stack kStack or there is not a player id sSong of stack kStack then exit Audio.MusicCheck
   if the paused of player id sSong of stack kStack and the platform is among the items of "Win32,MacOS" then
      Audio.Music "next"
      exit Audio.MusicCheck
   end if
   send "Audio.MusicCheck" to me in 1000 milliseconds
   put the result into sMusicMsg
end Audio.MusicCheck

function Audio.Song
   if sSong is empty then return empty
   return sPlayerFile[sSong]
end Audio.Song

-------------------------------------------------------------------------------------------
-- Step 5 (24 Nov 2026): the AUDIO window, for choosing and appointing sounds. Built in code on
-- card 1 (the pool's card: AUDIO never goes to another card), so the saved AUDIO.livecode needs
-- no new save.
--   left:  the chosen game's words (click = hear it as the game plays it; Music: start/stop)
--   right: the kit, Sounds/<Category>/ and its files, a game's own Sounds/<Game>/<Category>/ first
--          (click = hear that file, click again = stop; double-click = appoint)
--   Appoint: the selected word gets the selected kit line (a folder: its files take turns)
--   Vol - / Vol +: 10 steps, heard at once. Save: Sounds/Games/<Game>.txt, then the fill runs
--   again (files already in players are not read again). Revert: back to the saved words.

local sKitEntries   -- [line number of field "Kit"] its entry: Category/ or Category/file.wav
local sChanged      -- [name] true when its sound was appointed and not saved yet
local sDirty        -- true when the words were changed and not saved
local sPreview      -- the file in player "Preview" (Sounds-relative)
local sEditWord     -- the word chosen when Edit... was clicked: a sound saved in SOUND EDIT goes to it

command Audio.Show pGame
   if not Audio.IsOpen() then Audio.Open
   Audio.UIBuild
   if pGame is not empty and pGame is not sGame then
      put false into sDirty
      put empty into sChanged
      Audio.Select pGame
   end if
   Audio.UIKit
   Audio.UIStatus
   set the title of stack kStack to "FOR OWNER | AUDIO: the sounds of a game (click = hear, double-click = appoint)"
   show stack kStack
end Audio.Show

command Audio.Hide
   Audio.PreviewStop
   if there is a stack kStack then hide stack kStack
end Audio.Hide

-- The window's controls, once. Template colours first (owner's rule), dark like the rest.
command Audio.UIBuild
   local tDef, tC
   if there is not a stack kStack then exit Audio.UIBuild
   if there is a group "Chooser" of card 1 of stack kStack then exit Audio.UIBuild
   put the defaultStack into tDef
   set the defaultStack to kStack
   lock screen
   lock messages
   put "on mouseUp" & cr & "  #" & cr & "end mouseUp" into tC
   set the rect of stack kStack to 200, 32, 1100, 632
   set the rect of field "Title" of card 1 to 10, 8, 890, 34
   set the rect of field "Words" of card 1 to 10, 64, 450, 520
   set the tabStops of field "Words" of card 1 to 110, 340, 390
   set the listBehavior of field "Words" of card 1 to true
   set the script of field "Words" of card 1 to replaceText(tC, "#", "Audio.UIWord")
   reset the templateField
   set the textColor of the templateField to "220,220,220"
   set the backgroundColor of the templateField to "24,24,28"
   set the textFont of the templateField to "Courier New"
   set the textSize of the templateField to 12
   set the lockText of the templateField to true
   reset the templateButton
   set the backgroundColor of the templateButton to "60,60,72"
   set the textColor of the templateButton to "230,230,230"
   set the textSize of the templateButton to 12
   reset the templateGroup
   reset the templatePlayer
   create group "Chooser"
   set the backgroundBehavior of group "Chooser" to false
   create field "WordsHead" in group "Chooser"
   set the rect of field "WordsHead" of card 1 to 10, 40, 450, 62
   put "Words: name, sound, copies, volume (click = hear)" into field "WordsHead" of card 1
   create field "KitHead" in group "Chooser"
   set the rect of field "KitHead" of card 1 to 460, 40, 890, 62
   put "The kit (click = hear, again = stop; double-click = appoint)" into field "KitHead" of card 1
   create field "Kit" in group "Chooser"
   set the rect of field "Kit" of card 1 to 460, 64, 890, 520
   set the listBehavior of field "Kit" of card 1 to true
   set the vScrollbar of field "Kit" of card 1 to true
   set the script of field "Kit" of card 1 to replaceText(tC, "#", "Audio.UIKitClick") & cr & "on mouseDoubleUp" & cr & "  Audio.UIAppoint" & cr & "end mouseDoubleUp"
   create field "Status" in group "Chooser"
   set the rect of field "Status" of card 1 to 10, 566, 890, 592
   create player "Preview" in group "Chooser"
   set the rect of player "Preview" of card 1 to -40, -40, -8, -8
   set the visible of player "Preview" of card 1 to false
   Audio.UIButton "Game...", "10,530,110,556", "Audio.UIGameMenu", tC
   Audio.UIButton "Hear", "120,530,190,556", "Audio.UIWord", tC
   Audio.UIButton "Vol -", "200,530,260,556", "Audio.UIVolume -10", tC
   Audio.UIButton "Vol +", "270,530,330,556", "Audio.UIVolume 10", tC
   Audio.UIButton "<- Appoint", "460,530,570,556", "Audio.UIAppoint", tC
   Audio.UIButton "Edit...", "580,530,680,556", "Audio.UIEdit", tC
   Audio.UIButton "Revert", "690,530,780,556", "Audio.UIRevert", tC
   Audio.UIButton "Save", "790,530,890,556", "Audio.UISave", tC
   Audio.UIButton "Close", "790,600,890,626", "Audio.Hide", tC
   create button "GameList" in group "Chooser"
   set the style of button "GameList" of card 1 to "menu"
   set the menuMode of button "GameList" of card 1 to "popup"
   set the visible of button "GameList" of card 1 to false
   set the script of button "GameList" of card 1 to "on menuPick pWhich" & cr & "  Audio.UIPickGame pWhich" & cr & "end menuPick"
   reset the templateField
   reset the templateButton
   unlock messages
   unlock screen
   set the defaultStack to tDef
end Audio.UIBuild

command Audio.UIButton pName, pRect, pCall, pScript
   create button pName in group "Chooser"
   set the rect of button pName of card 1 to pRect
   set the script of button pName of card 1 to replaceText(pScript, "#", pCall)
end Audio.UIButton

-- The kit list: the chosen game's own categories first, then the shared ones (not Games, not
-- another game's folder). One folder listing each: no players, no sound files opened.
command Audio.UIKit
   local tRoot, tText, n, tCat, tFolders
   if there is not a field "Kit" of card 1 of stack kStack then exit Audio.UIKit
   put Audio.Root() into tRoot
   put empty into sKitEntries
   put 0 into n
   put empty into tText
   if sGame is not empty and there is a folder (tRoot & "/" & sGame) then
      repeat for each line tCat in Audio.Subfolders(tRoot & "/" & sGame)
         Audio.UIKitAdd tRoot, sGame & "/" & tCat, tText, n
      end repeat
   end if
   repeat for each line tCat in Audio.Subfolders(tRoot)
      if tCat is "Games" or there is a card tCat of stack kStack then next repeat
      Audio.UIKitAdd tRoot, tCat, tText, n
   end repeat
   if tText is empty then put "(no sounds in" && tRoot & ")" & cr into tText
   put line 1 to -1 of tText into field "Kit" of card 1 of stack kStack
   repeat for each key n in sKitEntries
      if char -1 of sKitEntries[n] is "/" then set the textStyle of line n of field "Kit" of card 1 of stack kStack to "bold"
   end repeat
end Audio.UIKit

command Audio.UIKitAdd pRoot, pCat, @rText, @rN
   local tFiles, f
   put Audio.FolderFiles(pRoot & "/" & pCat) into tFiles
   if tFiles is empty then exit Audio.UIKitAdd
   add 1 to rN
   put pCat & "/  (" & the number of lines of tFiles & ")" & cr after rText
   put pCat & "/" into sKitEntries[rN]
   repeat for each line f in tFiles
      add 1 to rN
      put "    " & f & cr after rText
      put pCat & "/" & f into sKitEntries[rN]
   end repeat
end Audio.UIKitAdd

function Audio.Subfolders pFolder
   local tOld, tList, tOut, f
   if there is not a folder pFolder then return empty
   put the folder into tOld
   set the folder to pFolder
   put folders() into tList
   set the folder to tOld
   repeat for each line f in tList
      if f is "." or f is ".." or f is empty then next repeat
      put f & cr after tOut
   end repeat
   sort tOut
   return line 1 to -1 of tOut
end Audio.Subfolders

-- The entry of a kit line (for tests and the window)
function Audio.KitEntry pLine
   return sKitEntries[pLine]
end Audio.KitEntry

function Audio.KitLine pEntry
   repeat for each key n in sKitEntries
      if sKitEntries[n] is pEntry then return n
   end repeat
   return 0
end Audio.KitLine

function Audio.UIWordLine
   return the hilitedLine of field "Words" of card 1 of stack kStack
end Audio.UIWordLine

-- Click on a word: hear it. Appointed and not saved yet: the new sound, through Preview.
command Audio.UIWord
   local tLine, tName, tEntry
   put Audio.UIWordLine() into tLine
   if tLine is empty then
      Audio.UIStatus "choose a word on the left"
      exit Audio.UIWord
   end if
   set the itemDel to tab
   put item 1 of line tLine of field "Words" of card 1 of stack kStack into tName
   put item 2 of line tLine of field "Words" of card 1 of stack kStack into tEntry
   set the itemDel to comma
   if sChanged[tName] is true then
      Audio.Preview tEntry
      Audio.UIStatus tName & ": (not saved)" && tEntry
   else if tName is "Music" then
      if Audio.Song() is empty then Audio.Music "start"
      else Audio.Music "stop"
      Audio.UIStatus "Music:" && Audio.Song()
   else
      Audio.Play tName
      if tEntry is empty then Audio.UIStatus tName & ": no sound yet, choose one on the right"
      else Audio.UIStatus tName & ":" && tEntry
   end if
end Audio.UIWord

command Audio.UIKitClick
   local tLine
   put the hilitedLine of field "Kit" of card 1 of stack kStack into tLine
   if tLine is empty or sKitEntries[tLine] is empty then exit Audio.UIKitClick
   Audio.Preview sKitEntries[tLine]
   if sPreview is empty then Audio.UIStatus "stopped"
   else Audio.UIStatus "hear:" && sPreview
end Audio.UIKitClick

-- Plays one file in player "Preview" (a folder: its first file). The same file again: stop.
command Audio.Preview pEntry
   local tFile, tFull, tFiles
   if there is not a player "Preview" of card 1 of stack kStack then exit Audio.Preview
   put pEntry into tFile
   if char -1 of tFile is "/" then
      put Audio.FolderFiles(Audio.Root() & "/" & char 1 to -2 of tFile) into tFiles
      if tFiles is empty then exit Audio.Preview
      put tFile & line 1 of tFiles into tFile
   end if
   if tFile is sPreview and not the paused of player "Preview" of card 1 of stack kStack then
      Audio.PreviewStop
      exit Audio.Preview
   end if
   Audio.PreviewStop
   put Audio.Root() & "/" & tFile into tFull
   set the fileName of player "Preview" of card 1 of stack kStack to tFull
   put tFile into sPreview
   set the playLoudness of player "Preview" of card 1 of stack kStack to 80
   set the currentTime of player "Preview" of card 1 of stack kStack to 0
   start player "Preview" of card 1 of stack kStack
end Audio.Preview

command Audio.PreviewStop
   if there is a stack kStack and there is a player "Preview" of card 1 of stack kStack then stop player "Preview" of card 1 of stack kStack
   put empty into sPreview
end Audio.PreviewStop

-- Edit... : the chosen kit sound (else the chosen word's) in the SOUND EDIT window
-- (lib_sound_edit beside this file, LIB_SFX's numbers). Never an error: the status says why not.
command Audio.UIEdit
   local k, w, tEntry, tLib, tErr, tWhy
   put the hilitedLine of field "Kit" of card 1 of stack kStack into k
   if k is not empty then put sKitEntries[k] into tEntry
   if tEntry is empty then
      put Audio.UIWordLine() into w
      if w is not empty then
         set the itemDel to tab
         put item 2 of line w of field "Words" of card 1 of stack kStack into tEntry
         set the itemDel to comma
      end if
   end if
   if tEntry is empty then
      Audio.UIStatus "choose a sound to edit (right), or a word that has one (left)"
      exit Audio.UIEdit
   end if
   Audio.PreviewStop
   put empty into sEditWord
   put Audio.UIWordLine() into w
   if w is not empty then
      set the itemDel to tab
      put item 1 of line w of field "Words" of card 1 of stack kStack into sEditWord
      set the itemDel to comma
   end if
   put the effective filename of me into tLib
   set the itemDel to "/"
   put item 1 to -2 of tLib & "/lib_sound_edit.livecodescript" into tLib
   set the itemDel to comma
   try
      if "lib_sound_edit" is not among the lines of the stacksInUse then start using stack tLib
      SEdit.Open tEntry, Audio.Root(), sGame
      put the result into tWhy
   catch tErr
      put line 1 of tErr into tWhy
   end try
   if tWhy is empty then Audio.UIStatus "editing" && tEntry
   else Audio.UIStatus "no sound editor:" && tWhy
end Audio.UIEdit

-- SOUND EDIT saved pEntry (Sounds-relative): the kit list shows it, chosen; the word Edit... was
-- opened from gets it, as an appoint does (then Save here keeps it).
command Audio.EditSaved pEntry
   local w, tLine, k
   if there is not a field "Words" of card 1 of stack kStack then exit Audio.EditSaved
   Audio.UIKit
   put Audio.KitLine(pEntry) into k
   if k > 0 then set the hilitedLine of field "Kit" of card 1 of stack kStack to k
   if sEditWord is empty then
      Audio.UIStatus "new sound" && pEntry & ": choose a word and Appoint it"
      exit Audio.EditSaved
   end if
   put 0 into w
   put 0 into k
   repeat for each line tLine in field "Words" of card 1 of stack kStack
      add 1 to k
      if tLine begins with (sEditWord & tab) then
         put k into w
         exit repeat
      end if
   end repeat
   if w is 0 then exit Audio.EditSaved
   set the itemDel to tab
   put line w of field "Words" of card 1 of stack kStack into tLine
   put pEntry into item 2 of tLine
   put tLine into line w of field "Words" of card 1 of stack kStack
   set the itemDel to comma
   put true into sChanged[sEditWord]
   put true into sDirty
   set the hilitedLine of field "Words" of card 1 of stack kStack to w
   Audio.UIStatus sEditWord && "now" && pEntry & ": Save to keep it"
end Audio.EditSaved

-- The selected word gets the selected kit line.
command Audio.UIAppoint
   local w, k, tLine, tEntry
   put Audio.UIWordLine() into w
   put the hilitedLine of field "Kit" of card 1 of stack kStack into k
   if w is empty then
      Audio.UIStatus "choose a word on the left first"
      exit Audio.UIAppoint
   end if
   if k is empty or sKitEntries[k] is empty then
      Audio.UIStatus "choose a sound on the right"
      exit Audio.UIAppoint
   end if
   put sKitEntries[k] into tEntry
   set the itemDel to tab
   put line w of field "Words" of card 1 of stack kStack into tLine
   put tEntry into item 2 of tLine
   put tLine into line w of field "Words" of card 1 of stack kStack
   put true into sChanged[item 1 of tLine]
   set the itemDel to comma
   set the hilitedLine of field "Words" of card 1 of stack kStack to w
   put true into sDirty
   Audio.UIStatus "appointed:" && tEntry
end Audio.UIAppoint

command Audio.UIVolume pDelta
   local w, tLine, v, tName
   put Audio.UIWordLine() into w
   if w is empty then
      Audio.UIStatus "choose a word on the left first"
      exit Audio.UIVolume
   end if
   set the itemDel to tab
   put line w of field "Words" of card 1 of stack kStack into tLine
   put item 4 of tLine into v
   if v is not a number then put 80 into v
   put max(0, min(100, v + pDelta)) into v
   put v into item 4 of tLine
   put item 1 of tLine into tName
   put tLine into line w of field "Words" of card 1 of stack kStack
   set the itemDel to comma
   put v into sVolume[tName]
   set the hilitedLine of field "Words" of card 1 of stack kStack to w
   put true into sDirty
   Audio.UIWord
   Audio.UIStatus tName && "volume" && v
end Audio.UIVolume

-- Writes Sounds/Games/<Game>.txt and fills again (music goes on if it was playing).
-- A game with a family (Comfy: ComfyPhoton937801948) asks: this game, or the whole family
-- (Games/ComfyPhoton.txt, which every ComfyPhoton without its own file then uses).
-- pFor: "game" or "family" answers that without asking (tests).
command Audio.UISave pFor
   local tFolder, tFile, tMusic, tWords, tName, tFamily
   if sGame is empty then exit Audio.UISave
   put sGame into tName
   put Audio.Family(sGame) into tFamily
   if tFamily is not sGame and pFor is empty then
      answer "Save these sounds for" && sGame && "alone, or for every" && tFamily && "game?" with "Cancel" or "Whole family" or "This game"
      if it is "Cancel" then exit Audio.UISave
      if it is "Whole family" then put "family" into pFor
   end if
   if pFor is "family" and tFamily is not sGame then put tFamily into tName
   put Audio.Root() & "/Games" into tFolder
   if there is not a folder tFolder then create folder tFolder
   put tFolder & "/" & tName & ".txt" into tFile
   put field "Words" of card 1 of stack kStack into tWords
   put textEncode(line 1 to -1 of tWords & cr, "UTF-8") into URL ("binfile:" & tFile)
   if the result is not empty then
      Audio.UIStatus "NOT saved:" && the result
      exit Audio.UISave
   end if
   put (Audio.Song() is not empty) into tMusic
   put false into sDirty
   put empty into sChanged
   Audio.PreviewStop
   Audio.Select sGame
   if tMusic then Audio.Music "start"
   Audio.UIStatus "saved" && tFile
end Audio.UISave

command Audio.UIRevert
   if sGame is empty then exit Audio.UIRevert
   put false into sDirty
   put empty into sChanged
   Audio.PreviewStop
   Audio.Select sGame
   Audio.UIStatus "back to the saved words"
end Audio.UIRevert

-- Game... : a popup of the game cards (from mouseUp: owner's rule)
command Audio.UIGameMenu
   local tList, i
   repeat with i = 2 to the number of cards of stack kStack
      put the short name of card i of stack kStack & cr after tList
   end repeat
   sort tList
   put line 1 to -1 of tList into button "GameList" of card 1 of stack kStack
   popup button "GameList" of card 1 of stack kStack
end Audio.UIGameMenu

command Audio.UIPickGame pGame
   if sDirty is true then
      Audio.UIStatus "Save or Revert" && sGame && "first"
      exit Audio.UIPickGame
   end if
   Audio.PreviewStop
   Audio.Select pGame
   Audio.UIKit
   Audio.UIStatus
end Audio.UIPickGame

function Audio.UIDirty
   return sDirty is true
end Audio.UIDirty

command Audio.UIStatus pMsg
   local t
   if there is not a stack kStack or there is not a field "Status" of card 1 of stack kStack then exit Audio.UIStatus
   put sGame into t
   if t is empty then put "(no game chosen: Game...)" into t
   if sDirty is true then put " (changed, not saved)" after t
   if sQueue is not empty then put " | filled" && Audio.Progress() after t
   if sFailed is not empty then put " | silent:" && replaceText(line 1 to -1 of sFailed, return, ", ") after t
   if pMsg is not empty then put " | " & pMsg after t
   put t into field "Status" of card 1 of stack kStack
end Audio.UIStatus
