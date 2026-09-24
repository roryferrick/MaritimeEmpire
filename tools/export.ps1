# Exports release builds and zips them for sharing.
#
#   powershell -ExecutionPolicy Bypass -File tools/export.ps1              # Windows + macOS
#   powershell -ExecutionPolicy Bypass -File tools/export.ps1 -Only macOS  # just one preset
#
# Output: build/MaritimeEmpire-windows.zip (single .exe with the game data embedded)
#         build/MaritimeEmpire-macos.zip   (universal .app, ad-hoc signed, not notarized)
#         build/MaritimeEmpire-web.zip     (-Only Web; upload to itch.io as an HTML game)
# Set $env:GODOT to point at a different Godot executable.
param(
	[ValidateSet("All", "Windows", "macOS", "Web")]
	[string]$Only = "All"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = $env:GODOT
if (-not $godot) {
	$godot = "$env:USERPROFILE\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
}
if (-not (Test-Path $godot)) {
	throw "Godot not found at '$godot'. Set `$env:GODOT to the Godot executable."
}

# Web is opt-in: "All" covers the platforms we're sharing builds for.
$targets = @(
	@{ Preset = "Windows"; Dir = "build\windows"; File = "MaritimeEmpire.exe"; Zip = "build\MaritimeEmpire-windows.zip"; Default = $true },
	@{ Preset = "macOS"; Dir = "build\macos"; File = "MaritimeEmpire-macos.zip"; Zip = "build\MaritimeEmpire-macos.zip"; Default = $true },
	@{ Preset = "Web"; Dir = "build\web"; File = "index.html"; Zip = "build\MaritimeEmpire-web.zip"; Default = $false }
) | Where-Object { ($Only -eq "All" -and $_.Default) -or $_.Preset -eq $Only }

foreach ($t in $targets) {
	$dir = Join-Path $root $t.Dir
	$zip = Join-Path $root $t.Zip
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null

	Write-Host "Exporting $($t.Preset)..."
	$out = Join-Path $dir $t.File
	$proc = Start-Process -FilePath $godot -NoNewWindow -Wait -PassThru `
		-ArgumentList @("--headless", "--path", "`"$root`"", "--export-release", "`"$($t.Preset)`"", "`"$out`"")
	if ($proc.ExitCode -ne 0 -or -not (Test-Path $out)) {
		throw "$($t.Preset) export failed (exit code $($proc.ExitCode)). Are the export templates installed?"
	}

	if (Test-Path $zip) { Remove-Item -Force $zip }
	if ($out.EndsWith(".zip")) {
		# macOS exports straight to a zipped .app.
		Copy-Item $out $zip
	} else {
		Compress-Archive -Path (Join-Path $dir "*") -DestinationPath $zip
	}
	Write-Host "  -> $($t.Zip)"
}
