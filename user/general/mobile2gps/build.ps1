# Build for MIPS 24KEc soft-float (OpenWRT)
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
$env:GOOS = "linux"
$env:GOARCH = "mipsle"
$env:GOMIPS = "softfloat"

go build -ldflags="-s -w" -o mobile2gps .

Write-Host "Built: mobile2gps (linux/mipsle softfloat)"
