cask "brewster" do
  version "1.2.2"
  sha256 "aadd77b14039e156e6f05d93ebd6282aa52b95e5036c256be1d45be9c01536d1"

  url "https://github.com/shmoopi/Brewster/releases/download/#{version}/Brewster.zip"
  name "Brewster"
  desc "macOS menu bar app that monitors Homebrew for package updates"
  homepage "https://github.com/shmoopi/Brewster"

  depends_on macos: :ventura

  app "Brewster.app"

  zap trash: [
    "~/Library/Preferences/net.shmoopi.Brewster.plist",
  ]
end
