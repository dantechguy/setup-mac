#!/usr/bin/env bash
# ~/setup-mac.sh — Dan's MacBook setup
#
# Idempotent: skips anything already installed/configured.
# Usage:
#   bash ~/setup-mac.sh             # install missing only
#   bash ~/setup-mac.sh --force     # also overwrite existing dotfiles (.bak left)

set -euo pipefail

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

[[ "$(uname)" == "Darwin" ]] || { echo "macOS only"; exit 1; }

# ---------- helpers ---------------------------------------------------------
c_b='\033[1;34m'; c_g='\033[1;32m'; c_y='\033[1;33m'; c_r='\033[1;31m'; c_x='\033[0m'
LAST_STEP="(initialization)"
step() { LAST_STEP="$*"; printf "\n${c_g}== %s ==${c_x}\n" "$*"; }
ok()   { printf "  ${c_g}✓${c_x} %s\n" "$*"; }
skip() { printf "  ${c_y}·${c_x} %s (already)\n" "$*"; }
warn() { printf "  ${c_y}!${c_x} %s\n" "$*"; }
err()  { printf "  ${c_r}✗${c_x} %s\n" "$*"; }
todo() { printf "  ${c_b}→${c_x} TODO: %s\n" "$*"; }

# On any unhandled failure, print where it broke before dying.
on_err() {
  local rc=$?
  printf "\n${c_r}✗ FAILED${c_x} during step: %s\n" "$LAST_STEP"
  printf "    line %s: %s\n"   "${BASH_LINENO[0]:-?}" "${BASH_COMMAND:-?}"
  printf "    exit code: %s\n" "$rc"
  exit "$rc"
}
trap on_err ERR

have()       { command -v "$1" >/dev/null 2>&1; }
brew_have()  { brew list --formula "$1" >/dev/null 2>&1; }
cask_have()  { brew list --cask "$1" >/dev/null 2>&1; }
tap_have()   { brew tap | grep -qx "$1"; }

# ---------- 1. Xcode Command Line Tools ------------------------------------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  skip "xcode-select"
else
  xcode-select --install || true
  echo "  Complete the install dialog, then re-run this script."
  exit 0
fi

# ---------- 2. Homebrew -----------------------------------------------------
step "Homebrew"
if have brew; then
  skip "brew"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ok "brew installed"
fi
# Make brew available in this shell regardless of arch
if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"
fi
have brew || { err "brew not on PATH"; exit 1; }

# ---------- 3. Taps ---------------------------------------------------------
step "Homebrew taps"
for tap in nikitabobko/tap felixkratz/formulae; do
  if tap_have "$tap"; then skip "tap $tap"; else brew tap "$tap" >/dev/null && ok "tap $tap"; fi
done

# ---------- 4. CLI tools ----------------------------------------------------
step "CLI tools (brew formulae)"
formulae=(
  gh                       # GitHub CLI
  jj                       # Jujutsu VCS
  borders                  # JankyBorders, used by AeroSpace
  node                     # Node.js + npm
)
for f in "${formulae[@]}"; do
  bare="${f##*/}"; bare="${bare%@*}"
  if brew_have "$f" || brew_have "$bare"; then
    skip "$f"
  else
    brew install "$f" >/dev/null && ok "$f"
    case "$f" in
      gh) todo "Run: gh auth login"
          todo "Generate SSH key: ssh-keygen -t ed25519 -C \"d@nielwb.com\""
          ;;
    esac
  fi
done

# ---------- 5. GUI apps -----------------------------------------------------
step "GUI apps (brew casks)"
casks=(
  aerospace                # tiling WM
  alt-tab                  # better cmd-tab
  bruno                    # API client
  claude                   # Claude desktop
  docker-desktop           # Docker
  fluor                    # per-app function-key behavior
  google-chrome
  iterm2                   # terminal
  raycast                  # launcher
  reflex-app               # Reflex
  visual-studio-code
)
for c in "${casks[@]}"; do
  if cask_have "$c"; then
    skip "$c"
  else
    brew install --cask "$c" >/dev/null && ok "$c"
    case "$c" in
      google-chrome|claude|raycast)
        todo "Sign in to $c"
        ;;
      aerospace)
        todo "Open AeroSpace once to start it (borders launches via after-startup-command)"
        todo "Grant Accessibility to AeroSpace (System Settings → Privacy → Accessibility)"
        ;;
      alt-tab|fluor)
        todo "Grant Accessibility to $c (System Settings → Privacy → Accessibility)"
        ;;
      iterm2)
        todo "Open iTerm so it picks up PrefsCustomFolder from \$HOME/dotfiles/iterm"
        ;;
    esac
  fi
done

# ---------- 6. npm globals --------------------------------------------------
step "npm globals"
if have npm; then
  installed_npm=$(npm ls -g --depth=0 --parseable 2>/dev/null || true)
  npm_globals=(
    @anthropic-ai/claude-code
    @ranger-testing/ranger-cli
  )
  for pkg in "${npm_globals[@]}"; do
    if echo "$installed_npm" | grep -q "/${pkg}\$\|/${pkg}/"; then
      skip "$pkg"
    else
      npm install -g "$pkg" >/dev/null && ok "$pkg"
    fi
  done
else
  warn "npm not on PATH; skipping npm globals"
fi

# ---------- 8. VS Code extensions ------------------------------------------
step "VS Code extensions"
CODE="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
if [[ -x "$CODE" ]]; then
  installed_ext=$("$CODE" --list-extensions 2>/dev/null || true)
  exts=(
    anthropic.claude-code
    github.copilot-chat
    k--kato.intellij-idea-keybindings
    ms-azuretools.vscode-containers
    ms-playwright.playwright
    ms-python.debugpy
    ms-python.python
    ms-python.vscode-pylance
    ms-python.vscode-python-envs
    ms-vscode-remote.remote-containers
    singularityinc.claude-notifier
    tamasfe.even-better-toml
    vscodevim.vim
  )
  for e in "${exts[@]}"; do
    if echo "$installed_ext" | grep -qix "$e"; then
      skip "$e"
    else
      "$CODE" --install-extension "$e" >/dev/null 2>&1 && ok "$e" || warn "$e (failed)"
    fi
  done
else
  warn "VS Code not installed; skipping extensions"
fi

# ---------- 9. Dotfiles -----------------------------------------------------
step "Dotfiles"
write_dotfile() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" && $FORCE -eq 0 ]]; then
    # If contents already match what we'd write, treat as already configured
    local tmp; tmp=$(mktemp); cat > "$tmp"
    if cmp -s "$tmp" "$target"; then
      rm -f "$tmp"; skip "$target"; return
    fi
    rm -f "$tmp"
    skip "$target (exists; use --force to overwrite)"
    return
  fi
  [[ -e "$target" ]] && cp "$target" "$target.bak.$(date +%s)"
  cat > "$target"
  ok "$target"
}

write_dotfile "$HOME/.zshrc" <<'EOF'
# Highlight input prompt
PROMPT='%B%F{blue}%~%f%b %B%F{red}%%%f%b %B'
POSTEDIT=$'\e[0m'

# brew
export PATH=/opt/homebrew/bin:$PATH

# shortcut for terminal tab renaming
function title {
    echo -ne "\033]0;"$*"\007"
}

# autocomplete
autoload -Uz compinit && compinit
command -v jj >/dev/null && source <(jj util completion zsh)
EOF

write_dotfile "$HOME/.gitconfig" <<'EOF'
[user]
	name = Dan Wendon-Blixrud
	email = d@nielwb.com
[credential "https://github.com"]
	helper =
	helper = !/opt/homebrew/bin/gh auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !/opt/homebrew/bin/gh auth git-credential
EOF

write_dotfile "$HOME/.config/git/ignore" <<'EOF'
**/.claude/settings.local.json
EOF

write_dotfile "$HOME/.config/borders/bordersrc" <<'EOF'
#!/bin/bash
options=(
	style=round
	width=8.0
	hidpi=off
	active_color=0xffff0f0f
	inactive_color=0xffffffff
	order=above
)
borders "${options[@]}"
EOF
chmod +x "$HOME/.config/borders/bordersrc" 2>/dev/null || true

write_dotfile "$HOME/.vimrc" <<'EOF'
set relativenumber
set nu
set ai
syntax on
set re=0

" Below 5 lines are for the vim-plug package manager
call plug#begin()
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'

" On-demand loading
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
call plug#end()

" Custom escape -- not needed atm because I have rebound CapsLock to Esc
" inoremap jk <Esc>
" inoremap kj <Esc>

" Make / and ? searches go in same direction with n and N
nnoremap <expr> n (v:searchforward ? 'n' : 'N')
nnoremap <expr> N (v:searchforward ? 'N' : 'n')
onoremap <expr> n (v:searchforward ? 'n' : 'N')
onoremap <expr> N (v:searchforward ? 'N' : 'n')
xnoremap <expr> n (v:searchforward ? 'n' : 'N')
xnoremap <expr> N (v:searchforward ? 'N' : 'n')

" Insert newlines without leaving normal mode
noremap Ø o<Esc>k<C-e>
noremap ø O<Esc>j<C-y>

" Add semicolon to end of line below
noremap … jA;<Esc>k$

noremap vv ^v$
EOF

write_dotfile "$HOME/.aerospace.toml" <<'EOF'
config-version = 2

after-startup-command = [
  'exec-and-forget borders'
]

start-at-login = true

enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
automatically-unhide-macos-hidden-apps = true

persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B",
                         "C", "D", "E", "F", "G", "I", "M", "N", "O", "P", "Q",
                         "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]

on-mode-changed = []

[key-mapping]
    preset = 'qwerty'

[gaps]
    inner.horizontal = 16
    inner.vertical =   16
    outer.left =       12
    outer.bottom =     12
    outer.top =        12
    outer.right =      12

[mode.main.binding]
    alt-slash = 'layout tiles horizontal vertical'
    alt-comma = 'layout accordion horizontal vertical'

    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'

    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'

    alt-minus = 'resize smart -50'
    alt-equal = 'resize smart +50'

    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-0 = 'workspace 0'
    alt-a = 'workspace A'
    alt-b = 'workspace B'
    alt-c = 'workspace C'
    alt-d = 'workspace D'
    alt-e = 'workspace E'
    alt-f = 'workspace F'
    alt-g = 'workspace G'
    alt-i = 'workspace I'
    alt-m = 'workspace M'
    alt-n = 'workspace N'
    alt-o = 'workspace O'
    alt-p = 'workspace P'
    alt-r = 'workspace R'
    alt-s = 'workspace S'
    alt-t = 'workspace T'
    alt-u = 'workspace U'
    alt-v = 'workspace V'
    alt-w = 'workspace W'
    alt-x = 'workspace X'
    alt-y = 'workspace Y'
    alt-z = 'workspace Z'

    alt-shift-1 = 'move-node-to-workspace 1'
    alt-shift-2 = 'move-node-to-workspace 2'
    alt-shift-3 = 'move-node-to-workspace 3'
    alt-shift-4 = 'move-node-to-workspace 4'
    alt-shift-5 = 'move-node-to-workspace 5'
    alt-shift-6 = 'move-node-to-workspace 6'
    alt-shift-7 = 'move-node-to-workspace 7'
    alt-shift-8 = 'move-node-to-workspace 8'
    alt-shift-9 = 'move-node-to-workspace 9'
    alt-shift-0 = 'move-node-to-workspace 0'
    alt-shift-a = 'move-node-to-workspace A'
    alt-shift-b = 'move-node-to-workspace B'
    alt-shift-c = 'move-node-to-workspace C'
    alt-shift-d = 'move-node-to-workspace D'
    alt-shift-e = 'move-node-to-workspace E'
    alt-shift-f = 'move-node-to-workspace F'
    alt-shift-g = 'move-node-to-workspace G'
    alt-shift-i = 'move-node-to-workspace I'
    alt-shift-m = 'move-node-to-workspace M'
    alt-shift-n = 'move-node-to-workspace N'
    alt-shift-o = 'move-node-to-workspace O'
    alt-shift-p = 'move-node-to-workspace P'
    alt-shift-r = 'move-node-to-workspace R'
    alt-shift-s = 'move-node-to-workspace S'
    alt-shift-t = 'move-node-to-workspace T'
    alt-shift-u = 'move-node-to-workspace U'
    alt-shift-v = 'move-node-to-workspace V'
    alt-shift-w = 'move-node-to-workspace W'
    alt-shift-x = 'move-node-to-workspace X'
    alt-shift-y = 'move-node-to-workspace Y'
    alt-shift-z = 'move-node-to-workspace Z'

    alt-tab = 'workspace-back-and-forth'
    alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

    alt-shift-semicolon = 'mode service'

    # Custom commands
    alt-shift-q = 'close'
    alt-shift-space = 'layout floating tiling'

[mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main']
    f = 'fullscreen'
    backspace = ['close-all-windows-but-current', 'mode main']

    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']

[workspace-to-monitor-force-assignment]
1 = 'main'
2 = 'main'
3 = 'main'
4 = 'main'
5 = 'main'
6 = 'secondary'
7 = 'secondary'
8 = 'secondary'
9 = 'secondary'
0 = 'secondary'

[[on-window-detected]]
if.app-id = 'com.apple.finder'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.systemsettings'
run = 'layout floating'
EOF

# ---------- 10. macOS defaults ---------------------------------------------
step "macOS defaults"

# --- Dock ---
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock tilesize -int 45
ok "Dock: autohide, magnification, tilesize=45"

# --- Finder ---
defaults write com.apple.finder FXPreferredViewStyle -string clmv     # column view
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
ok "Finder: column view, show external drives"

# --- Keyboard: fast key repeat ---
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
ok "Keyboard: fast repeat (15/2)"

# --- Trackpad: tap-to-click + three-finger drag (built-in + magic trackpad) ---
for d in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
  defaults write "$d" Clicking            -bool true
  defaults write "$d" TrackpadThreeFingerDrag -bool true
done
# Also flip the global tap-behavior flag so tap-to-click actually triggers
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults              write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
ok "Trackpad: tap-to-click, three-finger drag"

# --- Keyboard layout: British-PC (alongside British) ---
defaults write com.apple.HIToolbox AppleEnabledInputSources '(
    { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 2;   "KeyboardLayout Name" = British; },
    { "Bundle ID" = "com.apple.CharacterPaletteIM"; InputSourceKind = "Non Keyboard Input Method"; },
    { "Bundle ID" = "com.apple.PressAndHold";      InputSourceKind = "Non Keyboard Input Method"; },
    { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 250; "KeyboardLayout Name" = "British-PC"; }
)'
defaults write com.apple.HIToolbox AppleSelectedInputSources '(
    { "Bundle ID" = "com.apple.PressAndHold"; InputSourceKind = "Non Keyboard Input Method"; },
    { InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 250; "KeyboardLayout Name" = "British-PC"; }
)'
ok "Keyboard layout: British-PC"

# --- Caps Lock → Escape (system-wide modifier remap) ---
# Src 30064771129 = Caps Lock (HID 0x07/0x39); Dst 30064771113 = Escape (HID 0x07/0x29)
defaults -currentHost write -g com.apple.keyboard.modifiermapping.0-0-0 -array \
  '{ HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771113; }'
ok "Caps Lock → Escape"

# Apply (no-op if values unchanged)
killall Dock   2>/dev/null || true
killall Finder 2>/dev/null || true

todo "Log out (or restart) to apply keyboard layout, Caps→Esc, and trackpad defaults"

# ---------- 11. App configs (snapshots) ------------------------------------
# These embed binary plist snapshots from the source Mac. They're a one-time
# starting point; once the apps are launched they will rewrite their own prefs.
step "App configs"

install_plist_snapshot() {
  # $1 = domain (e.g. com.lwouis.alt-tab-macos)
  # stdin = base64-encoded binary plist
  local domain="$1"
  local target="$HOME/Library/Preferences/$domain.plist"
  if [[ -e "$target" && $FORCE -eq 0 ]]; then
    cat >/dev/null   # drain heredoc
    skip "$domain (use --force to overwrite)"
    return
  fi
  local tmp; tmp=$(mktemp)
  base64 -d > "$tmp"
  if ! plutil -lint "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; warn "$domain: invalid plist data, skipping"; return
  fi
  defaults import "$domain" "$tmp"
  rm -f "$tmp"
  ok "$domain"
}

# --- AltTab ---
install_plist_snapshot com.lwouis.alt-tab-macos <<'PLIST_B64'
YnBsaXN0MDDfEBMBAgMEBQYHCAkKCwwNDg8QERITFBUWFxgUGhscFB4jFBwmFCgpLV8QLE1TQXBw
Q2VudGVyMzEwQ3Jhc2hlc1VzZXJEZWZhdWx0c01pZ3JhdGVkS2V5XxAScHJlZmVyZW5jZXNWZXJz
aW9uXxAgc2V0dGluZ3NXaW5kb3dTaG93bk9uRmlyc3RMYXVuY2hfEBZNU0FwcENlbnRlclBhc3RE
ZXZpY2VzXHVwZGF0ZVBvbGljeV8QE1NVSGFzTGF1bmNoZWRCZWZvcmVfEA9TVUxhc3RDaGVja1Rp
bWVfEBhNU0FwcENlbnRlclVzZXJJZEhpc3RvcnlfEBVTVUF1dG9tYXRpY2FsbHlVcGRhdGVfEC5N
U0FwcENlbnRlcjMxMEFwcENlbnRlclVzZXJEZWZhdWx0c01pZ3JhdGVkS2V5XGhvbGRTaG9ydGN1
dF8QFE1TQXBwQ2VudGVySW5zdGFsbElkXxAXU1VFbmFibGVBdXRvbWF0aWNDaGVja3NfECFNU0Fw
cENlbnRlck5ldHdvcmtSZXF1ZXN0c0FsbG93ZWRfEB1OU1dpbmRvdyBGcmFtZSBTZXR0aW5nc1dp
bmRvd18QJU1TQXBwQ2VudGVyQXBwRGlkUmVjZWl2ZU1lbW9yeVdhcm5pbmdfEBtNU0FwcENlbnRl
clNlc3Npb25JZEhpc3RvcnldaG9sZFNob3J0Y3V0Ml8QIE5TV2luZG93IEZyYW1lIFBlcm1pc3Np
b25zV2luZG93CVcxMC4xMi4wVHRydWVPEQR5YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFy
Y2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBUL
DBIYHCJQUVJTVFVWV1hZWltcYWZVJG51bGzSDQ4PEVpOUy5vYmplY3RzViRjbGFzc6EQgAKAFNMT
FA4VFhdcdGltZXN0YW1wS2V5WWRldmljZUtleYADgAWAE9IZDhobV05TLnRpbWUjQcfPsIWMS2+A
BNIdHh8gWiRjbGFzc25hbWVYJGNsYXNzZXNWTlNEYXRloh8hWE5TT2JqZWN03xAXIyQlJg4nKCkq
KywtLi8wMTIzNDU2Nzg5Ojs8PTs8PEFCPDw8PEdISUo8PE1OT1lvc1ZlcnNpb25edGltZVpvbmVP
ZmZzZXRYYXBwQnVpbGRfEBVsaXZlVXBkYXRlUGFja2FnZUhhc2haYXBwVmVyc2lvbl8QEXdyYXBw
ZXJTZGtWZXJzaW9uW2NhcnJpZXJOYW1lV3Nka05hbWVWbG9jYWxlXxAXbGl2ZVVwZGF0ZURlcGxv
eW1lbnRLZXleY2FycmllckNvdW50cnlab3NBcGlMZXZlbF53cmFwcGVyU2RrTmFtZVdvZW1OYW1l
WnNka1ZlcnNpb25cYXBwTmFtZXNwYWNlVW1vZGVsXxAVd3JhcHBlclJ1bnRpbWVWZXJzaW9uXxAW
bGl2ZVVwZGF0ZVJlbGVhc2VMYWJlbFpzY3JlZW5TaXplVm9zTmFtZVdvc0J1aWxkgAuADoAQgACA
EoAQgACAAIAGgA2AAIAAgACAAIAJgAeAEYAIgACAAIAPgAqADF8QD2FwcGNlbnRlci5tYWNvc1U0
LjMuMFdNYWMxNyw4VUFwcGxlVW1hY09TVjI2LjQuMVYyNUUyNTNVZW5fR0IQPFkzNDQweDE0NDBX
MTAuMTIuMF8QGGNvbS5sd291aXMuYWx0LXRhYi1tYWNvc9IdHl1eWk1TQUNEZXZpY2WjX2AhWk1T
QUNEZXZpY2VeTVNBQ1dyYXBwZXJTZGvSHR5iY18QFU1TQUNEZXZpY2VIaXN0b3J5SW5mb6NkZSFf
EBVNU0FDRGV2aWNlSGlzdG9yeUluZm9fEA9NU0FDSGlzdG9yeUluZm/SHR5naF5OU011dGFibGVB
cnJheaNnaSFXTlNBcnJheQAIABEAGgAkACkAMgA3AEkATABRAFMAawBxAHYAgQCIAIoAjACOAJUA
ogCsAK4AsACyALcAvwDIAMoAzwDaAOMA6gDtAPYBJwExAUABSQFhAWwBgAGMAZQBmwG1AcQBzwHe
AeYB8QH+AgQCHAI1AkACRwJPAlECUwJVAlcCWQJbAl0CXwJhAmMCZQJnAmkCawJtAm8CcQJzAnUC
dwJ5AnsCfQKPApUCnQKjAqkCsAK3Ar0CvwLJAtEC7ALxAvwDAAMLAxoDHwM3AzsDUwNlA2oDeQN9
AAAAAAAAAgEAAAAAAAAAagAAAAAAAAAAAAAAAAAAA4VRMQkzQcfPsIj+C5pPEQHHYnBsaXN0MDDU
AQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRB
cmNoaXZlctEICVRyb290gAGnCwwSGBwiJ1UkbnVsbNINDg8RWk5TLm9iamVjdHNWJGNsYXNzoRCA
AoAG0xMUDhUWF1x0aW1lc3RhbXBLZXlZdXNlcklkS2V5gAOAAIAF0hkOGhtXTlMudGltZSNBx8+w
hYsW9IAE0h0eHyBaJGNsYXNzbmFtZVgkY2xhc3Nlc1ZOU0RhdGWiHyFYTlNPYmplY3TSHR4jJF8Q
FU1TQUNVc2VySWRIaXN0b3J5SW5mb6MlJiFfEBVNU0FDVXNlcklkSGlzdG9yeUluZm9fEA9NU0FD
SGlzdG9yeUluZm/SHR4oKV5OU011dGFibGVBcnJheaMoKiFXTlNBcnJheQAIABEAGgAkACkAMgA3
AEkATABRAFMAWwBhAGYAcQB4AHoAfAB+AIUAkgCcAJ4AoACiAKcArwC4ALoAvwDKANMA2gDdAOYA
6wEDAQcBHwExATYBRQFJAAAAAAAAAgEAAAAAAAAAKwAAAAAAAAAAAAAAAAAAAVEICdIfICEiVnN0
cmluZ1pzZWN1cmVEYXRhYSMYTxEBZWJwbGlzdDAw1AECAwQFBgcKWCR2ZXJzaW9uWSRhcmNoaXZl
clQkdG9wWCRvYmplY3RzEgABhqBfEA9OU0tleWVkQXJjaGl2ZXLRCAlUcm9vdIABpgsMGRobHFUk
bnVsbNYNDg8QERITFBUUFxhdbW9kaWZpZXJGbGFnc18QG2NoYXJhY3RlcnNJZ25vcmluZ01vZGlm
aWVyc1YkY2xhc3NaY2hhcmFjdGVyc1drZXlDb2RlV3ZlcnNpb26ABIAAgAWAAIADgAJRMRH//xIA
EAAA0h0eHyBaJGNsYXNzbmFtZVgkY2xhc3Nlc1pTUlNob3J0Y3V0oh8hWE5TT2JqZWN0AAgAEQAa
ACQAKQAyADcASQBMAFEAUwBaAGAAbQB7AJkAoACrALMAuwC9AL8AwQDDAMUAxwDJAMwA0QDWAOEA
6gD1APgAAAAAAAACAQAAAAAAAAAiAAAAAAAAAAAAAAAAAAABAV8QJDgxQkQ5MkUxLUNBMzMtNDIz
Ni05NTM5LTE3RjRENTcyNjM3RAkIXxAmLTE3MSAxNDk4IDkxOCA1MzQgLTkxMCAxMTE3IDM0NDAg
MTQxMCAJTxEBzGJwbGlzdDAw1AECAwQFBgcKWCR2ZXJzaW9uWSRhcmNoaXZlclQkdG9wWCRvYmpl
Y3RzEgABhqBfEA9OU0tleWVkQXJjaGl2ZXLRCAlUcm9vdIABpwsMEhgcIidVJG51bGzSDQ4PEVpO
Uy5vYmplY3RzViRjbGFzc6EQgAKABtMTFA4VFhdcdGltZXN0YW1wS2V5XHNlc3Npb25JZEtleYAD
gACABdIZDhobV05TLnRpbWUjQcfPsIWLDdCABNIdHh8gWiRjbGFzc25hbWVYJGNsYXNzZXNWTlNE
YXRloh8hWE5TT2JqZWN00h0eIyRfEBZNU0FDU2Vzc2lvbkhpc3RvcnlJbmZvoyUmIV8QFk1TQUNT
ZXNzaW9uSGlzdG9yeUluZm9fEA9NU0FDSGlzdG9yeUluZm/SHR4oKV5OU011dGFibGVBcnJheaMo
KiFXTlNBcnJheQAIABEAGgAkACkAMgA3AEkATABRAFMAWwBhAGYAcQB4AHoAfAB+AIUAkgCfAKEA
owClAKoAsgC7AL0AwgDNANYA3QDgAOkA7gEHAQsBJAE2ATsBSgFOAAAAAAAAAgEAAAAAAAAAKwAA
AAAAAAAAAAAAAAAAAVbSHyorLFpzZWN1cmVEYXRhYSMYTxEBZWJwbGlzdDAw1AECAwQFBgcKWCR2
ZXJzaW9uWSRhcmNoaXZlclQkdG9wWCRvYmplY3RzEgABhqBfEA9OU0tleWVkQXJjaGl2ZXLRCAlU
cm9vdIABpgsMGRobHFUkbnVsbNYNDg8QERITFBUUFxhdbW9kaWZpZXJGbGFnc18QG2NoYXJhY3Rl
cnNJZ25vcmluZ01vZGlmaWVyc1YkY2xhc3NaY2hhcmFjdGVyc1drZXlDb2RlV3ZlcnNpb26ABIAA
gAWAAIADgAJRMRH//xIAEAAA0h0eHyBaJGNsYXNzbmFtZVgkY2xhc3Nlc1pTUlNob3J0Y3V0oh8h
WE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBaAGAAbQB7AJkAoACrALMAuwC9AL8AwQDD
AMUAxwDJAMwA0QDWAOEA6gD1APgAAAAAAAACAQAAAAAAAAAiAAAAAAAAAAAAAAAAAAABAV8QJTU0
OSAxODYzIDUyMSA0MTUgLTkxMCAxMTE3IDM0NDAgMTQxMCAACAAxAGAAdQCYALEAvgDUAOYBAQEZ
AUoBVwFuAYgBrAHMAfQCEgIgAkMCRAJMAlEGzgbQBtEG2gilCKYIpwisCLMIvgjBCioKUQpSClMK
fAp9DE0MUgxdDGANyQAAAAAAAAIBAAAAAAAAAC4AAAAAAAAAAAAAAAAAAA3x
PLIST_B64

# --- Reflex (Stunt Software) ---
install_plist_snapshot com.stuntsoftware.Reflex <<'PLIST_B64'
YnBsaXN0MDDVAQIDBAUGBwgJCl8QD1NVTGFzdENoZWNrVGltZV8QJk5TU3RhdHVzSXRlbSBQcmVm
ZXJyZWQgUG9zaXRpb24gSXRlbS0wXxATU1VIYXNMYXVuY2hlZEJlZm9yZV8QF1NVVXBkYXRlR3Jv
dXBJZGVudGlmaWVyXxAUa1ByZWZlcmVuY2VzTXVzaWNBcHAzQcfSb8RJL5AiQ6AAAAkSrPj/M18Q
EmNvbS5zcG90aWZ5LmNsaWVudAgTJU5kfpWeo6SpAAAAAAAAAQEAAAAAAAAACwAAAAAAAAAAAAAA
AAAAAL4=
PLIST_B64

# --- iTerm2: prefs-folder approach ---
# Drop a snapshot into ~/dotfiles/iterm and tell iTerm to load from there.
ITERM_DIR="$HOME/dotfiles/iterm"
ITERM_PLIST="$ITERM_DIR/com.googlecode.iterm2.plist"
mkdir -p "$ITERM_DIR"
if [[ -e "$ITERM_PLIST" && $FORCE -eq 0 ]]; then
  skip "$ITERM_PLIST (use --force to overwrite)"
else
  base64 -d > "$ITERM_PLIST" <<'PLIST_B64'
YnBsaXN0MDDfEEMAAQACAAMABAAFAAYABwAIAAkACgALAAwADQAOAA8AEAARABIAEwAUABUAFgAX
ABgAGQAaABsAHAAdAB4AHwAgACEAIgAjACQAJQAmACcAKAApACoAKwAsAC0ALgAvADAAMQAyADMA
NAA1ADYANwA4ADkAOgA7ADwAPQA+AD8AQABBAEIAQwBEAEUARgNrA24A9QBEAPUARANzA3QDdQSu
BK8EsASxATwA9QD1AEQCigS1A/MEugBFBM0EzgBEAooE0AD1AEQCigBEBNQA9QBFBNYE2ATNBNkA
9QTeBN8A9QKKBOEA9QTjBOQARATmBOcE6ATpAEQE6wD1APUE7gTwATwARAD1AEQE9AD1XxAjTm9T
eW5jSWdub3JlU3lzdGVtV2luZG93UmVzdG9yYXRpb25fEBlOb1N5bmNSZXN0b3JlV2luZG93c0Nv
dW50XU5ldyBCb29rbWFya3NfEDBOU1NwbGl0VmlldyBTdWJ2aWV3IEZyYW1lcyBOU0NvbG9yUGFu
ZWxTcGxpdFZpZXdfEBVEZWZhdWx0IEJvb2ttYXJrIEd1aWRbU291bmRGb3JFc2NfEBlBSUZlYXR1
cmVIb3N0ZWRGaWxlU2VhcmNoXxArTlNPdmVybGF5U2Nyb2xsZXJzRmFsbEJhY2tGb3JBY2Nlc3Nv
cnlWaWV3c18QH0hvdGtleU1pZ3JhdGVkRnJvbVNpbmdsZVRvTXVsdGlfEBxOU1dpbmRvdyBGcmFt
ZSBTVVVwZGF0ZUFsZXJ0XxAUTm9TeW5jSW5zdGFsbGF0aW9uSWRfEBdOb1N5bmNSZWNvcmRlZFZh
cmlhYmxlc1lTVUZlZWRVUkxfEBlTVUZlZWRBbHRlcm5hdGVBcHBOYW1lS2V5W0FpTWF4VG9rZW5z
XxAXTm9TeW5jTmV4dEFubm95YW5jZVRpbWVfEBhOU1F1b3RlZEtleXN0cm9rZUJpbmRpbmdfEBVW
aXN1YWxJbmRpY2F0b3JGb3JFc2NfEBhBcHBsZVByZXNzQW5kSG9sZEVuYWJsZWRfEBhBSUZlYXR1
cmVIb3N0ZWRXZWJTZWFyY2hfEBpBcHBsZUFudGlBbGlhc2luZ1RocmVzaG9sZF8QHU5vU3luY0Zy
YW1lX1NoYXJlZFByZWZlcmVuY2VzWUFJVGVybUFQSV5Qb2ludGVyQWN0aW9uc11BSVZlY3RvclN0
b3JlXWlUZXJtIFZlcnNpb25fEBNBaVJlc3BvbnNlTWF4VG9rZW5zXxATTm9TeW5jQnJvd3NlclVw
c2VsbF8QIU5vU3luY1JlbW92ZURlcHJlY2F0ZWRLZXlNYXBwaW5nc18QE05vU3luY0xhc3RPU1Zl
cnNpb25fECVOb1N5bmNXaW5kb3dSZXN0b3Jlc1dvcmtzcGFjZUF0TGF1bmNoXxAbQUlGZWF0dXJl
U3RyZWFtaW5nUmVzcG9uc2VzXxAdTm9TeW5jQnJvd3NlclVwc2VsbF9zZWxlY3Rpb25fEBdTVUVu
YWJsZUF1dG9tYXRpY0NoZWNrc18QD1NVTGFzdENoZWNrVGltZV8QGU5vU3luY1Blcm1pc3Npb25U
b1Nob3dUaXBfEBtBcHBsZVNjcm9sbEFuaW1hdGlvbkVuYWJsZWRfEC5OU1Rvb2xiYXIgQ29uZmln
dXJhdGlvbiBjb20uYXBwbGUuTlNDb2xvclBhbmVsXxAbTlNXaW5kb3cgRnJhbWUgTlNDb2xvclBh
bmVsXxAlTm9TeW5jUGVybWlzc2lvbnNIZWxwZXJfQWNjZXNzaWJpbGl0eV8QGk5vU3luY1NhdmVk
V2luZG93UG9zaXRpb25zXxAlTlNTY3JvbGxWaWV3U2hvdWxkU2Nyb2xsVW5kZXJUaXRsZWJhcl8Q
HU5TV2luZG93IEZyYW1lIGlUZXJtIFdpbmRvdyAwV0FpTW9kZWxfEBRIYXB0aWNGZWVkYmFja0Zv
ckVzY18QIkFwcGxlU21vb3RoRml4ZWRGb250c1NpemVUaHJlc2hvbGRfEB1OU1dpbmRvdyBGcmFt
ZSBpVGVybSBXaW5kb3cgMV8QEVNVU2VuZFByb2ZpbGVJbmZvXxAcTlNXaW5kb3cgRnJhbWUgUHJv
ZmlsZXNQYW5lbF8QHU5TV2luZG93IEZyYW1lIGlUZXJtIFdpbmRvdyAyXxAdQUlGZWF0dXJlSG9z
dGVkQ29kZUludGVycGV0ZXJfEBZBcHBsZVdpbmRvd1RhYmJpbmdNb2RlWUFpdGVybVVSTF8QF1NV
VXBkYXRlR3JvdXBJZGVudGlmaWVyXxAoTm9TeW5jTGFzdFN5c3RlbVB5dGhvblZlcnNpb25SZXF1
aXJlbWVudF8QE1NVSGFzTGF1bmNoZWRCZWZvcmVfEChOb1N5bmNMYXVuY2hFeHBlcmllbmNlQ29u
dHJvbGxlclJ1bkNvdW50XxAZU1VVcGRhdGVSZWxhdW5jaGluZ01hcmtlcl8QGE5TU2Nyb2xsQW5p
bWF0aW9uRW5hYmxlZF8QFE5vU3luY0FsbEFwcFZlcnNpb25zXxAcTlNXaW5kb3cgRnJhbWUgU1VT
dGF0dXNGcmFtZV8QFE5TUmVwZWF0Q291bnRCaW5kaW5nXxAYQUlGZWF0dXJlRnVuY3Rpb25DYWxs
aW5nXxAkTlNBdXRvRmlsbEhldXJpc3RpY0NvbnRyb2xsZXJFbmFibGVkXxAUU2hvd0Z1bGxTY3Jl
ZW5UYWJCYXJfECVOb1N5bmNUaXBPZlRoZURheUVsaWdpYmlsaXR5QmVnYW5UaW1lXxAoUHJldmVu
dEVzY2FwZVNlcXVlbmNlRnJvbUNsZWFyaW5nSGlzdG9yeQkQAKIARwIb3xB/AEgASQBKAEsATABN
AE4ATwBQAFEAUgBTAFQAVQBWAFcAWABZAFoAWwBcAF0AXgBfAGAAYQBiAGMAZABlAGYAZwBoAGkA
agBrAGwAbQBuAG8AcABxAHIAcwB0AHUAdgB3AHgAeQB6AHsAfAB9AH4AfwCAAIEAggCDAIQAhQCG
AIcAiACJAIoAiwCMAI0AjgCPAJAAkQCSAJMAlACVAJYAlwCYAJkAmgCbAJwAnQCeAJ8AoAChAKIA
owCkAKUApgCnAKgAqQCqAKsArACtAK4ArwCwALEAsgCzALQAtQC2ALcAuAC5ALoAuwC8AL0AvgC/
AMAAwQDCAMMAxADFAMYAxwDSANQA1wDbAEQA4ADkAOgA7ADtAEUA8QD1APYA9wD4APsARAEZARoB
GwEeASIBJQEpAPUBKwEsAS8BMAEyAPUARQE3AEUARAD1ATwBPQE+AUEA9QFHAUoBTwFUANAARABE
AVcBWgFbAVoBXwFjAWcA9QBEAWwBcAF1AXkARAF+AYIBhgGKAYsA9QGQAYoA1QDQAZQBlwGZAZ0B
ogBFAaYBqgGsAa0BsQGyAPUBtgG7AbwBvwHDAccBywHMAc8BWgHUAEQBPABEAdcB2AE8AdsARAHg
AeQBywD1AecB6wHvAfIB8wD1AEQB9wH7AfwCAAIEAggCDAIQAhMCF18QFEFuc2kgNyBDb2xvciAo
TGlnaHQpXxAVQW5zaSAxNSBDb2xvciAoTGlnaHQpXxAUQW5zaSAyIENvbG9yIChMaWdodClaQm9s
ZCBDb2xvcl8QE0Fuc2kgMSBDb2xvciAoRGFyaylfEA9Vc2UgQnJpZ2h0IEJvbGRfEBRBbnNpIDkg
Q29sb3IgKExpZ2h0KV8QE0Fuc2kgOCBDb2xvciAoRGFyaylfEBBCYWNrZ3JvdW5kIENvbG9yV0Nv
bHVtbnNcQW5zaSA4IENvbG9yXxAWUmlnaHQgT3B0aW9uIEtleSBTZW5kc18QFEFuc2kgNCBDb2xv
ciAoTGlnaHQpXxAPQmxpbmtpbmcgQ3Vyc29yXxAbU2VsZWN0ZWQgVGV4dCBDb2xvciAoTGlnaHQp
XxAaU2VsZWN0ZWQgVGV4dCBDb2xvciAoRGFyaylfEBNBbnNpIDMgQ29sb3IgKERhcmspXEtleWJv
YXJkIE1hcFtWaXN1YWwgQmVsbF8QEUN1cnNvciBUZXh0IENvbG9yXxAQU2Nyb2xsYmFjayBMaW5l
c18QF1NlbGVjdGlvbiBDb2xvciAoTGlnaHQpXEFuc2kgMCBDb2xvcl8QFUFuc2kgMTEgQ29sb3Ig
KExpZ2h0KV8QE0Fuc2kgNSBDb2xvciAoRGFyaylfEBlDdXJzb3IgVGV4dCBDb2xvciAoTGlnaHQp
XFNpbGVuY2UgQmVsbFRSb3dzXxAUQW5zaSAxNCBDb2xvciAoRGFyaylUR3VpZF8QFEFuc2kgMTUg
Q29sb3IgKERhcmspXxATQW5zaSAwIENvbG9yIChEYXJrKV8QFkFtYmlndW91cyBEb3VibGUgV2lk
dGhfEBBPcHRpb24gS2V5IFNlbmRzXEFuc2kgMyBDb2xvcltXaW5kb3cgVHlwZVhCTSBHcm93bF8Q
F1Byb21wdCBCZWZvcmUgQ2xvc2luZyAyV0NvbW1hbmRfEBNTZWxlY3RlZCBUZXh0IENvbG9yXxAV
QW5zaSAxNCBDb2xvciAoTGlnaHQpXxAZQ3Vyc29yIEd1aWRlIENvbG9yIChEYXJrKV8QE1NlbmQg
Q29kZSBXaGVuIElkbGVcQW5zaSA2IENvbG9yXkpvYnMgdG8gSWdub3JlXxASQmFkZ2UgQ29sb3Ig
KERhcmspXEN1cnNvciBDb2xvcl8QEFZlcnRpY2FsIFNwYWNpbmdfEBdEaXNhYmxlIFdpbmRvdyBS
ZXNpemluZ18QFUNsb3NlIFNlc3Npb25zIE9uIEVuZF8QFlNlbGVjdGlvbiBDb2xvciAoRGFyaylf
EBBEZWZhdWx0IEJvb2ttYXJrXxAYRm9yZWdyb3VuZCBDb2xvciAoTGlnaHQpXkN1c3RvbSBDb21t
YW5kXxAXQmFja2dyb3VuZCBDb2xvciAoRGFyaylcQW5zaSA5IENvbG9yXUFuc2kgMTQgQ29sb3Jd
Rmxhc2hpbmcgQmVsbF8QD1VzZSBJdGFsaWMgRm9udF8QFEFuc2kgMTMgQ29sb3IgKERhcmspXxAa
Q3Vyc29yIEd1aWRlIENvbG9yIChMaWdodCldQW5zaSAxMiBDb2xvcl8QFUFuc2kgMTAgQ29sb3Ig
KExpZ2h0KV8QFk5vbi1BU0NJSSBBbnRpIEFsaWFzZWRdQW5zaSAxMCBDb2xvcl8QEEZvcmVncm91
bmQgQ29sb3JfEBJMaW5rIENvbG9yIChMaWdodClbRGVzY3JpcHRpb25fEBNBbnNpIDcgQ29sb3Ig
KERhcmspWlN5bmMgVGl0bGVcQW5zaSAxIENvbG9yVE5hbWVcVHJhbnNwYXJlbmN5XxASSG9yaXpv
bnRhbCBTcGFjaW5nXxATQ3Vyc29yIENvbG9yIChEYXJrKV8QE0Fuc2kgMiBDb2xvciAoRGFyaylf
EBNBbnNpIDkgQ29sb3IgKERhcmspW0JhZGdlIENvbG9yXxAVQW5zaSAxMyBDb2xvciAoTGlnaHQp
WUlkbGUgQ29kZVxBbnNpIDQgQ29sb3JfEBFCb2xkIENvbG9yIChEYXJrKVZTY3JlZW5fEBNBbnNp
IDQgQ29sb3IgKERhcmspXxAYQ3Vyc29yIFRleHQgQ29sb3IgKERhcmspXxAPU2VsZWN0aW9uIENv
bG9yXxASVXNlIE5vbi1BU0NJSSBGb250XxATQmFkZ2UgQ29sb3IgKExpZ2h0KV8QEkNoYXJhY3Rl
ciBFbmNvZGluZ18QFEFuc2kgMTEgQ29sb3IgKERhcmspXxASQm9sZCBDb2xvciAoTGlnaHQpXxAU
QW5zaSAxMiBDb2xvciAoRGFyaylcQW5zaSA3IENvbG9yXk5vbiBBc2NpaSBGb250XxATQW5zaSA2
IENvbG9yIChEYXJrKV8QEkN1cnNvciBHdWlkZSBDb2xvcl8QEEN1c3RvbSBEaXJlY3RvcnlfEBFX
b3JraW5nIERpcmVjdG9yeV8QEkFTQ0lJIEFudGkgQWxpYXNlZFhTaG9ydGN1dF8QD01vdXNlIFJl
cG9ydGluZ1RUYWdzXxAUQW5zaSA2IENvbG9yIChMaWdodClfEBlCYWNrZ3JvdW5kIEltYWdlIExv
Y2F0aW9uXxAUQW5zaSAxIENvbG9yIChMaWdodCldVXNlIEJvbGQgRm9udF8QFEFuc2kgOCBDb2xv
ciAoTGlnaHQpXEFuc2kgMiBDb2xvcltOb3JtYWwgRm9udF8QFFVubGltaXRlZCBTY3JvbGxiYWNr
XxAVQW5zaSAxMiBDb2xvciAoTGlnaHQpXxAUQW5zaSAxMCBDb2xvciAoRGFyaylfEBRBbnNpIDMg
Q29sb3IgKExpZ2h0KV8QFEN1cnNvciBDb2xvciAoTGlnaHQpXUFuc2kgMTUgQ29sb3JUQmx1cl8Q
K1VzZSBTZXBhcmF0ZSBDb2xvcnMgZm9yIExpZ2h0IGFuZCBEYXJrIE1vZGVfEBhCYWNrZ3JvdW5k
IENvbG9yIChMaWdodCldVGVybWluYWwgVHlwZV1BbnNpIDEzIENvbG9yXxAUQW5zaSA1IENvbG9y
IChMaWdodClfEBdGb3JlZ3JvdW5kIENvbG9yIChEYXJrKVpMaW5rIENvbG9yXxARTGluayBDb2xv
ciAoRGFyayldQW5zaSAxMSBDb2xvclxBbnNpIDUgQ29sb3JfEBRBbnNpIDAgQ29sb3IgKExpZ2h0
KdUAyADJAMoAywDMAM0AzgDPANAA0V1SZWQgQ29tcG9uZW50W0NvbG9yIFNwYWNlXkJsdWUgQ29t
cG9uZW50XxAPQWxwaGEgQ29tcG9uZW50XxAPR3JlZW4gQ29tcG9uZW50Iz/o/kcgAAAAVHNSR0Ij
P+j+WQAAAAAjP/AAAAAAAAAjP+j+beAAAADVAMgAyQDKAMsAzADTAM4A0ADQANAjP+//96AAAADV
AMgAyQDKAMsAzADVAM4A1QDQANYjAAAAAAAAAAAjP+hYWGAAAADVAMgAyQDKAMsAzADYAM4A2QDQ
ANojP7AQECAAAAAjP7AQECAAAAAjP7AQECAAAADVAMgAyQDKAMsAzADcAM4A3QDQAN4jP+ajYAAA
AAAjP8TdMkAAAAAjP85I7oAAAAAJ1QDIAMkAygDLAMwA4QDOAOIA0ADjIz/rteAAAAAAIz/dVVDA
AAAAIz/ealhAAAAA1QDIAMkAygDLAMwA5QDOAOYA0ADnIz/aGa8AAAAAIz/aGcMAAAAAIz/aGdog
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
AAAAIz/OSO6AAAAACdUAyADJAMoAywDMAeEAzgHiANAB4yM/2hmvAAAAACM/2hnDAAAAACM/2hna
IAAAANUAyADJAMoAywDMANUAzgDVANAB5SM/6FhYYAAAAAjVAMgAyQDKAMsAzAHoAM4B6QDQAeoj
P+TpZYAAAAAjP+5aYAAAAAAjP+V0TaAAAADVAMgAyQDKAMsAzAHsAM4B7QDQAe4jP9YUmGAAAAAj
P+IX6mAAAAAjP+zv4AAAAADVAMgAyQDKAMsAzAHwAM4A1QDQAfEjP+j6kIAAAAAjP+ighWAAAADV
AMgAyQDKAMsAzADVAM4A1QDQANXVAMgAyQDKAMsAzAH0AM4A0ADQANAjP+//96AAAAAICdUAyADJ
AMoAywDMAfgAzgH5ANAB+iM/71wo9cKPXCM/71wo9cKPXCM/71wo9cKPXF54dGVybS0yNTZjb2xv
ctUAyADJAMoAywDMAf0AzgH+ANAB/yM/7DqgAAAAACM/7DqgAAAAACM/34jVYAAAANUAyADJAMoA
ywDMAgEAzgICANACAyM/6BIAAAAAACM/59aUAAAAACM/z+mdQAAAANUAyADJAMoAywDMAgUAzgIG
ANACByM/65VVQAAAACM/65VpAAAAACM/65WAAAAAANUAyADJAMoAywDMAgkAzgIKANACCyM/yVjb
oAAAACM/7eEAAAAAACM/4dpNoAAAANUAyADJAMoAywDMAg0AzgIOANACDyM/yVjboAAAACM/7eEA
AAAAACM/4dpNoAAAANUAyADJAMoAywDMAhEAzgDVANACEiM/7aEAAAAAACM/7EShAAAAANUAyADJ
AMoAywDMAhQAzgIVANACFiM/6BIAAAAAACM/59aUAAAAACM/z+mdQAAAANUAyADJAMoAywDMAhgA
zgIZANACGiM/tBQUIAAAACM/vh4eIAAAACM/uRkZIAAAAN8QjgBIAEkASgBLAEwATQBOAE8AUABR
AFIAUwBUAFUCHABWAh0AVwIeAFgAWQBaAFsAXABdAF4AXwBgAGEAYgBjAGUAZABmAGcAaABpAh8A
agBrAiAAbABtAG4AbwBwAiEAcQByAHMAdAB1AHYAdwIiAHgAeQB6AiMCJAB8AH0AfgB/AIAAgQCC
AIMAhACFAIYCJQCHAIgAiQCKAIsAjACNAI4AjwCQAJEAkgCTAJQAlQCWAJcCJgCYAJkAmgCbAJwA
nQCeAJ8AoAChAicAogCjAKQApQCmAigApwCoAKkAqgIpAKsArACtAK4AsACxALIAswC0ALUAtgC3
ALgAuQC6ALsAvAIqAisAvQC+AL8CLADAAMEAwgDDAMQAxQDGAi0CMQIzAjUCOQBEAj4CQgJGAOwC
SgBFAk4A9QD1AlQBrAJVAEUCVgJZAEQCawBFAmwCbwJzAnYCegD1ASsCfAJ9AoACggD1AEUARQKH
AooARQBEAPUBPAKNAo4A9QKSAPUCmAKbApwCoQDQAqIARABEAqUBWgD1AqkBWgKtArECtQD1AEQC
ugK+AsMCxwBEAEQCzQLRAtUBigLZAPUC3gLiANUA0ALjAuYC6ALsAvEARQELAvUC+QKKAvsC/wMA
APUDBAG7AwkDDAMNAxEDFQHLAxkA9QMdAVoB1ABEAPUBPABEAyUDJgMpAEQDLgMyAcsARAM1AzkD
PQNAA0EA9QBEA0UDRgNHAfsDSwBEA1ADVANYA1wDYANjA2daSGFzIEhvdGtleVVTcGFjZV8QFUhv
dEtleSBNb2RpZmllciBGbGFnc18QGkhvdEtleSBNb2RpZmllciBBY3RpdmF0aW9uXxAfSG90S2V5
IFdpbmRvdyBEb2NrIENsaWNrIEFjdGlvbl8QI0hvdEtleSBXaW5kb3cgUmVvcGVucyBPbiBBY3Rp
dmF0aW9uW0JvdW5kIEhvc3RzXxAQRGVmYXVsdCBCb29rbWFya18QHEhvdEtleSBBY3RpdmF0ZWQg
QnkgTW9kaWZpZXJfEBRIb3RLZXkgV2luZG93IEZsb2F0c18QD0hvdEtleSBLZXkgQ29kZV8QGkhv
dEtleSBBbHRlcm5hdGUgU2hvcnRjdXRzXxAWSG90S2V5IFdpbmRvdyBBbmltYXRlc18QF0hvdEtl
eSBXaW5kb3cgQXV0b0hpZGVzXxAkSG90S2V5IENoYXJhY3RlcnMgSWdub3JpbmcgTW9kaWZpZXJz
XxARSG90S2V5IENoYXJhY3RlcnNfEBhJbml0aWFsIFVzZSBUcmFuc3BhcmVuY3nVAMgAyQDKAMsA
zAIuAM4CLwDQAjAjP+j+RyAAAAAjP+j+WQAAAAAjP+j+beAAAADVAMgAyQDKAMsAzAIyAM4A0ADQ
ANAjP+//96AAAADVAMgAyQDKAMsAzADVAM4A1QDQAjQjP+hYWGAAAADVAMgAyQDKAMsAzAI2AM4C
NwDQAjgjP7AQECAAAAAjP7AQECAAAAAjP7AQECAAAADVAMgAyQDKAMsAzAI6AM4COwDQAjwjP+aj
YAAAAAAjP8TdMkAAAAAjP85I7oAAAAAJ1QDIAMkAygDLAMwCPwDOAkAA0AJBIz/rteAAAAAAIz/d
VVDAAAAAIz/ealhAAAAA1QDIAMkAygDLAMwCQwDOAkQA0AJFIz/aGa8AAAAAIz/aGcMAAAAAIz/a
GdogAAAA1QDIAMkAygDLAMwCRwDOAkgA0AJJIz/vXCj1wo9cIz/vXCj1wo9cIz/vXCj1wo9c1QDI
AMkAygDLAMwCSwDOAkwA0AJNIz/aGa8AAAAAIz/aGcMAAAAAIz/aGdogAAAA1QDIAMkAygDLAMwC
TwDOAlAA0AJRIz/Dt65gAAAAIz/pB3ggAAAAIz/Q8Y8AAAAACAjVAMgAyQDKAMsAzADVAM4A1QDQ
ANXVAMgAyQDKAMsAzADVAM4A1QDQANXVAMgAyQDKAMsAzAJXAM4A1QDQAlgjP+j6kIAAAAAjP+ig
hWAAAADYAloCWwJcAl0CXgJfAmACYQJiAmMCZAJlAmYCZwJoAmlcMHg3Zi0weDgwMDAwXxAPMHhm
NzAyLTB4MjgwMDAwXxAPMHhmNzAyLTB4MzAwMDAwXjB4ZjcyOC0weDgwMDAwXTB4N2YtMHgxMDAw
MDBfEA8weGY3MDMtMHgyODAwMDBfEA8weGY3MDMtMHgzMDAwMDBaMHhmNzI4LTB4MNIBBQEGAQcB
CNIBBQEGAQoBC9IBBQEGAQ0BCNIBBQEGAQ8BC9IBBQEGAREBCNIBBQEGARMBC9IBBQEGARUBCNIB
BQEGARcBCAnVAMgAyQDKAMsAzADQAM4A0ADQANDVAMgAyQDKAMsAzAJtAM4A0ADQAm4jP+Z2doAA
AAAjP+r6+wAAAADVAMgAyQDKAMsAzAJwAM4CcQDQAnIjP7QUFCAAAAAjP74eHiAAAAAjP7kZGSAA
AADVAMgAyQDKAMsAzAJ0AM4A1QDQAnUjP+2hAAAAAAAjP+xEoQAAAADVAMgAyQDKAMsAzAJ3AM4C
eADQAnkjP+gSAAAAAAAjP+fWlAAAAAAjP8/pnUAAAADVAMgAyQDKAMsAzADQAM4A0ADQANAIXxAk
Q0REMTEwMTEtRUJBNS00RDYwLUFFRjktMERBNjQ0OURFNDZF1QDIAMkAygDLAMwCfgDOANAA0AJ/
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
QzQtRjVGNjMwMUY0RDc5CAkICV8QHjU1NCA1MTEgNjIwIDQwMiAwIDAgMTcyOCAxMDg0IF8QJDNB
MjhDQzgzLTA4N0UtNDEzNC05NUVELUY4QTUxRDE5OEFCNNUDdgN3A3gDeQN6A3sEFQRiBGsEq1Ex
UjE2UTRRMlEwrxAyA3wDggOFA4gDiwOOA5EDlAOXA5oDnQOgA6MDpgOpA6wDrwOyA7UDuAO7A74D
wQPEA8cDyQPMA88D0gPVA9gD2wPeA+ED5APnA+oD7QPwA/QD9wP6A/0EAAQDBAYECQQMBA8EEtMD
fQN+A38DgABEAEVUbmFtZVppc1Rlcm1pbmFsXxASbm9udGVybWluYWxDb250ZXh0XxAQcHJlc2Vu
dGF0aW9uTmFtZQnTA30DfgN/A4MARABFWHRtdXhSb2xlCdMDfQN+A38DhgBEAEVbbGFzdENvbW1h
bmQJ0wN9A34DfwOJAEQARVtwcm9maWxlTmFtZQnTA30DfgN/A4wARABFXxAWc2hvd2luZ0FsdGVy
bmF0ZVNjcmVlbgnTA30DfgN/A48ARABFUmlkCdMDfQN+A38DkgBEAEVWdGVybWlkCdMDfQN+A38D
lQBEAEVdaG9tZURpcmVjdG9yeQnTA30DfgN/A5gARABFV2pvYk5hbWUJ0wN9A34DfwObAEQARVdj
b2x1bW5zCdMDfQN+A38DngBEAEVVdW5hbWUJ0wN9A34DfwOhAEQARV8QE3RhYi50bXV4V2luZG93
VGl0bGUJ0wN9A34DfwOkAEQARVxwcm9jZXNzVGl0bGUJ0wN9A34DfwOnAEQARV50bXV4Q2xpZW50
TmFtZQnTA30DfgN/A6oARABFWGhvc3RuYW1lCdMDfQN+A38DrQBEAEVfEA9zZWxlY3Rpb25MZW5n
dGgJ0wN9A34DfwOwAEQARVltb3VzZUluZm8J0wN9A34DfwOzAEQARVRwYXRoCdMDfQN+A38DtgBE
AEVVc2hlbGwJ0wN9A34DfwO5AEQARVt0cmlnZ2VyTmFtZQnTA30DfgN/A7wA9QKKXXBhcmVudFNl
c3Npb24I0wN9A34DfwO/AEQARV8QEHRlcm1pbmFsSWNvbk5hbWUJ0wN9A34DfwPCAEQARV50bXV4
V2luZG93UGFuZQnTA30DfgN/A8UARABFXxASbW91c2VSZXBvcnRpbmdNb2RlCdMDfQN+A38DfQBE
AEUJ0wN9A34DfwPKAEQARV8QD3RtdXhTdGF0dXNSaWdodAnTA30DfgN/A80A9QG7Vml0ZXJtMgjT
A30DfgN/A9AARABFXXRtdXhQYW5lVGl0bGUJ0wN9A34DfwPTAEQARVRyb3dzCdMDfQN+A38D1gBE
AEVfEBN0bXV4V2luZG93UGFuZUluZGV4CdMDfQN+A38D2QBEAEVTdHR5CdMDfQN+A38D3ABEAEVZ
YXV0b0xvZ0lkCdMDfQN+A38D3wBEAEVVYmFkZ2UJ0wN9A34DfwPiAEQARVh1c2VybmFtZQnTA30D
fgN/A+UARABFW2xvZ0ZpbGVuYW1lCdMDfQN+A38D6ABEAEVfEBJlZmZlY3RpdmVfcm9vdF9waWQJ
0wN9A34DfwPrAEQARV8QE3NzaEludGVncmF0aW9uTGV2ZWwJ0wN9A34DfwPuAEQARV8QEnRhYi50
bXV4V2luZG93TmFtZQnTA30DfgN/A/EA9QPzU3RhYggQAtMDfQN+A38D9QBEAEVedG11eFN0YXR1
c0xlZnQJ0wN9A34DfwP4AEQARVlzZWxlY3Rpb24J0wN9A34DfwP7AEQARVliZWxsQ291bnQJ0wN9
A34DfwP+AEQARV5hdXRvTmFtZUZvcm1hdAnTA30DfgN/BAEARABFWGF1dG9OYW1lCdMDfQN+A38E
BABEAEVfEBJ0ZXJtaW5hbFdpbmRvd05hbWUJ0wN9A34DfwQHAEQARV8QEmNyZWF0aW9uVGltZVN0
cmluZwnTA30DfgN/BAoARABFW2NvbW1hbmRMaW5lCdMDfQN+A38EDQBEAEVfEBFhcHBsaWNhdGlv
bktleXBhZAnTA30DfgN/BBAARABFVmpvYlBpZAnTA30DfgN/BBMARABFU3BpZAmvEBoEFgQZBBwE
HwQiBCUEKAQrBC4EMQQ0BDcEOgQ8BD8EQgRFBEgESwROBFEEVARXBFkEXARf0wN9A34DfwQXAEQA
RVVzdHlsZQnTA30DfgN/BBoARABFVWZyYW1lCdMDfQN+A38EHQBEAEVfEB1jdXJyZW50VGFiLmN1
cnJlbnRTZXNzaW9uLnBpZAnTA30DfgN/BCAARABFXxAgY3VycmVudFRhYi5jdXJyZW50U2Vzc2lv
bi50ZXJtaWQJ0wN9A34DfwQjAEQARV8QI2N1cnJlbnRUYWIuY3VycmVudFNlc3Npb24ubW91c2VJ
bmZvCdMDfQN+A38EJgBEAEVfECxjdXJyZW50VGFiLmN1cnJlbnRTZXNzaW9uLnRlcm1pbmFsV2lu
ZG93TmFtZQnTA30DfgN/BCkARABFXxAqY3VycmVudFRhYi5jdXJyZW50U2Vzc2lvbi50ZXJtaW5h
bEljb25OYW1lCdMDfQN+A38ELABEAEVeaXNIb3RrZXlXaW5kb3cJ0wN9A34DfwQvAPUD81pjdXJy
ZW50VGFiCNMDfQN+A38EMgBEAEVfECZjdXJyZW50VGFiLmN1cnJlbnRTZXNzaW9uLnByb2Nlc3NU
aXRsZQnTA30DfgN/BDUARABFXxAZY3VycmVudFRhYi5jdXJyZW50U2Vzc2lvbgnTA30DfgN/BDgA
RABFXxARY3VycmVudFRhYi53aW5kb3cJ0wN9A34DfwOPAEQARQnTA30DfgN/BD0ARABFXxAeY3Vy
cmVudFRhYi5jdXJyZW50U2Vzc2lvbi5uYW1lCdMDfQN+A38EQABEAEVddGl0bGVPdmVycmlkZQnT
A30DfgN/BEMARABFVm51bWJlcgnTA30DfgN/BEYARABFXxAlY3VycmVudFRhYi5jdXJyZW50U2Vz
c2lvbi5jb21tYW5kTGluZQnTA30DfgN/BEkARABFXxAsY3VycmVudFRhYi5jdXJyZW50U2Vzc2lv
bi5lZmZlY3RpdmVfcm9vdF9waWQJ0wN9A34DfwRMAEQARV8QImN1cnJlbnRUYWIuY3VycmVudFNl
c3Npb24uaG9zdG5hbWUJ0wN9A34DfwRPAEQARV8QHmN1cnJlbnRUYWIuY3VycmVudFNlc3Npb24u
cGF0aAnTA30DfgN/BFIARABFXxAdY3VycmVudFRhYi5jdXJyZW50U2Vzc2lvbi50dHkJ0wN9A34D
fwRVAEQARV8QImN1cnJlbnRUYWIuY3VycmVudFNlc3Npb24udXNlcm5hbWUJ0wN9A34DfwPNAPUB
uwjTA30DfgN/BFoARABFXxATdGl0bGVPdmVycmlkZUZvcm1hdAnTA30DfgN/BF0ARABFXxAjY3Vy
cmVudFRhYi5jdXJyZW50U2Vzc2lvbi5iZWxsQ291bnQJ0wN9A34DfwRgAEQARV8QIWN1cnJlbnRU
YWIuY3VycmVudFNlc3Npb24uam9iTmFtZQmjBGMEZQRo0wN9A34DfwQTAEQARQnTA30DfgN/BGYA
RABFXWxvY2FsaG9zdE5hbWUJ0wN9A34DfwRpAEQARV5lZmZlY3RpdmVUaGVtZQmvEBcEbARvBHIE
dAR3BHoEfQSBBIQEhwSKBI0EjwSRBJMElgSZBJsEnQSgBKMEpgSp0wN9A34DfwRtAEQARV8QGmN1
cnJlbnRTZXNzaW9uLmNvbW1hbmRMaW5lCdMDfQN+A38EcAD1AopVdGl0bGUI0wN9A34DfwRwAEQA
RQnTA30DfgN/BHUARABFXxAPdG11eFdpbmRvd1RpdGxlCdMDfQN+A38EeABEAEVfECFjdXJyZW50
U2Vzc2lvbi5lZmZlY3RpdmVfcm9vdF9waWQJ0wN9A34DfwR7AEQARV50bXV4V2luZG93TmFtZQnT
A30DfgN/BH4A9QSAVndpbmRvdwgQENMDfQN+A38EggBEAEVfEBJjdXJyZW50U2Vzc2lvbi50dHkJ
0wN9A34DfwSFAEQARV8QFmN1cnJlbnRTZXNzaW9uLmpvYk5hbWUJ0wN9A34DfwSIAEQARV8QE2N1
cnJlbnRTZXNzaW9uLm5hbWUJ0wN9A34DfwSLAEQARV8QG2N1cnJlbnRTZXNzaW9uLnByb2Nlc3NU
aXRsZQnTA30DfgN/BH4ARABFCdMDfQN+A38DjwBEAEUJ0wN9A34DfwRAAEQARQnTA30DfgN/BJQA
RABFXxAXY3VycmVudFNlc3Npb24udXNlcm5hbWUJ0wN9A34DfwSXAEQARV8QFWN1cnJlbnRTZXNz
aW9uLnRlcm1pZAnTA30DfgN/A80A9QG7CNMDfQN+A38EWgBEAEUJ0wN9A34DfwSeAEQARV8QF2N1
cnJlbnRTZXNzaW9uLmhvc3RuYW1lCdMDfQN+A38EoQBEAEVfEBJjdXJyZW50U2Vzc2lvbi5waWQJ
0wN9A34DfwSkAEQARVp0bXV4V2luZG93CdMDfQN+A38EpwD1AopeY3VycmVudFNlc3Npb24I0wN9
A34DfwSnAEQARQmhBKzTA30DfgN/ATwARABFCV8QNWh0dHBzOi8vaXRlcm0yLmNvbS9hcHBjYXN0
cy9maW5hbF9tb2Rlcm4ueG1sP3NoYXJkPTcxVWlUZXJtEgAGGoAjQcfMZDIGZBMICAnSBLYEtwS4
BLlXdG9wTGVmdFtzY3JlZW5GcmFtZVt7MTI1OCwgOTgwfV8QFnt7MCwgMH0sIHszNDQwLCAxNDQw
fX3WBLsEvAS9BL4EvwTABMEEwwTFBMcEyQTLXxAeR2VzdHVyZSxUaHJlZUZpbmdlclN3aXBlRG93
biwsXxAcR2VzdHVyZSxUaHJlZUZpbmdlclN3aXBlVXAsLFxCdXR0b24sMSwxLCxfEB5HZXN0dXJl
LFRocmVlRmluZ2VyU3dpcGVMZWZ0LCxfEB9HZXN0dXJlLFRocmVlRmluZ2VyU3dpcGVSaWdodCws
XEJ1dHRvbiwyLDEsLNEBBgTCXxAYa1ByZXZXaW5kb3dQb2ludGVyQWN0aW9u0QEGBMRfEBhrTmV4
dFdpbmRvd1BvaW50ZXJBY3Rpb27RAQYExl8QGWtDb250ZXh0TWVudVBvaW50ZXJBY3Rpb27RAQYE
yF8QFWtQcmV2VGFiUG9pbnRlckFjdGlvbtEBBgTKXxAVa05leHRUYWJQb2ludGVyQWN0aW9u0QEG
BMxfECBrUGFzdGVGcm9tQ2xpcGJvYXJkUG9pbnRlckFjdGlvblYzLjYuMTASAAH0AAlfEB1WZXJz
aW9uIDI2LjQuMSAoQnVpbGQgMjVFMjUzKQgJCTNBx9JVOyC9RQjRBNcCiltUQiBJcyBTaG93bl8Q
GzAgODMgMjUwIDI5NyAwIDAgMzQ0MCAxNDEwINMDegN2A3kE2gTbBNxYezkxMCwgMH1cezExNDYs
IDE0MTB9XHsxNzIwLCAxNDEwfQhfECg5MTAgLTExMTcgMTcyOCAxMTE3IDkxMCAtMTExNyAxNzI4
IDEwODUgV2dwdC01LjIIXxAfMTE0NiAxIDExNDcgMTQwOSAwIDAgMzQ0MCAxNDEwIAhfECYtNjEw
IDE1OTAgNzM1IDM5MiAtOTEwIDExMTcgMzQ0MCAxNDEwIF8QHzE3MjAgMSAxNzIwIDE0MDkgMCAw
IDM0NDAgMTQxMCAJVm1hbnVhbF8QI2h0dHBzOi8vYXBpLm9wZW5haS5jb20vdjEvcmVzcG9uc2Vz
EvmMim1UMS4xNwkQAwgIogTvBM1VMy42LjlfEB42NjQgNzA4IDQwMCAxMzkgMCAwIDE3MjggMTA4
NCAJCAkjQce9T8RtOPgIAAgBFwE9AVkBZwGaAbIBvgHaAggCKgJJAmACegKEAqACrALGAuEC+QMU
Ay8DTANsA3YDhQOTA6EDtwPNA/EEBwQvBE0EbQSHBJkEtQTTBQQFIgVKBWcFjwWvBbcFzgXzBhMG
JwZGBmYGhgafBqkGwwbuBwQHLwdLB2YHfQecB7MHzgf1CAwINAhfCGAIYghnCmYKfQqVCqwKtwrN
Ct8K9gsMCx8LJws0C00LZAt2C5QLsQvHC9QL4Av0DAcMIQwuDEYMXAx4DIUMigyhDKYMvQzTDOwM
/w0MDRgNIQ07DUMNWQ1xDY0Now2wDb8N1A3hDfQODg4mDj8OUg5tDnwOlg6jDrEOvw7RDugPBQ8T
DysPRA9SD2UPeg+GD5wPpw+0D7kPxg/bD/EQBxAdECkQQRBLEFgQbBBzEIkQpBC2EMsQ4RD2EQ0R
IhE5EUYRVRFrEYARkxGnEbwRxRHXEdwR8xIPEiYSNBJLElgSZBJ7EpMSqhLBEtgS5hLrExkTNBNC
E1ATZxOBE4wToBOuE7sT0hPnE/UUARQQFCIUNBQ9FEIUSxRUFF0UchR7FJAUmRSiFLcUwBTJFNIU
5xTwFPkVAhUDFRgVIRUqFTMVSBVRFVoVYxV4FYEVihWTFZUVqhWzFbwVxRXaFeMV7BX1FfYWCxYg
FjUWPhZHFmgWdRaHFpkWqBa2FsgW2hblFu4W8xb6FwQXBhcPFxEXExccFyAXKRcrFzQXORdCF0QX
TRdRF1oXXhdfF3QXdxeMF5UXnhezF7wXxRfOF+MX7Bf1GAoYExgcGCUYOhg7GD0YUhhbGGQYixig
GKkYvhjHGNAY2RjaGO8Y+BkBGQIZAxkEGRkZLhk3GUAZVRleGWcZcBl5GXoZjxmYGaEZqhmxGbUZ
vBnDGdgZ4RnqGfMZ/BoRGhIaExooGjEaOho9GlIaWxpkGm0aghqLGpQanRqyGrsaxBrNGuIa6xr0
GvUa9hsLGxQbHRsmGzsbRBtNG1YbXxt0G30bhhuPG6QbrRu2G78bwBvVG94b5xvwHAUcDhwXHCAc
NRw+HEccUBxYHG0cdhx/HIgciRyeHKccsBy5HM4c1xzgHPUc/h0THRwdJR0uHUMdTB1VHV4dZx18
HYUdjh2XHawdtR2+Hccd3B3lHe4eAx4MHhUeHh4zHkgeUR5aHlsecB55HoIeix6UHpYeqx60Hr0e
0h7bHuQe7R8CHwsfFB8dHzIfOx9EH00fVx9sH3Uffh+TH5wfpR+uH7cfwh/DH8QfxR/aH+Mf7CAB
IAogEyAcIB0gMiA7IEQgTSBiIGsgbCCBIIogkyCcILEguiDDIMwg4SDqIPMhCCEdISYhJyEoIT0h
RiFPIVghZyF8IYUhjiGXIawhtSG+Icch3CHlIe4h9yIMIhUiHiInIjwiRSJOIlcibCJ1In4ikyKc
IqUiriLDIswi1SLeJRklJCUqJUIlXyWBJaclsyXGJeUl/CYOJismRCZeJoUmmSa0Jskm0ibbJuQm
+ScCJxcnICc1Jz4nRydQJ2Unbid3J4AngSeWJ58nqCexJ8YnzyfYJ+En9if/KAgoESgmKC8oOChB
KFYoXyhoKHEocihzKIgonSiyKLsoxCjlKPIpBCkWKSUpMylFKVcpYilrKXQpfSmGKY8pmCmhKaop
qynAKdUp3innKfwqBSoOKhcqLCo1Kj4qUypcKmUqbiqDKoQqqyrAKskq0irnKvArBSsOKxcrICsh
KzYrPytIK0orSytMK2Erdit/K4griSueK6crsCu5K8IrwyvYK+Er6ivzLAgsESwaLCMsLCxBLEIs
QyxELFksYixrLGwsgSyKLJMsnCyxLLoswyzMLOEs6izzLPwtES0aLSMtJC0lLTotQy1MLVUtai1z
LXwthS2OLaMtrC21Lb4t0y3cLeUt7i3vLfAuBS4OLhcuIC41Lj4uRy5QLmUubi53LoAulS6eLqcu
sC6xLsYuzy7YLuEu6C79LwYvDy8kLy0vQi9LL1QvXS9yL3svhC+NL5Yvqy+0L70vxi/bL+Qv7S/2
MAswFDApMDIwOzBEMFkwbjB3MIAwgTCWMJ8wqDCxMLowzzDYMOEw4jD3MQAxCTESMScxMDE5MUIx
VzFgMWkxcjGHMZAxmTGaMa8xuDHBMcox0zHUMdUx1jHXMewx9TH+MhMyHDIlMi4yLzJEMk0yVjJf
MnQyfTJ+MpMynDKlMq4ywzLMMtUy3jLzMvwzBTMaMy8zODM5MzozPTNAM1UzXjNnM3AzhTOOM5cz
oDOhM7YzvzPIM9Ez5jPvM/g0ATQWNB80KDQxNEY0TzRYNGE0djR/NIg0nTSmNK80uDTNNNY03zTo
NO01IjVYNX81gDWBNYI1gzWkNcs14DXiNeU15zXpNes2UjZfNmQ2bzaENpc2mDalNq42rza8Nsg2
yTbWNuI24zbwNwk3CjcXNxo3GzcoNy83MDc9N0s3TDdZN2E3YjdvN3c3eDeFN4s3jDeZN683sDe9
N8o3yzfYN+c36Df1N/43/zgMOB44HzgsODY4NzhEOEk4SjhXOF04XjhrOHc4eDiFOJM4lDihOLQ4
tTjCONE40jjfOPQ49TkCOQM5EDkiOSM5MDk3OTg5RTlTOVQ5YTlmOWc5dDmKOYs5mDmcOZ05qjm0
ObU5wjnIOck51jnfOeA57Tn5Ofo6BzocOh06KjpAOkE6TjpjOmQ6cTp1OnY6eDqFOpQ6lTqiOqw6
rTq6OsQ6xTrSOuE64jrvOvg6+TsGOxs7HDspOz47PztMO1g7WTtmO3o7ezuIO487kDudO6E7ojvZ
O+Y77DvtO/o8ADwBPA48LjwvPDw8XzxgPG08kzyUPKE80DzRPN49Cz0MPRk9KD0pPTY9QT1CPU89
eD15PYY9oj2jPbA9xD3FPdI90z3gPgE+Aj4PPh0+Hj4rPjI+Mz5APmg+aT52PqU+pj6zPtg+2T7m
Pwc/CD8VPzU/Nj9DP2g/aT92P3c/hD+aP5s/qD/OP88/3EAAQAFACEAVQBZAI0AxQDJAP0BOQE9A
gECNQKpAq0C4QL5Av0DMQM1A2kDsQO1A+kEeQR9BLEE7QTxBSUFQQVFBU0FgQXVBdkGDQZxBnUGq
QcBBwUHOQexB7UH6QftCCEIJQhZCF0IkQj5CP0JMQmRCZUJyQnNCgEKBQo5CqEKpQrZCy0LMQtlC
5ELlQvJDAUMCQw9DEEMTQyBDIUNZQ19DZENtQ25Db0NwQ3lDgUONQ5lDskPLQ+xEC0QYRDlEW0Ro
RG1EiESNRKhErUTJRM5E5kTrRQNFCEUrRTJFN0U4RVhFWUVaRVtFZEVlRWpFdkWURaFFqkW3RcRF
xUXwRfhF+UYbRhxGRUZnRmhGb0aVRppGn0agRqJGo0akRqlGr0bQRtFG0kbTRtwAAAAAAAACAgAA
AAAAAAT2AAAAAAAAAAAAAAAAAABG3Q==
PLIST_B64
  if plutil -lint "$ITERM_PLIST" >/dev/null 2>&1; then
    ok "$ITERM_PLIST"
  else
    rm -f "$ITERM_PLIST"; warn "iTerm plist invalid, skipped"
  fi
fi
defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ITERM_DIR"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
ok "iTerm: load prefs from $ITERM_DIR"
todo "Quit and reopen iTerm so it loads prefs from $ITERM_DIR"
todo "Quit AltTab/Reflex before re-running with --force, or imports won't stick"

# ---------- 12. Login items / launch agents --------------------------------
step "Launch at login"
if [[ -d /Applications/AeroSpace.app ]]; then
  ok "AeroSpace: start-at-login=true is set in ~/.aerospace.toml"
fi

# ---------- done ------------------------------------------------------------
printf "\n${c_g}All done.${c_x} Any TODOs above are manual follow-ups; scroll back to find them.\n"
