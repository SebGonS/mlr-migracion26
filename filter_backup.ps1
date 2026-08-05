# filter_backup.ps1
# Strips COPY blocks for Supabase system schemas from a pg_dumpall backup.
# These schemas fail with "permission denied" on a Supabase dev branch,
# which corrupts psql's COPY mode and prevents all subsequent app data from loading.
#
# Usage: .\filter_backup.ps1 -InputPath <backup.backup> -OutputPath <filtered.sql>

param(
    [Parameter(Mandatory=$true)] [string] $InputPath,
    [Parameter(Mandatory=$true)] [string] $OutputPath
)

# Schemas whose COPY blocks are skipped (Supabase-managed, postgres user has no INSERT rights)
$skipSchemas = @('auth', 'storage', 'realtime', 'pgsodium', 'vault', 'supabase_migrations', 'cron')

$reader = [System.IO.StreamReader]::new($InputPath, [System.Text.Encoding]::UTF8)
$writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::UTF8)

$skipping = $false
$linesWritten = 0
$linesSkipped = 0
$blocksSkipped = 0

try {
    while ($null -ne ($line = $reader.ReadLine())) {
        # Detect start of a COPY block
        if ($line -match '^COPY (\w+)\.') {
            $schema = $Matches[1]
            if ($skipSchemas -contains $schema) {
                $skipping = $true
                $blocksSkipped++
                Write-Host "  Skipping COPY block for schema: $schema" -ForegroundColor Yellow
            }
        }

        if ($skipping) {
            $linesSkipped++
            # End of COPY data block
            if ($line -eq '\.') {
                $skipping = $false
            }
        } else {
            $writer.WriteLine($line)
            $linesWritten++
        }
    }
} finally {
    $reader.Close()
    $writer.Close()
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Lines written : $linesWritten"
Write-Host "  Lines skipped : $linesSkipped (across $blocksSkipped COPY blocks)"
Write-Host "  Output        : $OutputPath"
