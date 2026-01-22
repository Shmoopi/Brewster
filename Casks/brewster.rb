cask "brewster" do
  version "1.1.1"
  sha256 "REPLACE_WITH_SHA256_OF_ZIP"

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
