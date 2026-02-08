cask "brewster" do
  version "1.1.2"
  sha256 "85aed80d1297a5769342581be42aa79016cef85086d1d2b3f2861aa0f95ff93a"

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
