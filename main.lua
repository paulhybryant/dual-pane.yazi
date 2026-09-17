--- @sync entry

-- Modern Yazi compatibility layer
local emit = ya.emit or ya.mgr_emit or ya.manager_emit
if not ya.manager_emit then
  ya.manager_emit = emit
end
if not ya.app_emit then
  ya.app_emit = emit
end

local set_state = ya.sync(function(state, key, value)
  state[key] = value
end)

local set_state_vector = ya.sync(function(state, key, vector)
  state[key] = {}
  for _, value in ipairs(vector) do
    table.insert(state[key], value)
  end
end)

local get_state = ya.sync(function(state, key)
  return state[key]
end)

local get_cwd = ya.sync(function() return cx.active.current.cwd end)

local function _get_command(filename)
	local _permit = ya.hide()
	local cwd = tostring(get_cwd())

	local child, err =
		Command("bash"):args({ "-c", "cat " .. filename .. " | fzf" }):cwd(cwd):stdin(Command.INHERIT):stdout(Command.PIPED):stderr(Command.INHERIT):spawn()

	if not child then
		return fail("Spawn `fzf` failed with error code %s. Do you have it installed?", err)
	end

	local output, err = child:wait_with_output()
	if not output then
		return fail("Cannot read `fzf` output, error code %s", err)
	elseif not output.status.success and output.status.code ~= 130 then
		return fail("`fzf` exited with error code %s", output.status.code)
	end

  _permit:drop()

	local target = output.stdout:gsub("\n$", "")
  return target
end

-- Prepare urls
local _prepare_urls = ya.sync(function(state, macro)
  local pane = get_state("cpane") or 1
  local tabs = get_state("ctabs") or { 1, 1 }
  local this = (tabs[pane] and cx.tabs[tabs[pane]]) or cx.active
  local other_idx = tabs[pane % 2 + 1]
  local other = (other_idx and cx.tabs[other_idx]) or this

  local urls = nil
  if macro == "f" then
    if #this.selected > 0 then
      urls = this.selected
    elseif this.current.hovered ~= nil then
      urls = { this.current.hovered.url }
    end
  elseif macro == "d" then
    local d1 = this.current.cwd
    if d1 ~= nil then
      urls = { d1 }
    end
  elseif macro == "c" then
    local c1 = this.current.hovered
    if c1 ~= nil then
      urls = { c1.url }
    end
  elseif macro == "F" then
    if #other.selected > 0 then
      urls = other.selected
    elseif other.current.hovered ~= nil then
      urls = { other.current.hovered.url }
    end
  elseif macro == "D" then
    local d1 = other.current.cwd
    if d1 ~= nil then
      urls = { d1 }
    end
  elseif macro == "C" then
    local c1 = other.current.hovered
    if c1 ~= nil then
      urls = { c1.url }
    end
  end

  return urls
end)

local _prepare_expansion = ya.sync(function(state, urls, modifier)
    local names = ""
    for _, url in pairs(urls) do
      local name
      if modifier == "" then
        name = tostring(url)
      elseif modifier == "n" then
        name = url:name()
      elseif modifier == "s" then
        name = url:stem()
      elseif modifier == "e" then
        name = url:ext()
      end
      if name == nil then
        name = ""
      end
      names = names .. ya.quote(name) .. " "
    end
    -- Remove last space
    names = names:sub(1, -2)

    return names
  end)

-- macros cannot be run in an already expanded string, or files containing
-- macro triggers in their names will also be expanded. So expansion can only
-- happen once; running through the cmd only once.
local _expand_macros = ya.sync(function(_, cmd)
  local expanded = ""
  local i = 1
  while i <= #cmd do
    local mi, mj, macro = cmd:find("%%([fFcCdD])", i)
    if mi then
      local urls = _prepare_urls(macro)
      if urls ~= nil then
        -- Add substring before match to expanded
        expanded = expanded .. cmd:sub(i, mi - 1)
        local modifier = cmd:sub(mj + 1, mj + 2)
        local _, _, mod = modifier:find(":([nse])")
        if not mod then
          mod = ""
          i = mi + 2
        else
          i = mi + 4
        end
        expanded = expanded .. _prepare_expansion(urls, mod)
      else
        -- Invalid urls, for example %c in an empty directory
        ya.notify({
          title = "dual-pane",
          content = string.format("Invalid macro expansion '%s'", "%" .. macro),
          timeout = 3,
          level = "error"
        })
        return ""
      end
    else
      expanded = expanded .. cmd:sub(i, -1)
      break
    end
  end

  return expanded
end)

local Pane = {
  _id = "pane",
}

function Pane:new(area, tab, pane)
  local me = setmetatable({ _area = area }, { __index = self })
  me:layout()
  me:build(tab or cx.active, pane)
  return me
end

function Pane:layout()
  self._chunks = ui.Layout()
    :direction(ui.Layout.VERTICAL)
    :constraints({
      ui.Constraint.Length(1),
      ui.Constraint.Fill(1),
    })
    :split(self._area)
end

function Pane:build(tab, pane)
  local header = Header:new(self._chunks[1], tab)
  header.pane = pane
  self._children = {
    header,
    Tab:new(self._chunks[2], tab),
  }
end

setmetatable(Pane, { __index = Root })

local Panes = {
  _id = "panes"
}

function Panes:new(area, tab_left, tab_right)
  local me = setmetatable({ _area = area }, { __index = self })
  me:layout()
  me:build(tab_left or cx.active, tab_right or cx.active)
  return me
end

function Panes:layout()
  self._chunks = ui.Layout()
    :direction(ui.Layout.VERTICAL)
    :constraints({
      ui.Constraint.Fill(1),
      ui.Constraint.Length(1),
    })
    :split(self._area)

  self._panes_chunks = ui.Layout()
    :direction(ui.Layout.HORIZONTAL)
    :constraints({
      ui.Constraint.Percentage(50),
      ui.Constraint.Percentage(50),
    })
    :split(self._chunks[1])
end

function Panes:build(tab_left, tab_right)
  self._children = {
    Pane:new(self._panes_chunks[1], tab_left, 1),
    Pane:new(self._panes_chunks[2], tab_right, 2),
    Status:new(self._chunks[2], cx.active),
  }
end

setmetatable(Panes, { __index = Root })

local DualPane = {
  pane = nil,
  tabs = {},
  view = nil, -- 0 = dual, 1 = current zoomed

  old_root_layout = nil,
  old_root_build = nil,
  old_tab_layout = nil,
  old_header_cwd = nil,
  old_header_tabs = nil,

  _create = function(self)
    self.pane = 1
    if cx then
      self.tabs[1] = cx.tabs.idx
      if #cx.tabs > 1 then
        self.tabs[2] = cx.tabs.idx % #cx.tabs + 1
      else
        self.tabs[2] = self.tabs[1]
      end
    else
      self.tabs[1] = 1
      self.tabs[2] = 1
    end

    self.old_root_layout = Root.layout
    self.old_root_build = Root.build
    self._config_dual_pane(self)

    self.old_header_cwd = Header.cwd
    Header.cwd = function(header)
      local max = header._area.w - header._right_width
      if max <= 0 then
        return ui.Span("")
      end

      local s = ya.readable_path(tostring(header._tab.current.cwd)) .. header:flags()
      local style_active = (th and th.tabs and th.tabs.active) or (THEME and THEME.manager and THEME.manager.tab_active) or ui.Style():bold()
      local style_inactive = (th and th.tabs and th.tabs.inactive) or (THEME and THEME.manager and THEME.manager.tab_inactive) or ui.Style():dim()
      local truncate_fn = ui.truncate or ya.truncate or function(str) return str end
      if header.pane == self.pane then
        return ui.Span(truncate_fn(s, { max = max, rtl = true })):style(style_active)
      else
        return ui.Span(truncate_fn(s, { max = max, rtl = true })):style(style_inactive)
      end
    end

    self.old_tab_layout = Tab.layout
    Tab.layout = function(tab_self)
      tab_self._chunks = ui.Layout()
        :direction(ui.Layout.HORIZONTAL)
        :constraints({
          ui.Constraint.Percentage(0),
          ui.Constraint.Percentage(100),
          ui.Constraint.Percentage(0),
        })
        :split(tab_self._area)
    end
  end,

  _destroy = function(self)
    Root.layout = self.old_root_layout
    self.old_root_layout = nil
    Root.build = self.old_root_build
    self.old_root_build = nil
    Tab.layout = self.old_tab_layout
    self.old_tab_layout = nil
    Header.cwd = self.old_header_cwd
    self.old_header_cwd = nil
    Header.tabs = self.old_header_tabs
    self.old_header_tabs = nil
  end,

  -- This function tests all the tabs in self.tabs are still valid. Some could
  -- have been deleted and we wouldn't get notified because tab_close is not
  -- a dual-pane command. If any is invalid, choose another one.
  _verify_update_tabs = function(self)
    for i = 1, #self.tabs do
      if cx.tabs[self.tabs[i]] == nil then
        self.tabs[i] = cx.tabs.idx
      end
    end
  end,

  _config_dual_pane = function(self)
    Root.layout = function(root)
      root._chunks = ui.Layout()
        :direction(ui.Layout.HORIZONTAL)
        :constraints({
          ui.Constraint.Percentage(100),
        })
        :split(root._area)
    end

    Root.build = function(root)
      self._verify_update_tabs(self)
      local t1 = cx.tabs[self.tabs[1]] or cx.active
      local t2 = cx.tabs[self.tabs[2]] or cx.active
      root._children = {
        Panes:new(root._chunks[1], t1, t2),
        Modal:new(root._area),
      }
    end
  end,

  _config_single_pane = function(self)
    Root.layout = function(root)
      root._chunks = ui.Layout()
        :direction(ui.Layout.VERTICAL)
        :constraints({
          ui.Constraint.Fill(1),
          ui.Constraint.Length(1),
        })
        :split(root._area)
    end

    Root.build = function(root)
      self._verify_update_tabs(self)
      local tab = cx.tabs[self.tabs[self.pane]] or cx.active
      root._children = {
        Pane:new(root._chunks[1], tab, self.pane),
        Status:new(root._chunks[2], tab),
        Modal:new(root._area),
      }
    end
  end,

  toggle = function(self)
    if self.view == nil then
      self._create(self)
      self.view = 0
    else
      self._destroy(self)
      self.view = nil
    end
    emit("resize", {})
  end,

  toggle_zoom = function(self)
    if self.view then
      if self.view == 0 then
        self._config_single_pane(self)
        self.view = 1
      else
        self._config_dual_pane(self)
        self.view = 0
      end
      emit("resize", {})
    end
  end,

  focus_next = function(self)
    if self.view and self.pane then
      self.pane = self.pane % 2 + 1
      local tab = self.tabs[self.pane]
      emit("tab_switch", { tab - 1 })
      emit("resize", {})
    end
  end,

  -- Copy selected files, or if there are none, the hovered item, to the
  -- destination directory
  copy_files = function(self, cut, force, follow)
    if self.view then
      local src_tab = self.tabs[self.pane]
      local dst_tab = self.tabs[self.pane % 2 + 1]
      -- yank selected
      if cut then
        emit("yank", { cut = true })
      else
        emit("yank", {})
      end
      -- select dst tab
      emit("tab_switch", { dst_tab - 1 })
      -- paste
      emit("paste", { force = force, follow = follow })
      -- unyank
      emit("unyank", {})
      -- select src tab again
      emit("tab_switch", { src_tab - 1 })
      emit("resize", {})
    end
  end,

  tab_switch = function(self, tab_number)
    if self.pane then
      self.tabs[self.pane] = tab_number
    end
    emit("tab_switch", { tab_number - 1 })
  end,

  load_config = function(self, state)
    if self.view == nil then
      return
    end
    local len = #cx.tabs
    -- First switch to the last tab, as new ones will be inserted after the
    -- active one
    emit("tab_switch", { len - 1 })
    -- Add stored tabs
    for _, path in ipairs(state.paths) do
      emit("tab_create", { path.cwd })
      if path.file ~= "" then
        emit("reveal", { path.file })
      end
    end
    -- Now delete the old ones
    for i = 1, len do
      emit("tab_close", { 0 })
    end
    self.tabs = { state.tabs[1], state.tabs[2] }
    self.pane = state.pane
    -- Refresh other pane
    emit("tab_switch", { self.tabs[self.pane % 2 + 1] - 1 })
    emit("refresh", {})

    emit("tab_switch", { self.tabs[self.pane] - 1 })
    emit("resize", {})
  end,

  save_config = function(self, state)
    if self.view == nil then
      return
    end
    state = {}
    state.pane = self.pane
    state.tabs = { self.tabs[1], self.tabs[2] }
    state.paths = {}
    for i = 1, #cx.tabs do
      local folder = cx.tabs[i].current
      local file
      if folder.hovered then
        file = tostring(folder.hovered.url)
      else
        file = ""
      end
      table.insert(state.paths, { cwd = tostring(folder.cwd), file = file })
    end
    ps.pub_to(0, "@dual-pane", state)
  end,

  reset_config = function(self, state)
    if self.view == nil then
      return
    end
    state = nil
    ps.pub_to(0, "@dual-pane", state)
  end,

  shell = function(self, state, cmd, blocking)
    local expanded = _expand_macros(cmd)
    if expanded ~= "" then
      emit("shell", { block = blocking, orphan = true, confirm = true, expanded } )
    end
  end
}

local function load_state(state)
  ps.sub_remote("@dual-pane", function(body)
    if body then
      state.pane = 1
      state.tabs = {}
      state.paths = {}
      for key, value in pairs(body) do
        if key == "pane" then
          state.pane = value
        elseif key == "tabs" then
          for _, tab in ipairs(value) do
            table.insert(state.tabs, tab)
          end
        elseif key == "paths" then
          for _, path in ipairs(value) do
            table.insert(state.paths, path)
          end
        end
      end
    end
  end)
end

local function get_copy_arguments(args)
  local force = false
  local follow = false
  if args[2] then
    if args[2] == "--force" then
      force = true
    elseif args[2] == "--follow" then
      follow = true
    end
    if args[3] then
      if args[3] == "--force" then
        force = true
      elseif args[3] == "--follow" then
        follow = true
      end
    end
  end
  return force, follow
end

local function parse_job_args(job_or_args)
  local result = {}
  if not job_or_args then
    return result
  end

  local raw = job_or_args
  if type(job_or_args) == "table" and job_or_args.args ~= nil then
    raw = job_or_args.args
  end

  if type(raw) == "table" then
    if type(raw.args) == "string" then
      for token in raw.args:gmatch("%S+") do
        table.insert(result, token)
      end
    elseif type(raw.args) == "table" then
      for _, v in ipairs(raw.args) do
        table.insert(result, tostring(v))
      end
    else
      for _, v in ipairs(raw) do
        table.insert(result, tostring(v))
      end
    end
  elseif type(raw) == "string" then
    for token in raw:gmatch("%S+") do
      table.insert(result, token)
    end
  end

  return result
end

local function entry(self, job_or_args)
  local args = parse_job_args(job_or_args)
  local action = args[1]
  if not action then
    return
  end

  if action == "toggle" then
    DualPane:toggle()
  elseif action == "toggle_zoom" then
    DualPane:toggle_zoom()
  elseif action == "next_pane" then
    DualPane:focus_next()
  elseif action == "copy_files" then
    local force, follow = get_copy_arguments(args)
    DualPane:copy_files(false, force, follow)
  elseif action == "move_files" then
    local force, follow = get_copy_arguments(args)
    DualPane:copy_files(true, force, follow)
  elseif action == "tab_switch" then
    if args[2] then
      local tab = tonumber(args[2])
      if tab then
        if args[3] and args[3] == "--relative" then
          if DualPane.pane and DualPane.tabs[DualPane.pane] then
            tab = (DualPane.tabs[DualPane.pane] - 1 + tab) % #cx.tabs
          else
            tab = (cx.tabs.idx - 1 + tab) % #cx.tabs
          end
        end
        DualPane:tab_switch(tab + 1)
      end
    end
  elseif action == "tab_create" then
    if args[2] then
      local dir
      if args[2] == "--current" then
        dir = tostring(cx.active.current.cwd)
      else
        dir = args[2]
      end
      emit("tab_create", { dir })
    else
      emit("tab_create", {})
    end
    local this = DualPane.pane
    local other = DualPane.pane and (DualPane.pane % 2 + 1)
    if this and other and DualPane.tabs[other] and DualPane.tabs[this] and DualPane.tabs[other] > DualPane.tabs[this] then
      DualPane.tabs[other] = DualPane.tabs[other] + 1
    end
    DualPane:tab_switch(cx.tabs.idx + 1)
  elseif action == "load_config" then
    DualPane:load_config(self)
  elseif action == "save_config" then
    DualPane:save_config(self)
  elseif action == "reset_config" then
    DualPane:reset_config(self)
  end

  -- Always store the current state of pane and tabs so the async context
  -- for 'shell' commands has access to it
  if DualPane.pane then
    set_state("cpane", DualPane.pane)
  end

  if #DualPane.tabs > 0 then
    set_state_vector("ctabs", DualPane.tabs)
  end

  if action == "shell" then
    local cmd = ""
    local block = false
    local interactive = false
    for i = 2, #args do
      if args[i] == "--block" then
        block = true
      elseif args[i] == "--interactive" then
        interactive = true
      else
        if args[i]:find("%s") then
          cmd = cmd .. ya.quote(args[i]) .. " "
        else
          cmd = cmd .. args[i] .. " "
        end
      end
    end
    if interactive then
      local cmd_input, event = ya.input({
        title = "Shell command:",
        value = cmd,
        position = { "top-center", y = 3, w = 40 },
      })
      if event == 1 then
        DualPane:shell(self, cmd_input, block)
      end
    else
      if cmd ~= "" then
        DualPane:shell(self, cmd, block)
      end
    end
  elseif action == "shell_fzf" then
    local interactive = false
    local filename
    for i = 2, #args do
      if args[i] == "--interactive" then
        interactive = true
      else
        filename = args[i]
      end
    end
    if filename then
      local file = io.open(filename, "r")
      if not file then
        ya.notify({
          title = "dual-pane",
          content = string.format("Cannot open shell_fzf file '%s'", filename),
          timeout = 3,
          level = "error"
        })
      else
        io.close(file)
        local cmd = _get_command(filename)
        if cmd ~= "" then
          local _, _, run, desc, block = cmd:find("run%s*=%s*\"(.-)\"%s*,%s*desc%s*=%s*\"(.-)\"%s*,%s*block%s*=%s*([^%s\n]+)")
          if run and run ~= "" and block and (block == "true" or block == "false") then
            block = (block == "true")
            if interactive then
              local cmd_input, event = ya.input({
                title = "Shell command:",
                value = run,
                position = { "top-center", y = 3, w = 40 },
              })
              if event == 1 then
                DualPane:shell(self, cmd_input, block)
              end
            else
              DualPane:shell(self, run, block)
            end
          end
        end
      end
    end
  end
end

local function setup(state, opts)
  load_state(state)

  if opts and opts.enabled then
    DualPane:toggle()
  end
end

return {
  entry = entry,
  setup = setup,
}
