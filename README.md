<p align="center">
  <img src="Brewster/Assets.xcassets/AppIcon.appiconset/icon-128.png" alt="Brewster Icon" width="128" height="128">
</p>

<h1 align="center">Brewster</h1>

<p align="center">
  <em>A lightweight macOS menu bar app for monitoring Homebrew updates</em>
</p>

<p align="center">
  <a href="https://github.com/shmoopi/Brewster/releases"><img src="https://img.shields.io/github/v/release/shmoopi/Brewster" alt="Release"></a>
  <a href="https://github.com/shmoopi/Brewster/blob/main/LICENSE"><img src="https://img.shields.io/github/license/shmoopi/Brewster" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
</p>

---

## Features

- **Menu Bar Integration** — See available Homebrew updates at a glance with a badge counter
- **One-Click Updates** — Upgrade individual packages or all outdoors packages directly from the menu
- **Package Installation** — Install new Homebrew packages without leaving your menu bar
- **Automatic Checking** — Configurable update intervals to keep you informed
- **Launch at Login** — Optionally start Brewster when you log in
- **Native Experience** — Built with Swift and AppKit for a fast, lightweight footprint

## Installation

### Homebrew (Recommended)

```bash
brew tap shmoopi/brewster https://github.com/shmoopi/Brewster
brew install --cask brewster
```

**Upgrade to latest:**
```bash
brew upgrade --cask brewster
```

**Uninstall:**
```bash
brew uninstall --cask brewster
```

### Manual Installation

1. Download the latest `Brewster.zip` from the [Releases page](https://github.com/shmoopi/Brewster/releases)
2. Unzip and drag `Brewster.app` to your Applications folder
3. Launch Brewster from Applications

## Requirements

- macOS 13 (Ventura) or later
- [Homebrew](https://brew.sh) installed

## Usage

Once launched, Brewster lives in your menu bar. Click the icon to:

- View outdated formulae and casks
- Refresh the package list
- Upgrade individual packages or upgrade all
- Access options like update frequency and launch at login
- Install new packages (via Options menu)

Hold **Option (⌥)** while clicking for additional menu options.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Commit your changes: `git commit -m "Add new feature"`
4. Push to the branch: `git push origin my-feature`
5. Open a pull request

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
