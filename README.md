# Brewster

Brewster is a macOS menu bar application that checks for Homebrew updates.

## Features

- Checks for Homebrew updates and displays the number of updates available in the menu bar.
- Allows users to refresh, run Homebrew update commands in the terminal, and set the application to start at login.
- Install new Homebrew packages directly from the menu bar (Options > Install Package...).

## Installation

### Homebrew (Recommended)

Install Brewster using [Homebrew](https://brew.sh):

```bash
brew tap shmoopi/brewster https://github.com/shmoopi/Brewster
brew install --cask brewster
```

To upgrade to the latest version:

```bash
brew upgrade --cask brewster
```

To uninstall:

```bash
brew uninstall --cask brewster
```

### Manual Installation

1. Download the latest `Brewster.zip` from the [Releases page](https://github.com/shmoopi/Brewster/releases)
2. Unzip and drag `Brewster.app` to your Applications folder
3. Launch Brewster from Applications

## Requirements

- macOS 13 (Ventura) or later
- Homebrew installed

## Contributing

1. Fork the repository.
2. Create a new branch:

```sh
git checkout -b my-feature-branch
```

3. Make your changes and commit them:

```sh
git commit -m "Add new feature"
```

4. Push to the branch:

```sh
git push origin my-feature-branch
```

5. Open a pull request.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
