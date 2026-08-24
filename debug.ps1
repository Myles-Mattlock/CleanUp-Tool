function Play-TempAlertSound {
    [System.Threading.Tasks.Task]::Run([System.Action]{
        try {
            # 1. Primary: Play Windows stock alarm WAV directly through sound hardware
            $WavPath = "$env:windir\Media\alarm01.wav"
            if (-not (Test-Path $WavPath)) { $WavPath = "$env:windir\Media\chimes.wav" }

            if (Test-Path $WavPath) {
                $Player = New-Object System.Media.SoundPlayer $WavPath
                $Player.PlaySync()
                $Player.Dispose()
                return
            }
        } catch {}

        # 2. Fallback A: SoundPlayer Default Beep
        try {
            $FallbackPlayer = New-Object System.Media.SoundPlayer
            $FallbackPlayer.PlaySync()
            $FallbackPlayer.Dispose()
            return
        } catch {}

        # 3. Fallback B: Terminal ASCII Bell Character Escape
        try {
            Write-Host -NoNewLine "`a"
        } catch {}
    }) | Out-Null
}