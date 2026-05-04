# setup-mac

Idempotent macOS setup script — installs apps, dotfiles, system preferences, and app config snapshots in one go. Skips anything already installed/configured. Tested on Apple Silicon.

## Install on a fresh Mac

```bash
curl -fsSL https://raw.githubusercontent.com/dantechguy/setup-mac/main/setup.sh | bash
```

Re-run any time; safe and idempotent. Pass `--force` to overwrite existing dotfiles and plist snapshots (a `.bak.<timestamp>` is left for dotfiles).

```bash
curl -fsSL https://raw.githubusercontent.com/dantechguy/setup-mac/main/setup.sh | bash -s -- --force
```

## What it sets up

- **CLI tools** (brew formulae): `gh`, `jj`, `borders`, `node`
- **GUI apps** (brew casks): AeroSpace, AltTab, Bruno, Claude, Docker Desktop, Fluor, Chrome, iTerm2, Raycast, Reflex, VS Code
- **VS Code extensions**
- **npm globals**: `@anthropic-ai/claude-code`, `@ranger-testing/ranger-cli`
- **Dotfiles**: `.zshrc`, `.gitconfig`, `.vimrc`, `.aerospace.toml`, JankyBorders config, global gitignore
- **macOS defaults**: Dock, Finder, fast key repeat, trackpad (tap-to-click + 3-finger drag), British-PC keyboard layout, Caps Lock → Escape
- **App config snapshots**: AltTab, Reflex, iTerm2 (via `PrefsCustomFolder` → `~/dotfiles/iterm`)

## What it can't do automatically

The script prints `→ TODO:` lines as it goes whenever it installs something that needs a manual follow-up — sign-ins, Accessibility permissions, `gh auth login`, SSH key generation, log out / restart. Scroll back through the run output to find them.
