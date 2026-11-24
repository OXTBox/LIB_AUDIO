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

-- A card per game (text only): the Vibecode3D_Play_<Game>.livecodescript files of pFolder.
command Audio.Refresh pFolder
   local tFiles, tFile, tGame, tDef
   if not Audio.IsOpen() then Audio.Open
   put the defaultStack into tDef
   set the defaultStack to kStack
   put the folder into tFile
   set the folder to pFolder
   put files() into tFiles
   set the folder to tFile
   filter tFiles with "Vibecode3D_Play_*.livecodescript"
   lock screen
   lock messages
   go card 1 of stack kStack
   repeat for each line tFile in tFiles
      put char 17 to -16 of tFile into tGame
      if there is not a card tGame of stack kStack then
         create card tGame
         -- Only the words view. The pool stays on card 1 alone: on Windows every card that
         -- shows 100 players sets them all up again (0.38 s a card, 23 Nov), so AUDIO never
         -- leaves card 1 while hidden and the game cards are text only.
         if there is a group kPool of card tGame then remove group kPool from card tGame
         if there is not a group "View" of card tGame then place group "View" of card 1 onto card tGame
         put tGame into field "Title" of card tGame
      end if
      set the uScriptFile of card tGame of stack kStack to pFolder & "/" & tFile
   end repeat
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

-- A game's words: the saved file Sounds/Games/<Game>.txt, else made from its script and the kit.
function Audio.Words pGame, pScriptFile
   local tFile, tWords, tName, tEntry
   put Audio.Root() & "/Games/" & pGame & ".txt" into tFile
   if there is a file tFile then
      put textDecode(URL ("binfile:" & tFile), "UTF-8") into tWords
      replace numToChar(13) with empty in tWords
      return line 1 to -1 of tWords
   end if
   repeat for each line tName in Audio.ScriptNames(pScriptFile)
      put Audio.Entry(pGame, tName) into tEntry
      put tName & tab & tEntry & tab & Audio.DefaultCopies(tName) & tab & 80 & cr after tWords
   end repeat
   put "Music" & tab & Audio.Entry(pGame, "Music") & tab & tab & 60 after tWords
   return tWords
end Audio.Words

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

-- The AUDIO window, for choosing and appointing sounds (step 5 makes it more than a list).
command Audio.Show
   if not Audio.IsOpen() then Audio.Open
   show stack kStack
end Audio.Show
