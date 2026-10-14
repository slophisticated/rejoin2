-- Rejoin loader: one file to install, update and start rejoin.
--
--   curl -sL https://raw.githubusercontent.com/slophisticated/rejoin2/main/rejoin.lua -o /sdcard/Download/rejoin.lua
--   lua /sdcard/Download/rejoin.lua
--
-- First run: installs rejoin to ~/rejoin (install.sh). Every run after that: updates
-- from GitHub (update.sh, config kept) and opens the menu. Extra arguments are passed
-- to main.lua, e.g. `lua /sdcard/Download/rejoin.lua --no-update`.

local REPO_RAW = "https://raw.githubusercontent.com/slophisticated/rejoin2/main"
local HOME = os.getenv("HOME") or "/data/data/com.termux/files/home"
local DIR = os.getenv("REJOIN_DIR") or (HOME .. "/rejoin")

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function run(cmd)
    local ok, how, code = os.execute(cmd)
    if type(ok) == "number" then return ok == 0 end -- Lua 5.1
    return ok == true and how == "exit" and code == 0
end

local function exists(path)
    return run("[ -e " .. q(path) .. " ]")
end

if not (os.getenv("PREFIX") or ""):find("com.termux", 1, true) then
    print("Jalankan loader ini di dalam Termux.")
    os.exit(1)
end

local update, pass = true, {}
for _, a in ipairs(arg or {}) do
    if a == "--no-update" then update = false else pass[#pass + 1] = q(a) end
end

if not exists(DIR .. "/main.lua") then
    print("Rejoin belum terpasang, install dulu (bisa beberapa menit)...")
    if not run("curl -sL " .. REPO_RAW .. "/install.sh | sh") or not exists(DIR .. "/main.lua") then
        print("Install gagal. Lihat pesan di atas, lalu jalankan loader ini lagi.")
        os.exit(1)
    end
elseif update then
    print("Cek update rejoin...")
    run("sh " .. q(DIR .. "/update.sh") .. " </dev/null")
end

-- Hand over to the supervisor (same as `cd ~/rejoin && lua main.lua`).
local ok = run("cd " .. q(DIR) .. " && exec sh ./run.sh " .. table.concat(pass, " "))
os.exit(ok and 0 or 1)
