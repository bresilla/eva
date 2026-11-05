-- The right panel's Network and Bluetooth pages: what the bar's popouts
-- had, given the panel's height. Network: Wi-Fi on or off, the networks
-- (the one in use first, then by strength; a click joins one) and a
-- rescan. Bluetooth: on or off, discovery, the devices (connected, then
-- paired, then by name; a click connects or disconnects) and the settings
-- program. The injected model owns service reads and actions; this builder
-- preserves the original cards, row positions and footer buttons.

local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")

local M = {}

local MAX_ROWS = 64

--- Up to `max` (MAX_ROWS) rows, each shown while `count()` reaches it; one
--- saying `none` while there are none.
local function list(w, prefix, count, row, none, max)
  local inner = P.inner(w)
  local col = { width = inner, gap = P.ROW_GAP }
  local slots = {}
  for i = 1, max or MAX_ROWS do
    slots[i] = ui.Item { id = prefix .. i, width = inner, height = P.ROW_H,
      visible = function() return i <= count() end, row(i, inner) }
    col[#col + 1] = slots[i]
  end
  col[#col + 1] = P.row { width = inner, icon = "info", on = function() return false end, title = none,
    visible = function() return count() == 0 end }
  local node = ui.Column(col)
  -- Rows a scan adds come in as new rows do (`theme.motion.rows`), top first.
  local had = count()
  morf.effect("eva.list." .. prefix, function()
    local now = math.min(count(), #slots)
    if now > had and theme.motion.rows then
      local coming = {}
      for i = had + 1, now do coming[#coming + 1] = slots[i] end
      theme.motion.rows(coming)
    end
    had = now
  end, { owner = node })
  return node
end

--- The one action under a list, the card's width.
local function action(w, spec)
  spec.width = P.inner(w)
  return P.buttons { width = P.inner(w), spec }
end

--- What a page without its service says, in place of its lists.
local function missing(w, icon, title, text, available)
  local node = P.empty { width = w, icon = icon, title = title, text = text }
  node.visible = function() return not available() end
  return node
end

--- What the last action said ("a password is needed"), under the list.
local function status(id, model, w)
  local function said() return (model.message:get() or "") ~= "" end
  -- It fades in where it opens its line, and its colour turns with the news.
  local node = kit.subtitle { id = id, width = P.inner(w), wrap = true, font_size = P.SUB,
    text = function() return model.message:get() or "" end,
    color = function() return model.failed:get() and theme.color.error or theme.color.onSurfaceVariant end,
    opacity = function() return said() and 1 or 0 end,
    behavior = { opacity = { duration = theme.duration.normal, easing = theme.ease.standard },
      color = { duration = theme.duration.small } } }
  node.visible = said
  return node
end

--- A one-line text field the card's width, its text kept in `draft`;
--- `keys` are its Enter and Escape handlers.
local function field(id, w, placeholder, draft, kind, keys)
  keys = keys or {}
  local box, handle = P.field { id = id, width = w, placeholder = placeholder, kind = kind,
    on_changed = function(value) draft:set(value) end, on_accepted = keys.accept, on_escape = keys.escape }
  morf.effect("eva.mobile.field." .. id, function() handle.text = draft:get() end)
  return box, handle
end

--- A password field whose text stays in a local here, never in a signal:
--- the box, the input, and a holder with `get` and `set`. `keys`: `changed`,
--- `accept`, `escape`.
local function secret_field(id, w, placeholder, keys)
  keys = keys or {}
  local value, box, input = "", nil, nil
  box, input = P.field { id = id, width = w, placeholder = placeholder, kind = "password",
    on_changed = function(text) value = text if keys.changed then keys.changed(text) end end,
    on_accepted = keys.accept, on_escape = keys.escape }
  return box, input, { get = function() return value end,
    set = function(_, text) value = text input.text = text end }
end

-- ----------------------------------------------------------------- network --

--- A small round button at a row's right that opens what can be done to it.
local function manage_button(id, visible, on_clicked)
  local button = kit.action { id = id, accessible_name = "Manage", width = 36, height = 36, cursor = "pointer",
    visible = visible, on_clicked = on_clicked,
    kit.icon("settings", 20, kit.ink("lo"), { anchors = { center_in = true } }) }
  kit.hover(button, function(hovered) return hovered and kit.ink("hi")():alpha(0.12) or kit.ink("hi")():alpha(0) end, 18)
  return button
end

--- Under the list: the password (and for 802.1X the user name) a network
--- asks for, or what can be done to a saved one.
local function network_prompt(model, w)
  local inner = P.inner(w)
  local identity = morf.signal("eva.network.identity", "")
  local typed = morf.signal("eva.network.typed", false)
  local password
  local function mode(m) return function() return model.mode() == m end end
  local function asking() local m = model.mode() return m == "password" or m == "enterprise" end
  local function row() return model.asked() or {} end
  local function clear() identity:set("") password:set("") typed:set(false) end
  local function join() local i, p = identity:get(), password:get() clear() model.join(p, i) end
  local function cancel() clear() model.dismiss() end
  local pass_box, pass
  pass_box, pass, password = secret_field("network-password", inner, "Password",
    { changed = function(text) typed:set(text ~= "") end, accept = join, escape = cancel })
  local user_box, user = field("network-identity", inner, "User name", identity, "entry",
    { accept = function() pass.focus = true end, escape = cancel })
  user_box.visible, pass_box.visible = mode("enterprise"), asking
  local answer = P.buttons { width = inner,
    { id = "network-password-cancel", label = "Cancel", on_clicked = cancel },
    { id = "network-password-join", label = "Connect", tone = "primary", on_clicked = join,
      enabled = function() return typed:get() and (model.mode() ~= "enterprise" or identity:get() ~= "") end } }
  local manage = P.buttons { width = inner,
    { id = "network-disconnect", label = "Disconnect", on_clicked = model.disconnect,
      visible = function() return row().in_use == true end },
    { id = "network-change-password", label = "Password", on_clicked = model.change_password,
      visible = function() return row().secure == true end },
    { id = "network-forget", label = "Forget", on_clicked = model.forget,
      visible = function() return row().known == true end },
    { id = "network-manage-close", label = "Close", on_clicked = cancel } }
  local more = P.buttons { width = inner,
    { id = "network-details", icon = "tune", label = "Details", on_clicked = function() model.details(row()) end,
      visible = function() return row().known == true end },
    { id = "network-share", icon = "qr_code_2", label = "Share", on_clicked = function() model.share_shown:set(true) end,
      visible = function() return row().known == true or row().secure ~= true end } }
  answer.visible, manage.visible, more.visible = asking, mode("manage"), mode("manage")
  morf.effect("eva.network.prompt.focus", function()
    local m = model.mode()
    if m ~= "password" and m ~= "enterprise" then clear() end
    user.focus = m == "enterprise"
    pass.focus = m == "password"
  end)
  return ui.Column { id = "network-password-prompt", width = inner, gap = 8,
    visible = function() return model.asked() ~= nil end,
    kit.subtitle { id = "network-password-title", width = inner, elide = "right", font_size = P.SUB,
      text = function()
        local m, ssid = model.mode(), row().ssid or ""
        if m == "enterprise" then return "Sign in to " .. ssid end
        if m == "manage" then return ssid .. (row().in_use and " · Connected" or " · Saved") end
        return "Password for " .. ssid
      end },
    user_box, pass_box, answer, manage, more,
  }
end

--- The code a phone reads to join the network being managed, drawn straight
--- from what the model hands over and cleared as soon as it is shut.
local function share_panel(model, w)
  local inner = P.inner(w)
  local SIDE = math.min(inner, 240)
  local light = function() return require("themes.color_mode").resolve() == "light" end
  local paper = function() return light() and theme.color.surface or theme.color.onSurface end
  local ink = function() return light() and theme.color.onSurface or theme.color.surface end
  local code = ui.Path { id = "network-share-code", x = theme.space.s, y = theme.space.s, width = SIDE - 2 * theme.space.s,
    height = SIDE - 2 * theme.space.s, fill_color = ink }
  local failure = morf.signal("eva.network.share.failure", "")
  local function clear() code.d = "" code.view_box = { 0, 0, 1, 1 } end
  morf.effect("eva.network.share", function()
    if not model.share_shown:get() then clear() failure:set("") return end
    model.share(function(made)
      code.view_box = { 0, 0, made.size, made.size }
      code.d = made.path
    end, function(why) failure:set(tostring(why)) end)
  end)
  return ui.Column { id = "network-share-panel", width = inner, gap = theme.space.s, align = "center",
    visible = function() return model.share_shown:get() end,
    kit.surface { id = "network-share-paper", width = SIDE, height = SIDE, radius = kit.round(theme.space.s), color = paper, code,
      visible = function() return failure:get() == "" end },
    kit.subtitle { id = "network-share-failure", width = inner, wrap = true, font_size = P.SUB,
      text = function() return failure:get() end, visible = function() return failure:get() ~= "" end,
      color = function() return theme.color.error end },
    kit.subtitle { width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"), horizontal_alignment = "center",
      text = "Point a phone's camera at it to join this network." },
    P.button { id = "network-share-close", label = "Close", on_clicked = function() model.share_shown:set(false) end },
  }
end

--- Joining a network that does not announce itself.
local function hidden_section(model, w)
  local inner = P.inner(w)
  local ssid = morf.signal("eva.network.hidden.ssid", "")
  local password
  local open = morf.signal("eva.network.hidden.open", false)
  local ssid_box = field("network-hidden-ssid", inner, "Network name", ssid)
  local pass_box, _, holder = secret_field("network-hidden-password", inner, "Password, if it has one")
  password = holder
  local function join()
    local name, secret = ssid:get(), password:get()
    password:set("")
    if name ~= "" then
      open:set(false)
      ssid:set("")
      model.join_hidden(name, secret)
    end
  end
  return P.section { id = "network-hidden", width = w, title = "Other networks", visible = model.available,
    P.row { id = "network-hidden-open", width = inner, icon = "wifi_find", title = "Join a hidden network",
      subtitle = "One that does not show in the list", trailing = P.chevron(),
      on_clicked = function() open:set(not open:get()) end },
    ui.Column { width = inner, gap = theme.space.s, visible = function() return open:get() end,
      ssid_box, pass_box,
      P.button { id = "network-hidden-join", label = "Join", tone = "primary", width = inner, on_clicked = join },
    },
    P.row { id = "network-proxy-open", width = inner, icon = "shield", title = "Proxy", subtitle = "For this session's programs",
      trailing = P.chevron(), on_clicked = function() model.request("network/proxy") end },
    P.row { id = "network-help-open", width = inner, icon = "troubleshoot", title = "Connection help",
      subtitle = "Troubleshoot, speed test, sign-in pages",
      trailing = P.chevron(), on_clicked = function() model.request("network/help") end },
  }
end

local function network_page(model, w, h)
  local available = model.available
  local inner = P.inner(w)
  local networks = P.section { id = "network-list", width = w, title = "Networks",
    visible = available,
    list(w, "network-row-", function() return #model.list() end, function(i, rw)
      local function ap() return model.list()[i] or {} end
      return P.row { id = "network-ap-" .. i, width = rw, on = function() return ap().in_use == true end,
        icon = function() return model.signal_icon(ap().strength) end,
        title = function() return ap().ssid or "" end,
        subtitle = function()
          local a = ap()
          if a.in_use then return model.sign_in_needed() and "Connected · Needs you to sign in" or "Connected" end
          return a.secure and "Secured" or "Open"
        end,
        trailing = ui.Row { gap = 4, align = "center",
          visible = function() local a = ap() return a.secure == true or a.known == true or a.in_use == true end,
          kit.icon("lock", 16, kit.ink("lo"),
            { visible = function() local a = ap() return a.secure == true and not (a.known or a.in_use) end }),
          manage_button("network-manage-" .. i, function() return ap().known == true or ap().in_use == true end,
            function() model.manage(ap()) end) },
        on_clicked = function() model.choose(ap()) end }
    end, function() return model.enabled() and "No networks found" or "Turn on Wi-Fi to find networks." end),
    network_prompt(model, w),
    share_panel(model, w),
    status("network-status", model, w),
    action(w, { id = "network-rescan", icon = "wifi_find", label = "Rescan networks",
      on_clicked = function() model.scan() end }),
  }
  return ui.Item { id = "network-page", width = w, height = h, P.page { id = "network-scroll", width = w, height = h,
    on_refresh = function() model.scan() end,
    P.section { id = "wifi", caption_id = "wifi-title", width = w, title = "Wi-Fi",
      P.row { id = "network-enabled", width = inner, icon = "wifi", on = model.enabled, title = "Enabled",
        subtitle = function()
          if not available() then return "No network manager" end
          local count = #model.list()
          return ("%d network%s available"):format(count, count == 1 and "" or "s")
        end,
        trailing = P.switch { id = "network-wifi", name = "Wi-Fi", on = model.enabled, on_toggled = model.set_enabled } },
    },
    networks,
    hidden_section(model, w),
    missing(w, "wifi_off", "No network manager", "NetworkManager is not running, so there are no networks to list.",
      available),
  } }
end

-- --------------------------------------------------------------- bluetooth --

--- What a pairing device asks: a code to compare, a PIN or a passkey to
--- type, leave to pair, or a code to type on the device itself.
local function pairing_prompt(model, w)
  local inner = P.inner(w)
  local typed = morf.signal("eva.bluetooth.pairing.code", "")
  local function asked() return model.pairing() or {} end
  local function kind() return asked().kind or "" end
  local function entry() local k = kind() return k == "pin" or k == "passkey" end
  local function accept()
    if not entry() then return model.answer_pairing(true) end
    local value = typed:get()
    typed:set("")
    model.answer_pairing(value ~= "" and value or nil)
  end
  local function refuse() typed:set("") model.answer_pairing(nil) end
  local box, handle = field("bluetooth-pairing-code", inner, "PIN", typed, "entry", { accept = accept, escape = refuse })
  box.visible = entry
  morf.effect("eva.bluetooth.pairing.focus", function()
    local on = entry()
    if not on then typed:set("") end
    handle.focus = on
  end)
  local buttons = P.buttons { width = inner,
    { id = "bluetooth-pairing-refuse", label = "Cancel", on_clicked = refuse },
    { id = "bluetooth-pairing-accept", label = "Pair", tone = "primary", on_clicked = accept,
      visible = function() return kind() ~= "display" end } }
  local TITLE = {
    confirm = "Pair with %s? Check it shows this code:",
    authorize = "%s asks to pair",
    pin = "Type the PIN for %s",
    passkey = "Type the passkey %s shows",
    display = "Type this code on %s, then Enter:",
  }
  return ui.Column { id = "bluetooth-pairing-prompt", width = inner, gap = 8,
    visible = function() return model.pairing() ~= nil end,
    kit.subtitle { id = "bluetooth-pairing-title", width = inner, wrap = true, font_size = P.SUB,
      text = function() return (TITLE[kind()] or "%s"):format(model.pairing_name()) end },
    kit.text { id = "bluetooth-pairing-code-shown", font_size = theme.size.extra, font_weight = 700,
      visible = function() return asked().code ~= nil end,
      text = function() return asked().code or "" end },
    box, buttons,
  }
end

--- Under the list: what can be done to a paired device.
local function device_prompt(model, w)
  local inner = P.inner(w)
  local F = require("themes.layouts.form")
  local function dev() return model.asked() or {} end
  local alias = morf.signal("eva.bluetooth.alias", "")
  local alias_box, alias_input = field("bluetooth-device-alias", inner, "A name for this device", alias)
  morf.effect("eva.bluetooth.alias.fill", function()
    local d = dev()
    alias_input.text = d.alias or ""
  end)
  local buttons = P.buttons { width = inner,
    { id = "bluetooth-disconnect", label = "Disconnect", on_clicked = model.disconnect,
      visible = function() return dev().connected == true end },
    { id = "bluetooth-forget", label = "Forget", on_clicked = model.forget },
    { id = "bluetooth-manage-close", label = "Close", on_clicked = model.dismiss } }
  local sending = morf.signal("eva.bluetooth.sending", false)
  local more = P.buttons { width = inner,
    { id = "bluetooth-send", icon = "upload_file", label = "Send file", on_clicked = function() sending:set(not sending:get()) end },
    { id = "bluetooth-rename-device", label = "Rename", on_clicked = function() model.rename_device(dev(), alias:get()) end } }
  return ui.Column { id = "bluetooth-manage-prompt", width = inner, gap = 8,
    visible = function() return model.mode() == "manage" and model.asked() ~= nil end,
    kit.subtitle { id = "bluetooth-manage-title", width = inner, elide = "right", font_size = P.SUB,
      text = function()
        local d = dev()
        local words = (d.alias or d.name or d.address or "") .. " · Paired"
        if d.has_battery then words = words .. (" · Battery %d%%"):format(d.battery or 0) end
        return words
      end },
    F.toggle { id = "bluetooth-trusted", width = inner, icon = "verified", title = "Connect by itself",
      subtitle = "It may connect without asking", on = function() return dev().trusted == true end,
      set = function(on) model.set_trusted(dev(), on) end },
    alias_box, more,
    F.chooser { id = "bluetooth-send-chooser", width = inner, open = function() return sending:get() end,
      on_accepted = function(path) sending:set(false) model.send_file(dev(), path) end,
      on_cancelled = function() sending:set(false) end },
    kit.subtitle { id = "bluetooth-send-progress", width = inner, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function() return model.transfer:get() end, visible = function() return model.transfer:get() ~= "" end },
    buttons,
  }
end

--- This computer's name as nearby devices see it.
local function adapter_section(model, w)
  local inner = P.inner(w)
  local name = morf.signal("eva.bluetooth.adapter.name", "")
  local box, input = field("bluetooth-adapter-name", inner, "This computer's name", name)
  morf.effect("eva.bluetooth.adapter.fill", function() input.text = model.adapter_name() end)
  return P.section { id = "bluetooth-adapter", width = w, title = "This computer", visible = model.available,
    box,
    P.button { id = "bluetooth-adapter-save", label = "Rename", width = inner,
      on_clicked = function() model.rename_adapter(name:get()) end },
  }
end

local function bluetooth_page(model, w, h)
  local available = model.available
  local inner = P.inner(w)
  local devices = P.section { id = "bluetooth-list", width = w, title = "Devices",
    visible = available,
    list(w, "bluetooth-row-", function() return #model.list() end, function(i, rw)
      local function dev() return model.list()[i] or {} end
      local function on() return dev().connected == true end
      return P.row { id = "bluetooth-device-" .. i, width = rw, on = on,
        icon = function() return on() and "bluetooth_connected" or "bluetooth" end,
        title = function() local d = dev() return d.alias or d.name or d.address or "" end,
        subtitle = function()
          local d = dev()
          if d.connected then return d.has_battery and d.battery and ("Connected · %d%%"):format(d.battery) or "Connected" end
          return d.paired and "Paired" or "Not paired"
        end,
        trailing = manage_button("bluetooth-manage-" .. i, function() return dev().paired == true end,
          function() model.manage(dev()) end),
        on_clicked = function() model.choose(dev()) end }
    end, function() return model.enabled() and "No devices" or "Turn on Bluetooth to find devices." end),
    pairing_prompt(model, w),
    device_prompt(model, w),
    status("bluetooth-status", model, w),
    action(w, { id = "bluetooth-settings", icon = "settings", label = "Open settings",
      on_clicked = function() model.open_settings() end }),
  }
  return ui.Item { id = "bluetooth-page", width = w, height = h, P.page { id = "bluetooth-scroll", width = w, height = h,
    on_refresh = function() model.scan(true) end,
    P.section { id = "bluetooth", caption_id = "bluetooth-title", width = w, title = "Bluetooth",
      P.row { id = "bluetooth-enabled", width = inner, icon = "bluetooth", on = model.enabled, title = "Enabled",
        subtitle = function()
          if not available() then return "No Bluetooth adapter" end
          local count = #model.list()
          return ("%d device%s"):format(count, count == 1 and "" or "s")
        end,
        trailing = P.switch { id = "bluetooth-power", name = "Bluetooth", on = model.enabled,
          on_toggled = model.set_enabled } },
      P.row { id = "bluetooth-discovering", width = inner, icon = "bluetooth_searching", on = model.discovering,
        title = "Discovering", subtitle = "Look for devices nearby",
        trailing = P.switch { id = "bluetooth-discover", name = "Discovering", on = model.discovering,
          on_toggled = model.scan } },
    },
    devices,
    adapter_section(model, w),
    missing(w, "bluetooth_disabled", "No Bluetooth adapter", "There is no Bluetooth adapter to use.", available),
  } }
end

local function mobile_page(model,w,h)
  local inner=P.inner(w)
  local function details() return model.details:get() or {} end
  local function modem() return details().modem or {} end
  local function sim() return details().sim or {} end
  local function profile()
    for _,r in ipairs(model.list()) do if (r.active or "")~="" then return r end end
    return model.list()[1]
  end
  local function has_profile() return profile()~=nil end
  local function busy() return model.pending:get() end
  local draft={}
  for _,k in ipairs {"apn","user","ussd","ussd_reply","sms_to","sms_text","limit"} do
    draft[k]=morf.signal("eva.mobile.draft."..k,"")
  end
  local password_box,pin_box,new_pin_box,_
  password_box,_,draft.password=secret_field("mobile-password",inner,"Password (optional)")
  pin_box,_,draft.pin=secret_field("mobile-pin",inner,"SIM PIN")
  new_pin_box,_,draft.new_pin=secret_field("mobile-new-pin",inner,"New PIN (to change it)")
  morf.effect("eva.mobile.draft.profile",function()
    local p=profile() or {}
    draft.apn:set(p.auto_apn and "" or (p.apn or "")) draft.user:set(p.user or "")
  end)
  local function save(change) local p=profile() if p then model.save_profile(p,change) end end

  local IP={{"ipv4","IPv4"},{"ipv4v6","IPv4 + IPv6"},{"ipv6","IPv6"}}
  local ip_buttons={width=inner}
  for _,t in ipairs(IP) do
    ip_buttons[#ip_buttons+1]={id="mobile-ip-"..t[1],label=t[2],enabled=function() return not busy() end,
      selected=function() return (profile() or {}).ip_type==t[1] end,on_clicked=function() save({ip_type=t[1]}) end}
  end
  local mode_buttons={width=inner}
  for i=1,5 do
    local function choice() return (model.modes())[i] end
    mode_buttons[#mode_buttons+1]={id="mobile-mode-"..i,label=function() return (choice() or {}).name or "" end,
      visible=function() return choice()~=nil end,enabled=function() return not busy() end,
      selected=function() local _,now=model.modes() return choice()~=nil and choice().id==now end,
      on_clicked=function() if choice() then model.set_mode(choice()) end end}
  end

  return ui.Item {id="mobile-page",width=w,height=h,
    P.page {id="mobile-scroll",width=w,height=h,active=model.active,
      P.section {id="mobile-radio",width=w,title="Mobile data",visible=model.available,
        P.row {id="mobile-enabled",width=inner,icon="signal_cellular_alt",title="Enabled",on=model.enabled,
          subtitle=model.status,
          trailing=P.switch {id="mobile-data",name="Mobile data",on=model.enabled,
            on_toggled=function(on) if model.can_toggle() then model.set_enabled(on) end end}},
        P.row {id="mobile-carrier",width=inner,icon="cell_tower",title=model.carrier,
          subtitle=model.signal,on=function() return false end},
        P.row {id="mobile-diagnosis",width=inner,icon="report",title="Problem",on=function() return false end,
          visible=function() return model.diagnosis()~=nil end,
          subtitle=function() return (model.diagnosis() or {}).text or "" end,
          trailing=P.button {id="mobile-fix",label=model.fix_label,tone="primary",
            visible=function() return model.fix_label()~="" and not busy() end,on_clicked=model.fix}},
        action(w,{id="mobile-reset",icon="restart_alt",label="Restart mobile radio",
          enabled=function() return not busy() end,on_clicked=model.reset_radio}),
      },
      P.section {id="mobile-connections",width=w,title="Connections",visible=model.available,
        list(w,"mobile-row-",function() return #model.list() end,function(i,rw)
          local function row() return model.list()[i] or {} end
          local function connected() return (row().active or "")~="" end
          return P.row {id="mobile-profile-"..i,width=rw,icon="sim_card",title=function() return row().name or "" end,
            on=connected,subtitle=function()
              local r=row()
              local state=({activated="Connected",activating="Connecting…",deactivating="Disconnecting…"})[r.state] or "Disconnected"
              return state.." · "..((r.apn or "")~="" and ("APN: "..r.apn) or r.auto_apn and "Automatic APN" or "Provider APN")
            end,
            trailing=P.button {id="mobile-connect-"..i,
              label=function() return connected() and "Disconnect" or "Connect" end,
              visible=function() return not model.pending:get() and (connected() or model.can_connect()) end,
              on_clicked=function() model.choose(row()) end}}
        end,"No saved mobile connections"),
        action(w,{id="mobile-setup",icon="add",label="Set up automatically",
          visible=function() return #model.list()==0 and model.can_connect() end,
          on_clicked=model.setup}),
        status("mobile-status",model,w),
        kit.subtitle {width=inner,wrap=true,font_size=P.SUB,text=model.note,color=kit.ink("lo")},
      },
      P.section {id="mobile-profile",width=w,title="Connection settings",
        visible=function() return model.available() and has_profile() end,
        kit.subtitle {width=inner,font_size=P.SUB,color=kit.ink("lo"),text="APN (empty for automatic)"},
        field("mobile-apn",inner,"live.vodafone.com",draft.apn),
        field("mobile-user",inner,"User (optional)",draft.user),
        password_box,
        P.buttons {width=inner,
          {id="mobile-apn-save",label="Save",tone="primary",enabled=function() return not busy() end,
            on_clicked=function()
              local change={apn=draft.apn:get(),user=draft.user:get()}
              if draft.password:get()~="" then change.password=draft.password:get() end
              save(change)
            end},
          {id="mobile-apn-auto",label="Automatic APN",enabled=function() return not busy() end,
            on_clicked=function() draft.apn:set("") save({apn=""}) end}},
        kit.subtitle {width=inner,font_size=P.SUB,color=kit.ink("lo"),text="IP type"},
        P.buttons(ip_buttons),
        P.row {id="mobile-roaming",width=inner,icon="public",title="Roaming",
          on=function() return (profile() or {}).roaming==true end,
          subtitle=function() return (profile() or {}).roaming and "Allowed on other networks" or "Home network only" end,
          trailing=P.switch {id="mobile-roaming-switch",name="Roaming",
            on=function() return (profile() or {}).roaming==true end,
            on_toggled=function(on) save({roaming=on}) end}},
      },
      P.section {id="mobile-network",width=w,title="Network",visible=model.available,
        kit.subtitle {width=inner,font_size=P.SUB,color=kit.ink("lo"),text="Network mode"},
        P.buttons(mode_buttons),
        list(w,"mobile-operator-",function() return #model.networks:get() end,function(i,rw)
          local function n() return model.networks:get()[i] or {} end
          return P.row {id="mobile-operator-row-"..i,width=rw,icon="cell_tower",
            on=function() return n().availability=="current" end,
            title=function() return n().name or "" end,
            subtitle=function() return unicase.upper(n().technology or "").." · "..(n().availability or "") end,
            on_clicked=function() if n().code then model.register(n().code) end end}
        end,"Scan to list the networks nearby",16),
        P.buttons {width=inner,
          {id="mobile-scan",icon="radar",label=function() return model.scanning:get() and "Scanning…" or "Scan networks" end,
            enabled=function() return not busy() end,on_clicked=model.scan_networks},
          {id="mobile-automatic",label="Automatic",enabled=function() return not busy() end,
            on_clicked=function() model.register(nil) end}},
      },
      P.section {id="mobile-sim",width=w,title="SIM",visible=model.available,
        P.row {id="mobile-sim-info",width=inner,icon="sim_card",on=function() return false end,
          title=function()
            local s=sim()
            if (s.operator or "")~="" then return s.operator end
            return (s.operator_code or "")~="" and ("Home network "..s.operator_code) or "SIM"
          end,
          subtitle=function()
            local s,m,parts=sim(),modem(),{}
            if (m.own_numbers or {})[1] then parts[#parts+1]=m.own_numbers[1] end
            if (s.iccid_tail or "")~="" then parts[#parts+1]="ICCID …"..s.iccid_tail end
            local tries=(m.retries or {})["sim-pin"]
            if tries then parts[#parts+1]=tries.." PIN tries left" end
            return #parts>0 and table.concat(parts," · ") or "No SIM details"
          end},
        pin_box,new_pin_box,
        P.buttons {width=inner,
          {id="mobile-unlock",label="Unlock",tone="primary",visible=function() return modem().locked~=nil end,
            enabled=function() return not busy() end,on_clicked=function() model.unlock(draft.pin:get()) draft.pin:set("") end},
          {id="mobile-change-pin",label="Change PIN",enabled=function() return not busy() end,
            on_clicked=function() model.change_pin(draft.pin:get(),draft.new_pin:get()) draft.pin:set("") draft.new_pin:set("") end},
          {id="mobile-pin-on",label="PIN on",enabled=function() return not busy() end,
            on_clicked=function() model.set_pin_lock(draft.pin:get(),true) draft.pin:set("") end},
          {id="mobile-pin-off",label="PIN off",enabled=function() return not busy() end,
            on_clicked=function() model.set_pin_lock(draft.pin:get(),false) draft.pin:set("") end}},
      },
      P.section {id="mobile-ussd",width=w,title="USSD codes",visible=model.available,
        field("mobile-ussd-code",inner,"*100#",draft.ussd),
        P.buttons {width=inner,
          {id="mobile-ussd-send",label="Send code",enabled=function() return not busy() end,
            on_clicked=function() if draft.ussd:get()~="" then model.ussd(draft.ussd:get()) end end}},
        (function()
          local node=kit.subtitle {id="mobile-ussd-reply",width=inner,wrap=true,font_size=P.SUB,
            text=function() return model.ussd_reply:get().text or "" end}
          node.visible=function() return (model.ussd_reply:get().text or "")~="" end
          return node
        end)(),
        ui.Column {width=inner,gap=P.ROW_GAP,visible=function() return model.ussd_reply:get().open==true end,
          field("mobile-ussd-answer",inner,"Reply",draft.ussd_reply),
          P.buttons {width=inner,
            {id="mobile-ussd-respond",label="Reply",enabled=function() return not busy() end,
              on_clicked=function() model.ussd_respond(draft.ussd_reply:get()) draft.ussd_reply:set("") end},
            {id="mobile-ussd-cancel",label="End",on_clicked=model.ussd_cancel}}},
      },
      P.section {id="mobile-messages",width=w,title="Messages",visible=model.has_messages,
        list(w,"mobile-sms-",function() return #model.threads() end,function(i,rw)
          local function s() return model.threads()[i] or {} end
          return P.row {id="mobile-sms-row-"..i,width=rw,icon="sms",on=function() return (s().unread or 0)>0 end,
            title=function() return s().label or "" end,subtitle=function() return s().last or "" end,
            trailing=P.button {id="mobile-sms-delete-"..i,label="Delete",
              on_clicked=function() if s().number then model.delete_thread(s().number) end end}}
        end,"No messages",24),
        field("mobile-sms-to",inner,"Phone number",draft.sms_to),
        field("mobile-sms-text",inner,"Message",draft.sms_text),
        P.buttons {width=inner,
          {id="mobile-sms-send",label="Send",tone="primary",enabled=function() return not busy() end,
            on_clicked=function()
              if model.send_message(draft.sms_to:get(),draft.sms_text:get()) then draft.sms_text:set("") end
            end}},
      },
      P.section {id="mobile-signal",width=w,title="Signal",visible=function() return model.levels()~="" end,
        P.row {id="mobile-levels",width=inner,icon="network_cell",on=function() return false end,
          title=model.levels,subtitle=function()
            local number=model.number()
            return number~="" and ("This SIM: "..number) or "Measured by the modem"
          end},
      },
      P.section {id="mobile-usage",width=w,title="Data this month",visible=model.available,
        list(w,"mobile-usage-",function() return #model.usage() end,function(i,rw)
          local function u() return model.usage()[i] or {} end
          return P.row {id="mobile-usage-row-"..i,width=rw,
            icon=function() return ({mobile="signal_cellular_alt",wifi="wifi",wired="lan"})[u().kind or ""] or "lan" end,
            on=function() return u().kind=="mobile" end,title=function() return u().name or "" end,
            subtitle=function() return model.usage_size(u().bytes) end}
        end,"Nothing counted yet",24),
        field("mobile-limit",inner,"Monthly limit in MB (0 for none)",draft.limit),
        P.buttons {width=inner,
          {id="mobile-limit-save",label="Set limit",on_clicked=function() model.set_limit(draft.limit:get()) end},
          {id="mobile-usage-reset",label="Start over",on_clicked=model.usage_reset}},
      },
      P.section {id="mobile-calls",width=w,title="Calls",visible=model.has_voice,
        P.row {id="mobile-waiting",width=inner,icon="phone_paused",title="Call waiting",
          subtitle="A second call can ask while you talk",
          trailing=P.switch {id="mobile-waiting-switch",name="Call waiting",on=function() return model.call_waiting:get() end,
            on_toggled=model.set_call_waiting}},
      },
      P.section {id="mobile-alerts",width=w,title="Emergency alerts",visible=model.has_voice,
        (function()
          local rows={gap=P.ROW_GAP,width=inner}
          for _,kind in ipairs(model.alert_kinds()) do
            rows[#rows+1]=P.row {id="mobile-alert-"..kind.id,width=inner,icon="warning",title=kind.name,
              on=function() return model.alert_on(kind.id) end,
              trailing=P.switch {id="mobile-alert-switch-"..kind.id,name=kind.name,
                on=function() return model.alert_on(kind.id) end,
                on_toggled=function(on) model.set_alert(kind.id,on) end}}
          end
          return ui.Column(rows)
        end)(),
        list(w,"mobile-alert-past-",function() return math.min(4,#model.alert_history()) end,function(i,rw)
          local function a() return model.alert_history()[i] or {} end
          return P.row {id="mobile-alert-row-"..i,width=rw,icon="history",on=function() return false end,
            title=function() return a().title or "" end,subtitle=function() return a().text or "" end}
        end,"No alerts so far",24),
      },
      missing(w,"signal_cellular_nodata","No modem","No mobile modem is available. This page updates when one is detected.",model.available),
    },
  }
end

--- The id of the row that shows `row` of `model`'s list.
function M.row_id(model, row)
  for i, r in ipairs(model.list()) do
    if r == row or (r.path ~= nil and r.path == row.path) then
      return (model.wireless and "network" or "bluetooth") .. "-row-" .. i
    end
  end
end

function M.build(model, w, h)
  if model.key=="mobile" then return mobile_page(model,w,h) end
  return model.wireless and network_page(model, w, h) or bluetooth_page(model, w, h)
end
return M
