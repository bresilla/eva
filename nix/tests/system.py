def system(password):
    login(password)
    machine.wait_until_succeeds(session("morf ipc call windows | grep -q '\"ok\":true'"), timeout=240)
    print("HYPRLAND", hyprctl("version"))
