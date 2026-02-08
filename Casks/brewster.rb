cask "brewster" do
  version "1.1.3"
  sha256 "066fb9bbd62514a02fdb2d7c8e4e6af11880359032a316c3129aae5bcf02a1d5"

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
