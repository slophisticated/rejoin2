local Control = require("managers.launch_control")
local CLI = {}

function CLI.run()
    local state = Control.read()
    if not state then print("Tidak ada clone yang sedang ditunggu."); return end
    print("\nAntrean: " .. tostring(state.name) .. " (" .. tostring(state.package) .. ")")
    print(tostring(state.reason))
    print("1) Lewati clone ini saja\n2) Batalkan sisa antrean (monitor tetap jalan)\n0) Kembali / tetap tunggu")
    io.write("Pilih: "); io.flush()
    local choice = io.read()
    local action = choice == "1" and "skip" or choice == "2" and "cancel"
    if action then
        local current = Control.read()
        if not current or current.token ~= state.token then
            print("Clone yang ditunggu sudah berubah. Buka menu ini lagi.")
            return
        end
        local ok, err = Control.request(action, state.token)
        print(ok and "Perintah dikirim ke monitor." or tostring(err))
    end
end

return CLI
