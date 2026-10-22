# HyperMac Release & Distribution Guide

This guide explains how to create releases and distribute HyperMac to users.

## ✅ What's Ready

Your repository is **ready to build and distribute** right now! Here's what's in place:

### 1. Git & GitHub
- ✅ Working tree is clean (all changes committed)
- ✅ GitHub remote configured: `git@github.com:BarutSRB/HyperMac.git`
- ✅ README.md has comprehensive documentation for users
- ✅ CONTRIBUTING.md explains contribution process
- ✅ LICENSE.txt included (MIT License)

### 2. Build Infrastructure
- ✅ `build-release.sh` - Creates release builds (universal binaries: x86_64 + arm64)
- ✅ `build-debug.sh` - Creates debug builds for development
- ✅ Build scripts work even without separate documentation files
- ✅ Shell completion generation works
- ✅ Man page generation creates placeholders if needed

### 3. Distribution Methods Available
- ✅ ZIP file distribution (for direct download)
- ✅ Homebrew cask files auto-generated (need separate tap repo)
- ✅ Local installation script for testing (`install-from-sources.sh`)

## 🚀 Creating Your First Release

### Option A: Simple GitHub Release (Recommended for First Release)

This is the easiest way to get your project in users' hands:

1. **Test everything works:**
   ```bash
   ./run-tests.sh
   ```

2. **Build the release:**
   ```bash
   ./build-release.sh --build-version "0.1.0"
   ```

3. **Check the artifacts in `.release/`:**
   - `HyperMac-v0.1.0.zip` - This is what users will download!
   - `hypermac.rb` - Homebrew cask file (for later)
   - `HyperMac.app` - The app bundle
   - `hypermac` - The CLI binary

4. **Create a Git tag:**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0: Initial public release"
   git push origin v0.1.0
   ```

5. **Create GitHub Release:**
   - Go to https://github.com/BarutSRB/HyprSpace/releases/new
   - Choose tag: `v0.1.0`
   - Release title: `v0.1.0 - Initial Release`
   - Description: See template below
   - Attach: `HyperMac-v0.1.0.zip`
   - Click "Publish release"

### GitHub Release Description Template

```markdown
# HyperMac v0.1.0 - Initial Release

A Hyprland-inspired tiling window manager for macOS with a beautiful workspace bar.

## 🎉 First Public Release

This is the first public release of HyperMac! The window manager is functional and ready for daily use.

## 📦 Installation

### Download and Install

1. Download `HyperMac-v0.1.0.zip` below
2. Extract the zip file
3. Copy `HyperMac.app` to `/Applications/`
4. Copy `bin/hypermac` to `/usr/local/bin/`
5. Remove quarantine: `xattr -d com.apple.quarantine /Applications/HyperMac.app`
6. Launch HyperMac and grant Accessibility permissions

### Configuration

Copy the default config:
```bash
cp /Applications/HyperMac.app/Contents/Resources/default-config.toml ~/.hypermac.toml
```

## ✨ Features

- i3/Hyprland-style tiling window management
- Dwindle layout (binary tree-based tiling)
- Virtual workspaces (5 workspaces by default)
- Multi-monitor support
- Vim-style navigation (Alt+H/J/K/L)
- CLI interface with shell completion
- TOML-based configuration

## 📚 Documentation

See the [README](https://github.com/BarutSRB/HyprSpace#readme) for:
- Complete keybindings reference
- Configuration guide
- CLI commands
- Troubleshooting

## 🔧 Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permissions

## 🐛 Known Issues

- Sticky windows not yet supported
- Limited to 5 workspaces in default config

## 📝 Changelog

- Initial public release
- Dwindle layout implementation
- Workspace management with 5 workspaces
- Multi-monitor support
- Default configuration with Vim-style keybindings
```

## 📤 How Users Will Install

### Method 1: Direct Download (Available Now)

Users download the zip from GitHub releases:
```bash
# User steps:
cd ~/Downloads
unzip HyperMac-v0.1.0.zip
cp HyperMac-v0.1.0/HyperMac.app /Applications/
cp HyperMac-v0.1.0/bin/hypermac /usr/local/bin/
xattr -d com.apple.quarantine /Applications/HyperMac.app
xattr -d com.apple.quarantine /usr/local/bin/hypermac
```

### Method 2: Homebrew (Requires Setup - See Below)

Once you setup a Homebrew tap:
```bash
brew install --cask barutsrb/tap/hypermac
```

## 🍺 Setting Up Homebrew Distribution

To enable Homebrew installation, you need to create a separate tap repository:

### 1. Create Homebrew Tap Repository

```bash
# Create a new GitHub repository named: homebrew-tap
# URL will be: https://github.com/BarutSRB/homebrew-tap

# Clone it locally
cd ~/Projects  # or wherever you keep repos
git clone git@github.com:BarutSRB/homebrew-tap.git
cd homebrew-tap

# Create directory structure
mkdir -p Casks

# Copy the generated cask file
cp /path/to/HyperMac/.release/hypermac.rb Casks/hypermac.rb

# Commit and push
git add Casks/hypermac.rb
git commit -m "Add HyperMac cask"
git push
```

### 2. Update the Cask for GitHub Release

The auto-generated cask file will have a local file:// URL. You need to update it:

Edit `Casks/hypermac.rb` and change:
```ruby
url "file:///path/to/.release/HyperMac-v0.1.0.zip"
```

To:
```ruby
url "https://github.com/BarutSRB/HyprSpace/releases/download/v0.1.0/HyperMac-v0.1.0.zip"
```

**OR** use the automated script (after you've created the GitHub release):

```bash
cd /path/to/HyperMac
./script/build-brew-cask.sh \
    --cask-name hypermac \
    --zip-uri "https://github.com/BarutSRB/HyprSpace/releases/download/v0.1.0/HyperMac-v0.1.0.zip" \
    --build-version "0.1.0"

# This regenerates the .rb file with the correct URL
# Then copy it to your tap repo
cp .release/hypermac.rb ~/Projects/homebrew-tap/Casks/hypermac.rb
```

### 3. Users Can Now Install via Homebrew

```bash
brew tap barutsrb/tap
brew install --cask barutsrb/tap/hypermac
```

Or in one command:
```bash
brew install --cask barutsrb/tap/hypermac
```

## 🔄 Future Release Process

For subsequent releases (v0.2.0, v0.3.0, etc.):

### Automated Way (Recommended)

Use the provided publish script (requires tap and website repos):

```bash
./script/publish-release.sh \
    --build-version "0.2.0" \
    --cask-git-repo-path ~/Projects/homebrew-tap \
    --site-git-repo-path ~/Projects/BarutSRB.github.io
```

This script will:
1. Run all tests
2. Build the release
3. Create and push git tag
4. Open GitHub releases page for you
5. Wait for you to upload the zip
6. Generate Homebrew cask
7. Update your tap repository
8. Update your documentation website

### Manual Way

```bash
# 1. Test
./run-tests.sh

# 2. Build
./build-release.sh --build-version "0.2.0"

# 3. Tag and release on GitHub (same as before)
git tag -a v0.2.0 -m "Release v0.2.0"
git push origin v0.2.0

# 4. Create GitHub release, upload zip

# 5. Update Homebrew cask
./script/build-brew-cask.sh \
    --cask-name hypermac \
    --zip-uri "https://github.com/BarutSRB/HyprSpace/releases/download/v0.2.0/HyperMac-v0.2.0.zip" \
    --build-version "0.2.0"

# 6. Copy to tap repo and push
cp .release/hypermac.rb ~/Projects/homebrew-tap/Casks/hypermac.rb
cd ~/Projects/homebrew-tap
git add Casks/hypermac.rb
git commit -m "Update HyperMac to v0.2.0"
git push
```

## 📊 DMG Creation (Optional)

Currently, HyperMac only distributes via ZIP files. If you want to create a fancy DMG:

You'll need to create a script using tools like:
- `hdiutil create` (built into macOS)
- [create-dmg](https://github.com/create-dmg/create-dmg) (community tool)
- [DMG Canvas](https://www.araelium.com/dmgcanvas) (commercial GUI tool)

Example simple DMG creation:
```bash
#!/bin/bash
# script/build-dmg.sh
hdiutil create -volname "HyperMac" \
    -srcfolder .release/HyperMac.app \
    -ov -format UDZO \
    .release/HyperMac-v0.1.0.dmg
```

However, the ZIP method is fine for now since:
- Homebrew handles installation automatically
- Manual users can easily extract zips
- DMGs add complexity to the build process

## 🎯 Summary: What You Need to Do Next

### To Start Distributing Now:

1. ✅ **Commit the changes** (README.md, build-docs.sh)
   ```bash
   git add README.md build-docs.sh
   git commit -m "Add comprehensive documentation and fix build without docs"
   git push
   ```

2. 🚀 **Create your first release** (follow "Option A" above)
   - Run tests
   - Build release
   - Create tag
   - Create GitHub release
   - Upload zip

3. 📢 **Share with users**
   - Users can download the zip from GitHub releases
   - Point them to the README for installation instructions

### To Enable Homebrew (Optional, Later):

1. Create `homebrew-tap` repository on GitHub
2. Follow the "Setting Up Homebrew Distribution" section above
3. Update your README to mention Homebrew installation is available

### Repository Readiness: ✅ READY

Your repository is **fully ready** for users to:
- ✅ Clone and build from source
- ✅ Read comprehensive documentation
- ✅ Understand how to contribute
- ✅ Install from releases (once you create one)

The only thing missing for 100% easiest installation is the Homebrew tap, but that's optional and can be added later!

## 💡 Tips

- **Start with v0.1.0** for your first public release
- **Use semantic versioning**: MAJOR.MINOR.PATCH (e.g., 0.1.0, 0.2.0, 1.0.0)
- **Write good release notes** explaining what changed
- **Test on a clean macOS install** if possible (use a VM or friend's computer)
- **Announce on social media** when you release (Twitter/X, Reddit, Hacker News, etc.)

## 🔗 Useful Links

- Your project: https://github.com/BarutSRB/HyprSpace
- Creating releases: https://docs.github.com/en/repositories/releasing-projects-on-github
- Homebrew cask docs: https://docs.brew.sh/Cask-Cookbook
- Semantic versioning: https://semver.org/
