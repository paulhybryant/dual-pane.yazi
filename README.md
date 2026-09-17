# dual-pane.yazi

[dual-pane.yazi](https://github.com/dawsers/dual-pane.yazi) provides true dual-pane file management for [Yazi](https://github.com/sxyazi/yazi/), following the classic Dual Commander (Norton Commander, Midnight Commander, Total Commander) workflow.

## Features

- **True Dual Commander Architecture**: Manages two independent tabs (`Tab 1` and `Tab 2`) side-by-side with independent directory navigation, cursor positioning, and selection.
- **Clear Active Focus**: The inactive pane suppresses cursor highlight, making it immediately clear which pane is active.
- **Cross-Pane File Operations**:
  - `Y`: Copy selected or hovered file(s) from the active pane to the directory in the other pane.
  - `M`: Move selected or hovered file(s) from the active pane to the directory in the other pane.
- **Integrated Preview Panel**: Toggle a bottom preview panel on/off with `P` (or `b b`) without leaving dual-pane mode.
- **Dual Live Watching**: Directories in both panes are monitored simultaneously so file creations, deletions, and transfers appear immediately in both panes.
- **Clean Lifecycle**: Toggling off dual-pane mode cleanly tears down components, unhooks layout overrides, and restores standard single-pane Yazi layout.

## Requirements

- [Yazi](https://github.com/sxyazi/yazi/) v25+ / v26+ (tested and verified on Yazi 26.5.6+)

## Installation

### Local / Development (Recommended)

Clone the repository and symlink it to your Yazi plugins directory:

```sh
mkdir -p ~/src ~/.config/yazi/plugins
git clone https://github.com/dawsers/dual-pane.yazi.git ~/src/dual-pane.yazi
ln -s ~/src/dual-pane.yazi ~/.config/yazi/plugins/dual-pane.yazi
```

### Via Yazi Package Manager

```sh
ya pkg add dawsers/dual-pane
```

## Setup

Enable the plugin in your `~/.config/yazi/init.lua`:

```lua
require("dual-pane"):setup()
```

### Setup Options

- `enabled`: (boolean, default `false`) If `true`, dual-pane mode is activated automatically when Yazi starts.

```lua
require("dual-pane"):setup({
    enabled = true,
})
```

## Keybindings Configuration

Add keybindings to your `~/.config/yazi/keymap.toml` under the `[mgr]` section:

```toml
[mgr]
prepend_keymap = [
    { on = "\\",         run = "plugin dual-pane toggle",     desc = "Dual-pane: toggle dual-pane mode" },
    { on = [ "b", "t" ], run = "plugin dual-pane toggle",     desc = "Dual-pane: toggle dual-pane mode" },
    { on = "<Tab>",      run = "plugin dual-pane next_pane",  desc = "Dual-pane: switch active pane" },
    { on = "Y",          run = "plugin dual-pane copy_files", desc = "Dual-pane: copy to the other pane" },
    { on = "M",          run = "plugin dual-pane move_files", desc = "Dual-pane: move to the other pane" },
    { on = "P",          run = "plugin dual-pane preview",    desc = "Dual-pane: toggle preview pane" },
    { on = [ "b", "b" ], run = "plugin dual-pane preview",    desc = "Dual-pane: toggle preview pane" },
]
```

## Available Commands

| Command | Action Argument | Description |
|---|---|---|
| `toggle` | `plugin dual-pane toggle` | Toggle dual-pane mode on / off |
| `next_pane` | `plugin dual-pane next_pane` | Switch active focus between left and right panes |
| `copy_files` | `plugin dual-pane copy_files` | Copy selected or hovered file(s) to the other pane |
| `move_files` | `plugin dual-pane move_files` | Move selected or hovered file(s) to the other pane |
| `preview` | `plugin dual-pane preview` | Toggle the bottom preview panel |
| `activate` | `plugin dual-pane activate` | Explicitly activate dual-pane mode |
| `deactivate` | `plugin dual-pane deactivate` | Explicitly deactivate dual-pane mode |

## Workflow & Usage Guide

1. **Activate Dual-Pane**: Press `\` (or `b t`). Yazi splits into two equal panes side by side.
2. **Switch Panes**: Press `<Tab>` to switch active focus between the left and right pane.
3. **Navigate Independently**: Move through folders (`h`, `j`, `k`, `l`, `Enter`) independently in each pane.
4. **Copy Across Panes**: Select files (using visual selection or hover) in the active pane and press `Y`. The files are copied directly into the inactive pane's directory.
5. **Move Across Panes**: Select files in the active pane and press `M`. The files are moved directly into the inactive pane's directory.
6. **Preview Files**: Press `P` (or `b b`) to open or close the bottom preview panel.
7. **Exit Dual-Pane**: Press `\` (or `b t`) again to return to the standard single-pane layout.

## License

MIT
