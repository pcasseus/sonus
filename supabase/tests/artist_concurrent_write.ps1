$ErrorActionPreference = "Stop"

$docker = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
$container = "supabase_db_sonus_next"

if (-not (Test-Path $docker)) {
    throw "Docker executable missing."
}

$userId = [guid]::NewGuid().ToString()
$artistId = "sn41-concurrent-$userId"

function Invoke-Sql([string]$query) {
    $query | & $docker exec -i $container `
        psql -X -v ON_ERROR_STOP=1 -A -t `
        -U postgres -d postgres

    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL command failed."
    }
}

$seed = @"
INSERT INTO auth.users (id)
VALUES ('$userId'::uuid);

INSERT INTO public.artists (
    id, user_id, name, canonical_name,
    created_at, updated_at
)
VALUES (
    '$artistId', '$userId'::uuid,
    'Original', 'original',
    now(), now()
);
"@

$sessionA = @"
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$userId', true);
SELECT outcome, server_revision
FROM public.update_artist_name_if_revision(
    '$artistId', 1, 'Winner', 'winner', now()
);
SELECT pg_sleep(6);
COMMIT;
"@

$sessionB = @"
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$userId', true);
SELECT outcome, server_revision
FROM public.update_artist_name_if_revision(
    '$artistId', 1, 'Loser', 'loser', now()
);
COMMIT;
"@

$jobA = $null
$jobB = $null

try {
    Invoke-Sql $seed | Out-Null

    $worker = {
        param($dockerExe, $dbContainer, $query)

        $output = $query | & $dockerExe exec -i $dbContainer `
            psql -X -v ON_ERROR_STOP=1 -A -t `
            -U postgres -d postgres 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "PostgreSQL session failed: $output"
        }

        return $output
    }

    $jobA = Start-Job -ScriptBlock $worker `
        -ArgumentList $docker, $container, $sessionA

    Start-Sleep -Seconds 2

    if ($jobA.State -ne "Running") {
        throw "Connection A exited before the competing write."
    }

    $startB = Get-Date

    $jobB = Start-Job -ScriptBlock $worker `
        -ArgumentList $docker, $container, $sessionB

    $null = @($jobA, $jobB) | Wait-Job

    $resultA = @(Receive-Job $jobA -ErrorAction Stop)
    $resultB = @(Receive-Job $jobB -ErrorAction Stop)

    $elapsedB = ((Get-Date) - $startB).TotalSeconds

    Write-Host "`n=== CONNECTION A ==="
    $resultA

    Write-Host "`n=== CONNECTION B ==="
    $resultB

    if ($jobA.State -ne "Completed" -or
        $jobB.State -ne "Completed") {
        throw "One or more connections failed."
    }

    if (-not ($resultA -match '^applied\|2$')) {
        throw "Connection A did not apply revision 2."
    }

    if (-not ($resultB -match '^conflict\|2$')) {
        throw "Connection B did not report conflict/2."
    }

    if ($elapsedB -lt 2) {
        throw "Connection B did not wait long enough to verify contention."
    }

    $verify = @"
SELECT name || '|' || server_revision
FROM public.artists
WHERE id = '$artistId'
  AND user_id = '$userId'::uuid;
"@

    $finalState = @(Invoke-Sql $verify)

    if ($finalState -notcontains "Winner|2") {
        throw "The final artist state was incorrect: $finalState"
    }

    Write-Host "`nPASS: First write applied revision 2."
    Write-Host "PASS: Competing stale write returned conflict."
    Write-Host "PASS: Concurrent execution caused database contention."
    Write-Host "PASS: Winning data was preserved."
}
finally {
    foreach ($job in @($jobA, $jobB)) {
        if ($null -ne $job) {
            if ($job.State -eq "Running") {
                $job | Stop-Job
            }
            $job | Remove-Job -Force
        }
    }

    # Deleting the temporary user also removes its artist
    # through the existing ON DELETE CASCADE foreign key.
    $cleanup = @"
DELETE FROM auth.users
WHERE id = '$userId'::uuid;
"@

    Invoke-Sql $cleanup | Out-Null
    Write-Host "Temporary test account cleaned up."
}