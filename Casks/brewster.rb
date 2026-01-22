cask "brewster" do
  version "1.1.1"
  sha256 "7212c2fba9c8df777e1df4e18c2cd6e395ad65ea923d5b6e67b1e6ed7a943361"

  url "https://github.com/shmoopi/Brewster/releases/download/#{version}/Brewster.zip"
  name "Brewster"
  desc "macOS menu bar app that monitors Homebrew for package updates"
  homepage "https://github.com/shmoopi/Brewster"

  depends_on macos: ">= :ventura"

  app "Brewster.app"

  zap trash: [
    "~/Library/Preferences/net.shmoopi.Brewster.plist",
  ]
end
