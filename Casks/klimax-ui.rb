cask "klimax-ui" do
  version "0.1.0"
  sha256 "784a1f15042b87d215edb21914338d1750e1da610d73286246e036f46cf2c2a3"

  url "https://github.com/bcollard/klimax-ui/releases/download/v#{version}/KlimaxUI.dmg"
  name "Klimax"
  desc "macOS companion app for the klimax CLI and the kind clusters it manages"
  homepage "https://github.com/bcollard/klimax-ui"

  depends_on macos: ">= :sonoma"

  app "KlimaxUI.app"

  zap trash: [
    "~/Library/Preferences/dev.bcollard.KlimaxUI.plist",
  ]

  caveats <<~EOS
    Klimax expects the klimax CLI to be installed and at least one VM to be
    configured under ~/.klimax/. Install it via:

      brew install bcollard/klimax/klimax
  EOS
end
