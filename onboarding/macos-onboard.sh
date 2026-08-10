#!/bin/bash
# VCSC macOS Onboarding Script

set -e

# Configuration
# Using Homebrew Casks (GUI Apps) and Formulae (CLI Tools)
casks=(
    "google-chrome"
    "visual-studio-code"
    "microsoft-office"
    "microsoft-teams"
    "slack"
    "zoom"
    "bitwarden"
    "docker" # Optional: if used
)

formulae=(
    "git"
    "wget"
    "python@3.12" # or specific version needed
)

echo "🚀 Starting VCSC macOS Onboarding..."

# 1. Install Homebrew if not present
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for current session (Apple Silicon vs Intel)
    if [[ "$(uname -m)" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew is already installed."
    brew update
fi

# 2. Install CLI Tools (Formulae)
echo "🛠️  Installing CLI tools..."
for formula in "${formulae[@]}"; do
    echo "Installing $formula..."
    brew install "$formula" || echo "Skipped $formula (might be installed or error)"
done

# 3. Install GUI Apps (Casks)
echo "🖥️  Installing Applications..."
for cask in "${casks[@]}"; do
    echo "Installing $cask..."
    brew install --cask "$cask" || echo "Skipped $cask (might be installed or error)"
done

# 4. System Configuration
echo "⚙️  Applying configurations..."

# Dock Configuration: Remove default icons, add specific ones (optional)
# defaults write com.apple.dock autohide -bool true
# killall Dock

# Disable "Are you sure you want to open this application?" dialog for downloaded apps
# defaults write com.apple.LaunchServices LSQuarantine -bool false

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

echo "🎉 Onboarding complete! You may need to restart apps to see all changes."