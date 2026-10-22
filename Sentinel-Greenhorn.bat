<# : Sentinel Greenhorn WSL installer - batch launcher, the PowerShell payload follows below
@echo off
setlocal
set "BARD_SELF=%~f0"
set "BARD_ARGS=%*"
title Sentinel Greenhorn - Help is here!
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:BARD_SELF,[Text.Encoding]::UTF8); iex $s"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
#>

# =====================================================================
#  Sentinel Greenhorn - the WSL installer for dummies
#  Fireworks intro + guided install of Windows Subsystem for Linux,
#  fixed IP for the distro and disk space reclaim.
#
#  Usage:   Sentinel-Greenhorn.bat               (normal, double-click)
#           Sentinel-Greenhorn.bat --dry-run     (shows everything, changes nothing)
#           Sentinel-Greenhorn.bat --dry-run --fresh   (dry-run as if WSL were missing)
#           Sentinel-Greenhorn.bat --go          (skip the intro, straight to the guide)
# =====================================================================

$ErrorActionPreference = 'Continue'

#region ---------- arguments and config ----------
$argv = @()
if ($env:BARD_ARGS) { $argv = @($env:BARD_ARGS -split '\s+' | Where-Object { $_ }) }
function Test-Flag([string[]]$names) { foreach ($a in $argv) { if ($names -contains $a) { return $true } }; return $false }

$DryRun    = Test-Flag @('--dry-run', '--dryrun', '-n', '/dry', 'dry')
$Fresh     = Test-Flag @('--fresh')
$GoDirect  = Test-Flag @('--go', '--skip-intro')
$SimOops   = Test-Flag @('--oops')          # dry-run only: fake a failure to preview the error talk
$SimNoVirt = Test-Flag @('--novirt')        # dry-run only: pretend virtualization is off in BIOS
$NoMusic   = Test-Flag @('--quiet', '--no-music', '--stille')
$AfterBios = Test-Flag @('--after-bios')    # we are back from the BIOS
$Resume    = Test-Flag @('--resume')        # started by the logon task after a reboot
$Self      = $env:BARD_SELF

$Cfg = @{
    WinIp     = '192.168.250.1'      # Windows side of the fixed link
    WslIp     = '192.168.250.2'      # fixed IP of the WSL distro
    Prefix    = 24
    Broadcast = '192.168.250.255'
    HostName  = 'wsl.local'          # added to the Windows hosts file
    TaskName  = 'Greenhorn-WSL-FixedIP'
    DataDir   = Join-Path $env:ProgramData 'GreenhornWSL'
    LogFile   = Join-Path $env:TEMP 'greenhorn-wsl-helper.log'
    ResumeTask = 'Greenhorn-WSL-Resume'
}
$Cfg.StateFile = Join-Path $Cfg.DataDir 'resume.json'
$Cfg.ResumePs1 = Join-Path $Cfg.DataDir 'resume.ps1'
$Cfg.SelfCopy  = Join-Path $Cfg.DataDir 'Sentinel-Greenhorn.bat'

$env:WSL_UTF8 = '1'   # make wsl.exe print UTF-8 instead of UTF-16
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ESC = [char]27
$RST = "$ESC[0m"

# Make sure ANSI/VT sequences work in classic conhost too
try {
    Add-Type -Namespace Greenhorn -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@ -ErrorAction Stop
    $h = [Greenhorn.Con]::GetStdHandle(-11); $m = 0
    if ([Greenhorn.Con]::GetConsoleMode($h, [ref]$m)) { [void][Greenhorn.Con]::SetConsoleMode($h, ($m -bor 4)) }
} catch {}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$Interactive = -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)
#endregion

#region ---------- small UI helpers ----------
function Say([string]$text, [int]$color = 252) { [Console]::WriteLine("$ESC[38;5;${color}m$text$RST") }
function Ok([string]$t)   { Say "  [OK]  $t" 46 }
function Info([string]$t) { Say "  [i]   $t" 117 }
function Warn([string]$t) { Say "  [!]   $t" 214 }
function Bad([string]$t)  { Say "  [X]   $t" 196 }

$script:StepNo = 0
$TotalSteps = 10
function Step([string]$title) {
    $script:StepNo++
    [Console]::WriteLine()
    Say ('=' * 64) 39
    Say ("  STEP {0}/{1}  -  {2}" -f $script:StepNo, $TotalSteps, $title) 51
    Say ('=' * 64) 39
}

function Ask-YesNo([string]$q, [bool]$def = $true) {
    $hint = if ($def) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = Read-Host "  $q $hint"
        if ([string]::IsNullOrWhiteSpace($a)) { return $def }
        switch -regex ($a.Trim()) {
            '^(j|ja|y|yes)$' { return $true }
            '^(n|nei|no)$'   { return $false }
        }
        Warn 'Answer y (yes) or n (no).'
    }
}

function Ask-Choice([string]$q, [string[]]$valid, [string]$def) {
    while ($true) {
        $a = Read-Host "  $q"
        if ([string]::IsNullOrWhiteSpace($a)) { return $def }
        if ($valid -contains $a.Trim()) { return $a.Trim() }
        Warn ("Pick one of: " + ($valid -join ', '))
    }
}

function Pause-Key([string]$msg = 'Press any key to close the window ...') {
    if ($Interactive) { [Console]::WriteLine(); Say "  $msg" 244; [void][Console]::ReadKey($true) }
}

#--- personality ---
$Rng = New-Object System.Random
$Cheers = @(
    'Yay! You did it!',
    'Hooray! Give yourself a pat on the back, Mr. Greenhorn!',
    'Brilliant, Mr. Greenhorn! Bang on target!',
    'Good job! You get a gold star in your book today!',
    'Woohoo! That went like clockwork!',
    'High five! That was easier than assembling IKEA furniture, right?',
    'Look at you go! You''ll be fixing other people''s computers next!',
    'Yippee! Somebody get this man a cape!',
    'Thumbs up! You''re a natural, Mr. Greenhorn!',
    'Boom! Not bad at all for a greenhorn!'
)
$OopsOpeners = @(
    'Oopsie daisy! We just fell off the rails!',
    'Whoops! Straight into the mud puddle.',
    'Uh-oh, uh-oh! That did not go according to plan.',
    'Oh dear! The computer said no - and it isn''t even a difficult customer.',
    'Yikes, an error! But only a teeny tiny one.',
    'Oh my! We fell off the bike.'
)
$Comforts = @(
    'Don''t panic, Mr. Greenhorn - Sentinel has got your back!',
    'No worries! We''ll kiss it better and fix it together - Sentinel has got your back!',
    'Deep breaths, Mr. Greenhorn. Sentinel has been here before!',
    'Relax! Even the best of us hear "no" now and then. Sentinel has got your back!'
)
$DefaultFix = 'Take a screenshot (Win+Shift+S) and send it to Sentinel - we''ll take it from there.'
$script:LastCheer = -1
$script:OopsCount = 0

$script:ForcedCheer = $null
function Yay {
    if ($script:ForcedCheer) { Say "  *** $($script:ForcedCheer) ***" 226; $script:ForcedCheer = $null; return }
    do { $i = $Rng.Next($Cheers.Count) } while ($i -eq $script:LastCheer)
    $script:LastCheer = $i
    Say "  *** $($Cheers[$i]) ***" 226
}

function Oops([string]$what, [string]$fix = $DefaultFix) {
    $script:OopsCount++
    [Console]::WriteLine()
    Say "  $($OopsOpeners[$Rng.Next($OopsOpeners.Count)])" 203
    Say "     (What happened: $what)" 244
    Say "  $($Comforts[$Rng.Next($Comforts.Count)])" 219
    $first = $true
    foreach ($l in ($fix -split "`n")) {
        if ($first) { Say "  Do this and we're back on track: $l" 229; $first = $false } else { Say "                                   $l" 229 }
    }
    [Console]::WriteLine()
}

# Every change goes through here, so dry-run can show it without doing it.
# A failure (exception or non-zero exit code) turns into a friendly Oops with a fix.
$script:ActionNo = 0
function Invoke-Action([string]$what, [scriptblock]$do, [string]$show, [string]$fix = $DefaultFix) {
    $script:ActionNo++
    if ($DryRun) {
        Say "  [DRY-RUN] $what" 214
        if ($show) { foreach ($l in ($show -split "`n")) { Say "            > $l" 244 } }
        if ($SimOops -and $script:ActionNo -eq 3) { Oops "$what went belly up (just pretend - this is the --oops test)" $fix }
        return
    }
    Say "  -> $what" 117
    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0
    try { & $do } catch { Oops "$what feilet: $($_.Exception.Message)" $fix; return }
    if ($LASTEXITCODE -ne 0) { Oops "$what ga feilkode $LASTEXITCODE." $fix }
}
#endregion

#region ---------- retro synth music ----------
# A tiny chiptune synth: renders a 15 s loop (lead + echo, arpeggio, bass, drums) into
# an in-memory WAV and loops it in the background while the helper does its thing.
$SynthSource = @'
using System;
using System.IO;
using System.Media;

namespace Greenhorn {
    public static class Synth {
        const int SR = 22050;
        static SoundPlayer player;

        static readonly string[] Melody = {
            "E5:3 D5:3 C5:2 A4:2 C5:2 D5:2 E5:2",
            "F5:3 E5:3 C5:2 A4:4 R:4",
            "G5:3 E5:3 C5:2 E5:2 G5:2 A5:2 G5:2",
            "D5:6 B4:2 G4:4 R:4",
            "A5:3 G5:3 E5:2 D5:2 E5:2 G5:2 A5:2",
            "C6:3 A5:3 F5:2 A5:4 C6:4",
            "G5:2 E5:2 G5:2 C6:2 B5:2 G5:2 E5:2 D5:2",
            "B5:4 D6:4 B5:2 G5:2 R:4"
        };
        static readonly int[][] Chords = { new[] { 57, 60, 64 }, new[] { 53, 57, 60 }, new[] { 55, 60, 64 }, new[] { 55, 59, 62 } };
        static readonly int[] Roots = { 45, 41, 48, 43 };   // Am F C G

        static double Freq(int midi) { return 440.0 * Math.Pow(2.0, (midi - 69) / 12.0); }

        static int Midi(string n) {
            int[] semi = { 9, 11, 0, 2, 4, 5, 7 };   // A B C D E F G
            int s = semi[n[0] - 'A'], i = 1;
            if (n[i] == '#') { s++; i++; }
            return 12 * (n[i] - '0' + 1) + s;
        }

        static void Kick(double[] m, int start) {
            double ph = 0;
            for (int i = 0; i < SR / 4; i++) {
                double t = (double)i / SR;
                ph += (45 + 110 * Math.Exp(-t * 30)) / SR;
                m[(start + i) % m.Length] += Math.Sin(2 * Math.PI * ph) * 0.5 * Math.Exp(-t * 9);
            }
        }

        static void Snare(double[] m, int start, Random r) {
            double ph = 0;
            for (int i = 0; i < SR / 5; i++) {
                double t = (double)i / SR;
                ph += 185.0 / SR;
                m[(start + i) % m.Length] += (r.NextDouble() * 2 - 1) * 0.2 * Math.Exp(-t * 16) + Math.Sin(2 * Math.PI * ph) * 0.12 * Math.Exp(-t * 25);
            }
        }

        static void Hat(double[] m, int start, Random r, double amp) {
            double prev = 0;
            for (int i = 0; i < SR / 25; i++) {
                double t = (double)i / SR, n = r.NextDouble() * 2 - 1;
                m[(start + i) % m.Length] += (n - prev) * amp * Math.Exp(-t * 70);
                prev = n;
            }
        }

        public static byte[] Render() {
            int stepLen = (int)(60.0 / 128.0 / 4.0 * SR);   // a 16th note at 128 BPM
            int steps = Melody.Length * 16, total = steps * stepLen;
            double[] lead = new double[total], mix = new double[total];
            Random rnd = new Random(7);

            // Lead: 25 % pulse wave, soft filter, vibrato on long notes
            int pos = 0;
            foreach (string bar in Melody) {
                foreach (string tok in bar.Split(' ')) {
                    string[] p = tok.Split(':');
                    int len = int.Parse(p[1]) * stepLen;
                    if (p[0] != "R") {
                        double f = Freq(Midi(p[0])), ph = 0, lp = 0;
                        for (int i = 0; i < len; i++) {
                            double t = (double)i / SR, rest = (double)(len - i) / SR;
                            double vib = t > 0.15 ? Math.Sin(2 * Math.PI * 5.5 * t) * 0.25 / 12.0 : 0;
                            ph += f * Math.Pow(2, vib) / SR; ph -= Math.Floor(ph);
                            lp += 0.3 * ((ph < 0.25 ? 1 : -1) - lp);
                            double env = Math.Min(1, t / 0.005) * Math.Min(1, rest / 0.03) * (0.7 + 0.3 * Math.Exp(-t * 6));
                            lead[(pos + i) % total] += lp * env * 0.2;
                        }
                    }
                    pos += len;
                }
            }
            // Echo wraps around, so the loop point is seamless
            int d = 3 * stepLen;
            for (int i = 0; i < total; i++)
                mix[i] += lead[i] + 0.3 * lead[(i - d + total) % total] + 0.12 * lead[(i - 2 * d + 2 * total) % total];

            // Arpeggio: classic fast chord arpeggio, three notes per 16th
            int tick = stepLen / 3;
            for (int s = 0; s < steps; s++) {
                int[] ch = Chords[(s / 16) % 4];
                for (int k = 0; k < 3; k++) {
                    double f = Freq(ch[(s * 3 + k) % 3] + 12), ph = 0;
                    int start = s * stepLen + k * tick;
                    for (int i = 0; i < tick; i++) {
                        ph += f / SR; ph -= Math.Floor(ph);
                        double t = (double)i / SR;
                        mix[(start + i) % total] += (ph < 0.5 ? 1 : -1) * 0.045 * Math.Min(1, t / 0.001) * Math.Exp(-t * 20);
                    }
                }
            }

            // Bass: triangle, octave-jumping eighths
            for (int e = 0; e < steps / 2; e++) {
                double f = Freq(Roots[(e / 8) % 4] + (e % 2 == 1 ? 12 : 0)), ph = 0.25;   // start at the zero crossing
                int start = e * 2 * stepLen, len = 2 * stepLen - SR / 100;
                for (int i = 0; i < len; i++) {
                    ph += f / SR; ph -= Math.Floor(ph);
                    double t = (double)i / SR;
                    mix[(start + i) % total] += (4 * Math.Abs(ph - 0.5) - 1) * 0.22 * Math.Min(1, t / 0.003) * Math.Exp(-t * 5);
                }
            }

            // Drums
            for (int s = 0; s < steps; s++) {
                int start = s * stepLen, b = s % 16;
                if (b == 0 || b == 8 || (b == 10 && (s / 16) % 2 == 1)) Kick(mix, start);
                if (b == 4 || b == 12) Snare(mix, start, rnd);
                if (b % 4 == 2) Hat(mix, start, rnd, 0.05);
                else if (b % 2 == 1) Hat(mix, start, rnd, 0.022);
            }

            byte[] wav = new byte[44 + total * 2];
            using (MemoryStream ms = new MemoryStream(wav))
            using (BinaryWriter w = new BinaryWriter(ms)) {
                w.Write("RIFF".ToCharArray()); w.Write(36 + total * 2); w.Write("WAVE".ToCharArray());
                w.Write("fmt ".ToCharArray()); w.Write(16); w.Write((short)1); w.Write((short)1);
                w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
                w.Write("data".ToCharArray()); w.Write(total * 2);
                for (int i = 0; i < total; i++) w.Write((short)(Math.Tanh(mix[i] * 1.1) * 0.3 * 32767));
            }
            return wav;
        }

        public static void Play() {
            if (player == null) player = new SoundPlayer(new MemoryStream(Render()));
            player.PlayLooping();
        }

        public static void Stop() { if (player != null) player.Stop(); }
    }
}
'@

$script:MusicOn = $false
function Start-Music {
    if ($NoMusic -or -not $Interactive) { return }
    try {
        if (-not ('Greenhorn.Synth' -as [type])) { Add-Type -TypeDefinition $SynthSource -ErrorAction Stop }
        [Greenhorn.Synth]::Play()
        $script:MusicOn = $true
    } catch {}
}
function Stop-Music { try { [Greenhorn.Synth]::Stop() } catch {}; $script:MusicOn = $false }
function Switch-Music { if ($script:MusicOn) { Stop-Music } else { $script:NoMusic = $false; Start-Music } }
#endregion

#region ---------- fireworks intro ----------
$Glyphs = @{
    'B' = @('     ', '#### ', '#   #', '#### ', '#   #', '#### ')
    'R' = @('     ', '#### ', '#   #', '#### ', '#  # ', '#   #')
    'D' = @('     ', '#### ', '#   #', '#   #', '#   #', '#### ')
    'H' = @('     ', '#   #', '#   #', '#####', '#   #', '#   #')
    'J' = @('     ', '  ###', '   # ', '   # ', '#  # ', ' ##  ')
    'E' = @('     ', '#####', '#    ', '#### ', '#    ', '#####')
    'L' = @('     ', '#    ', '#    ', '#    ', '#    ', '#####')
    'P' = @('     ', '#### ', '#   #', '#### ', '#    ', '#    ')
    'N' = @('     ', '#   #', '##  #', '# # #', '#  ##', '#   #')
    '!' = @('  ', '##', '##', '##', '  ', '##')
    'U' = @('     ', '#   #', '#   #', '#   #', '#   #', ' ### ')
    'K' = @('     ', '#   #', '#  # ', '###  ', '#  # ', '#   #')
    'T' = @('     ', '#####', '  #  ', '  #  ', '  #  ', '  #  ')
    'I' = @('   ', '###', ' # ', ' # ', ' # ', '###')
    'A' = @('     ', ' ### ', '#   #', '#####', '#   #', '#   #')
    'V' = @('     ', '#   #', '#   #', '#   #', ' # # ', '  #  ')
    'W' = @('     ', '#   #', '#   #', '# # #', '## ##', '#   #')
    'Y' = @('     ', '#   #', ' # # ', '  #  ', '  #  ', '  #  ')
    'G' = @('     ', ' ####', '#    ', '#  ##', '#   #', ' ####')
    'C' = @('     ', ' ####', '#    ', '#    ', '#    ', ' ####')
    '.' = @('  ', '  ', '  ', '  ', '  ', '##')
    'M' = @('     ', '#   #', '## ##', '# # #', '#   #', '#   #')
    'S' = @('     ', ' ####', '#    ', ' ### ', '    #', '#### ')
    'O' = @('     ', ' ### ', '#   #', '#   #', '#   #', ' ### ')
    ' ' = @('   ', '   ', '   ', '   ', '   ', '   ')
}
$Rainbow = @(196, 202, 208, 214, 220, 226, 190, 154, 118, 82, 46, 47, 48, 49, 50, 51, 45, 39, 33, 27, 21, 57, 93, 129, 165, 201, 200, 199, 198, 197)
$Sparkle = @(196, 208, 226, 46, 51, 33, 201, 231, 214, 129, 87, 219)

function New-BigLine([string]$text, [int]$sx) {
    $letters = @(); $x = 0
    foreach ($ch in $text.ToCharArray()) {
        $g = $Glyphs[[string]$ch]
        if (-not $g) { $g = $Glyphs[' '] }
        $w = $g[0].Length * $sx
        $letters += , @{ Rows = $g; X = $x; W = $w; Space = ($ch -eq ' ') }
        $x += $w + $sx
    }
    @{ Letters = $letters; Width = ($x - $sx); Sx = $sx }
}

function New-Particle($x, $y, $vx, $vy, $life, $color, $kind) {
    $q = New-Object 'double[]' 7
    $q[0] = $x; $q[1] = $y; $q[2] = $vx; $q[3] = $vy; $q[4] = $life; $q[5] = $color; $q[6] = $kind
    , $q
}

# Small 4x5 pixel font, drawn with half blocks so each letter is 4 columns x 3 rows
$MiniGlyphs = @{
    'O' = @('.##.', '#..#', '#..#', '#..#', '.##.')
    'D' = @('###.', '#..#', '#..#', '#..#', '###.')
    'V' = @('#..#', '#..#', '#..#', '.##.', '.##.')
    'A' = @('.##.', '#..#', '####', '#..#', '#..#')
    'R' = @('###.', '#..#', '###.', '#.#.', '#..#')
    'H' = @('#..#', '#..#', '####', '#..#', '#..#')
    'J' = @('...#', '...#', '...#', '#..#', '.##.')
    'E' = @('####', '#...', '###.', '#...', '####')
    'L' = @('#...', '#...', '#...', '#...', '####')
    'P' = @('###.', '#..#', '###.', '#...', '#...')
    'G' = @('.###', '#...', '#.##', '#..#', '.###')
    'N' = @('#..#', '##.#', '#.##', '#..#', '#..#')
    'W' = @('#...#', '#...#', '#.#.#', '##.##', '#...#')
    'S' = @('.###', '#...', '.##.', '...#', '###.')
    '!' = @('#', '#', '#', '.', '#')
    'T' = @('###', '.#.', '.#.', '.#.', '.#.')
    'C' = @('.###', '#...', '#...', '#...', '.###')
    'U' = @('#..#', '#..#', '#..#', '#..#', '.##.')
    '4' = @('#..#', '#..#', '####', '...#', '...#')
    '2' = @('###.', '...#', '.##.', '#...', '####')
    '0' = @('.##.', '#.##', '#..#', '##.#', '.##.')
    'I' = @('###', '.#.', '.#.', '.#.', '###')
}

# Tiny 4 pixel high font (2 text rows) for the scrolling marquee
$TinyGlyphs = @{
    'A' = @('.#.', '#.#', '###', '#.#');   'B' = @('##.', '###', '#.#', '###');   'D' = @('##.', '#.#', '#.#', '##.')
    'E' = @('###', '##.', '#..', '###');   'F' = @('###', '#..', '##.', '#..');   'I' = @('###', '.#.', '.#.', '###')
    'L' = @('#..', '#..', '#..', '###');   'M' = @('#...#', '##.##', '#.#.#', '#...#'); 'N' = @('#..#', '##.#', '#.##', '#..#')
    'O' = @('###', '#.#', '#.#', '###');   'R' = @('##.', '#.#', '##.', '#.#');   'S' = @('.##', '#..', '..#', '##.')
    'T' = @('###', '.#.', '.#.', '.#.');   'U' = @('#.#', '#.#', '#.#', '###');   'X' = @('#.#', '.#.', '.#.', '#.#')
    'Y' = @('#.#', '#.#', '.#.', '.#.');   'W' = @('#...#', '#...#', '#.#.#', '.#.#.'); 'v' = @('...', '#.#', '#.#', '.#.')
    '.' = @('.', '.', '.', '#');           '0' = @('.#.', '#.#', '#.#', '.#.');   '1' = @('.#', '##', '.#', '.#')
}

# Turns a text into a list of 4-bit pixel columns (bit 0 = top row) for the marquee
function New-Marquee([string]$text, [int]$gap) {
    $cols = New-Object System.Collections.Generic.List[int]
    foreach ($ch in $text.ToCharArray()) {
        if ($ch -eq ' ') { 1..3 | ForEach-Object { $cols.Add(0) }; continue }
        $g = $TinyGlyphs[[string]$ch]
        if (-not $g) { continue }
        for ($c = 0; $c -lt $g[0].Length; $c++) {
            $m = 0
            for ($r = 0; $r -lt 4; $r++) { if ($g[$r][$c] -eq '#') { $m = $m -bor (1 -shl $r) } }
            $cols.Add($m)
        }
        $cols.Add(0)
    }
    for ($i = 0; $i -lt $gap; $i++) { $cols.Add(0) }
    , $cols.ToArray()
}

# Fallback target shape for the morph, and the colours the morphing letter goes through on its way down
$RingGlyph = @('.##.', '####', '####', '.##.')
$MorphCols = @(213, 207, 171, 135, 99, 63, 69, 75, 81, 87)

# Every letter gets its own party trick: spin, flip upside down, bounce, bob, swap places,
# or (the I in SENTINEL) morph into the O in GREENHORN and back.
# -Calm gives a gentle wave only. Pal = @{ Base; Alt; Shine } (256-colour codes, no rainbow).
function New-FunLine([string]$text, $pal, [switch]$Calm) {
    $tricks = @(
        @{ T = 'spin'; P = 3.2; O = 0.0 }, @{ T = 'swapA' }, @{ T = 'swapB' }, @{ T = 'ball'; O = 0.0; A = 5 },
        @{ T = 'flip'; P = 4.5; O = 1.0 }, @{ T = 'wave' }, @{ T = 'bob'; O = 0.0 }, @{ T = 'morph' },
        @{ T = 'wave' }, @{ T = 'ball'; O = 1.2; A = 3 }, @{ T = 'flip'; P = 5.0; O = 2.7 }, @{ T = 'wave' },
        @{ T = 'spin'; P = 5.5; O = 3.0 }, @{ T = 'bob'; O = 1.0 }, @{ T = 'wave' }, @{ T = 'flip'; P = 6.0; O = 0.5 }
    )
    $extra = @(
        @{ T = 'spin'; P = 4.7; O = 2.2 }, @{ T = 'wave' }, @{ T = 'flip'; P = 5.3; O = 1.8 },
        @{ T = 'ball'; O = 0.6; A = 3 }, @{ T = 'bob'; O = 2.0 }, @{ T = 'wave' }
    )
    $letters = @(); $x = 0; $n = 0
    foreach ($ch in $text.ToCharArray()) {
        if ($ch -eq ' ') { $x += 3; continue }
        $rows = $MiniGlyphs[[string]$ch]
        # swap and morph are one-offs: letters past the list only get the harmless tricks
        $tr = if ($Calm) { @{ T = 'wave' } } elseif ($n -lt $tricks.Count) { $tricks[$n] } else { $extra[$n % $extra.Count] }
        $letters += , @{ Rows = $rows; W = $rows[0].Length; X = $x; Trick = $tr; Hop = 0.0 }
        $x += $rows[0].Length + 1; $n++
    }
    @{ Letters = $letters; Width = $x - 1; Pal = $pal; Calm = [bool]$Calm; Morph = $null }
}

# Draws one mini line into the half-block layer. $row = text row of the letters' top.
function Add-MiniLine($line, [int]$row, [double]$sec, [int]$t, [int]$W, [int]$H, $half, $hcol, $rnd) {
    if ($line.Width -gt $W - 2) { return }
    $mx0 = [int](($W - $line.Width) / 2)
    $py0 = $row * 2
    $pal = $line.Pal
    $swapK = [Math]::Floor(($sec + 3) / 5.0); $swapPh = ($sec + 3) - $swapK * 5.0
    $swapP = if ($swapPh -lt 0.9) { (1 - [Math]::Cos($swapPh / 0.9 * [Math]::PI)) / 2 } else { 1.0 }
    $swapArc = if ($swapPh -lt 0.9) { [Math]::Sin($swapPh / 0.9 * [Math]::PI) * 4 } else { 0.0 }
    $dA = $null; $dB = $null
    foreach ($g in $line.Letters) { if ($g.Trick.T -eq 'swapA') { $dA = $g.X } elseif ($g.Trick.T -eq 'swapB') { $dB = $g.X } }
    if (-not $line.Calm -and $rnd.NextDouble() -lt 0.01) { $line.Letters[$rnd.Next($line.Letters.Count)].Hop = $sec + 0.45 }
    $shine = ($t * 1.2) % ($line.Width + 30) - 15
    $li = 0
    foreach ($g in $line.Letters) {
        $tr = $g.Trick; $sx = 1.0; $sy = 1.0; $lx = [double]$g.X; $dy = 0.0
        $gRows = $g.Rows; $abs = $false; $mcol = $null; $msc = 1.0
        switch ($tr.T) {
            'morph' {
                $mp = $line.Morph
                if (-not $mp) { $dy = [Math]::Sin($sec * 3) * 2; break }
                # 9 s cycle: at home, fly down + grow into the big O, stay there, fly back up
                $ph = $sec % 9.0
                $p = if ($ph -lt 2.5) { 0.0 } elseif ($ph -lt 3.5) { $ph - 2.5 } elseif ($ph -lt 8.0) { 1.0 } else { 9.0 - $ph }
                $e = (1 - [Math]::Cos($p * [Math]::PI)) / 2
                $hx = $mx0 + $g.X + $g.W / 2.0; $hy = $py0 + 2.5 + [Math]::Sin($sec * 3) * 1.5
                $acx = $hx + ($mp.X - $hx) * $e
                $acy = $hy + ($mp.Y - $hy) * $e - [Math]::Sin($e * [Math]::PI) * 3
                $abs = $true
                if ($mp.Scale) { $msc = 1 + ($mp.Scale - 1) * $e }
                if ($e -lt 0.5) { $sy = 1 - 2 * $e } else { $gRows = $(if ($mp.Rows) { $mp.Rows } else { $RingGlyph }); $sy = 2 * $e - 1 }
                if ($e -ge 1) { $mcol = $mp.Col } elseif ($e -gt 0) { $mcol = $MorphCols[[int]($e * ($MorphCols.Count - 1))] }
            }
            'spin' { $ph = ($sec + $tr.O) % $tr.P; if ($ph -lt 0.8) { $sx = [Math]::Cos($ph / 0.8 * 2 * [Math]::PI) } }
            'flip' {
                $ph = ($sec + $tr.O) % $tr.P
                if ($ph -lt 0.4) { $sy = [Math]::Cos($ph / 0.4 * [Math]::PI) }
                elseif ($ph -lt 1.6) { $sy = -1.0 }
                elseif ($ph -lt 2.0) { $sy = [Math]::Cos([Math]::PI + ($ph - 1.6) / 0.4 * [Math]::PI) }
            }
            'ball' { $dy = - [Math]::Abs([Math]::Sin($sec * 4 + $tr.O)) * $tr.A }
            'bob'  { $dy = [Math]::Sin($sec * 3 + $tr.O) * 2 }
            'wave' { $dy = [Math]::Sin($sec * 2.5 + $li * 0.6) }
            'swapA' {
                $from = if ($swapK % 2 -eq 0) { $dA } else { $dB }; $to = if ($swapK % 2 -eq 0) { $dB } else { $dA }
                $lx = $from + ($to - $from) * $swapP; $dy = - $swapArc
            }
            'swapB' {
                $from = if ($swapK % 2 -eq 0) { $dB } else { $dA }; $to = if ($swapK % 2 -eq 0) { $dA } else { $dB }
                $lx = $from + ($to - $from) * $swapP; $dy = $swapArc
            }
        }
        if ($g.Hop -gt $sec) { $dy -= [Math]::Sin(($g.Hop - $sec) / 0.45 * [Math]::PI) * 3 }
        $col = if ([Math]::Abs($lx + $g.W / 2.0 - $shine) -lt 3) { $pal.Shine } elseif ($tr.T -eq 'swapB') { $pal.Alt } else { $pal.Base }
        if ($mcol) { $col = $mcol }
        $gh = $gRows.Count; $gw = $gRows[0].Length
        $ww = [Math]::Max(1, [int][Math]::Round($gw * [Math]::Abs($sx) * $msc))
        $hh = [Math]::Max(1, [int][Math]::Round($gh * [Math]::Abs($sy) * $msc))
        $cx = $mx0 + $lx + $gw / 2.0; $cy = $py0 + 5 - $gh / 2.0 + $dy
        if ($abs) { $cx = $acx; $cy = $acy }
        for ($oy = 0; $oy -lt $hh; $oy++) {
            $sr = [int][Math]::Floor($oy * $gh / $hh); if ($sy -lt 0) { $sr = $gh - 1 - $sr }
            $py = [int][Math]::Floor($cy - $hh / 2.0 + $oy)
            if ($py -lt 0 -or ($py -shr 1) -ge $H) { continue }
            for ($ox = 0; $ox -lt $ww; $ox++) {
                $sc = [int][Math]::Floor($ox * $gw / $ww); if ($sx -lt 0) { $sc = $gw - 1 - $sc }
                if ($gRows[$sr][$sc] -ne '#') { continue }
                $px = [int][Math]::Floor($cx - $ww / 2.0 + $ox)
                if ($px -lt 0 -or $px -ge $W) { continue }
                $idx = ($py -shr 1) * $W + $px
                $half[$idx] = $half[$idx] -bor (1 + ($py -band 1)); $hcol[$idx] = $col
            }
        }
        $li++
    }
}

# With -Seconds > 0 it is a finale: no menu, ends on any key or after the time.
# With -Fun the title reads THE SENTINEL (small acrobats) / GREENHORN (big neon) / WSL INSTALLER HAS LANDED!
function Show-Intro([string]$Text2 = 'HELP IS HERE!', [int]$Seconds = 0, [switch]$Fun) {
    if (-not $Interactive) { return 'go' }
    $block = [char]0x2588
    $dot   = [char]0x00B7
    $line1 = New-BigLine 'GREENHORN' 1
    $line2 = New-BigLine $Text2 1
    $half = $null; $hcol = $null
    if ($Fun) {
        $mini1 = New-FunLine 'THE SENTINEL' @{ Base = 213; Alt = 141; Shine = 225 }
        $mini3 = New-FunLine $Text2 @{ Base = 141; Alt = 141; Shine = 189 } -Calm
        # GREENHORN: 2 columns x 2 half rows per pixel, 1 column between letters. The O is left
        # empty: the I from SENTINEL in the line above flies down, grows and becomes it.
        $big = @(); $bx = 0
        foreach ($ch in 'GREENHORN'.ToCharArray()) { $big += , @{ Ch = [string]$ch; X = $bx }; $bx += 11 }
        $bigW = $bx - 1
        $holeI = 6
        $bigO = @($Glyphs['O'][1..5])
        # Neon tube: the core of each stroke pulses cyan -> almost white, the edges stay deep blue
        $neonCore = @(51, 87, 123, 159, 195); $neonEdge = @(31, 38, 39, 44, 45)
        $marquee = New-Marquee 'WINDOWS SUBSYSTEMS FOR LINUX INSTALLER FOR DUMMIES v.0.1' 40
    }
    $halfChars = @([char]0, [char]0x2580, [char]0x2584, [char]0x2588)
    $rnd = New-Object System.Random
    $parts = New-Object System.Collections.Generic.List[object]
    $sb = New-Object System.Text.StringBuilder 16384
    $W = 0; $H = 0; $chars = $null; $cols = $null
    $result = $null; $t = 0
    $oldCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
    [Console]::Write("$ESC[?25l$ESC[2J")
    try {
        while (-not $result) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $ww = [Math]::Max(40, [Console]::WindowWidth - 1)
            $wh = [Math]::Max(20, [Console]::WindowHeight)
            if ($ww -ne $W -or $wh -ne $H) {
                $W = $ww; $H = $wh
                $chars = New-Object char[] ($W * $H); $cols = New-Object int[] ($W * $H)
                $half = New-Object int[] ($W * $H); $hcol = New-Object int[] ($W * $H)
                [Console]::Write("$ESC[2J")
            }
            [Array]::Clear($chars, 0, $chars.Length)

            # --- rockets and sparks ---
            $rockets = 0
            foreach ($p in $parts) { if ($p[6] -eq 0) { $rockets++ } }
            if ($rockets -lt 3 -and $rnd.NextDouble() -lt 0.12) {
                $rx = [double]$rnd.Next(4, $W - 4); $rvx = ($rnd.NextDouble() - 0.5) * 0.4
                $rvy = -0.9 - $rnd.NextDouble() * 0.6; $rc = [double]$Sparkle[$rnd.Next($Sparkle.Count)]
                $parts.Add((New-Particle $rx ($H - 1) $rvx $rvy 99 $rc 0))
            }
            $next = New-Object System.Collections.Generic.List[object]
            foreach ($p in $parts) {
                if ($p[6] -eq 0) {
                    $p[0] += $p[2]; $p[1] += $p[3]; $p[3] += 0.025
                    if ($p[3] -ge -0.15 -or $p[1] -lt 2) {
                        $n = $rnd.Next(28, 55)
                        for ($i = 0; $i -lt $n; $i++) {
                            $a = $rnd.NextDouble() * 6.2832; $s = 0.25 + $rnd.NextDouble() * 0.9
                            $c = if ($rnd.NextDouble() -lt 0.75) { $p[5] } else { $Sparkle[$rnd.Next($Sparkle.Count)] }
                            $next.Add((New-Particle $p[0] $p[1] ([Math]::Cos($a) * $s * 2.0) ([Math]::Sin($a) * $s) $rnd.Next(14, 32) $c 1))
                        }
                    } else {
                        $next.Add($p)
                        $ix = [int]$p[0]; $iy = [int]$p[1]
                        if ($ix -ge 0 -and $ix -lt $W -and $iy -ge 0 -and $iy -lt $H) { $chars[$iy * $W + $ix] = '|'; $cols[$iy * $W + $ix] = 250 }
                        if ($iy + 1 -lt $H -and $ix -ge 0 -and $ix -lt $W) { $chars[($iy + 1) * $W + $ix] = '.'; $cols[($iy + 1) * $W + $ix] = 208 }
                    }
                } else {
                    $p[0] += $p[2]; $p[1] += $p[3]; $p[3] += 0.03; $p[2] *= 0.96; $p[4] -= 1
                    $ix = [int]$p[0]; $iy = [int]$p[1]
                    if ($p[4] -gt 0 -and $ix -ge 0 -and $ix -lt $W -and $iy -ge 0 -and $iy -lt $H) {
                        $next.Add($p)
                        $ch = if ($p[4] -gt 22) { '*' } elseif ($p[4] -gt 12) { '+' } elseif ($p[4] -gt 5) { $dot } else { '.' }
                        $col = if ($p[4] -lt 6) { 240 } elseif ($rnd.NextDouble() -lt 0.08) { 231 } else { [int]$p[5] }
                        $chars[$iy * $W + $ix] = $ch; $cols[$iy * $W + $ix] = $col
                    }
                }
            }
            $parts = $next

            # --- title ---
            if ($Fun) {
                [Array]::Clear($half, 0, $half.Length)
                $sec = $t * 0.045
                $top = [Math]::Max(0, [int](($H - 30) / 2))
                $bx0 = [int](($W - $bigW) / 2); $bpy0 = ($top + 7) * 2
                $shineX = ($t * 2) % ($bigW + 40) - 20
                $pulse = [int][Math]::Round(([Math]::Sin($sec * 3) + 1) * 2)
                $core = $neonCore[$pulse]; $edge = $neonEdge[$pulse]
                # 1) THE SENTINEL: small acrobats; the I flies down to be the O in GREENHORN
                $dyO = [int][Math]::Round([Math]::Sin($sec * 2 + $holeI * 0.9) * 1.5)
                $mini1.Morph = @{ X = $bx0 + $big[$holeI].X + 5.0; Y = $bpy0 + 7 + $dyO; Col = $core; Rows = $bigO; Scale = 2.0 }
                Add-MiniLine $mini1 ($top + 3) $sec $t $W $H $half $hcol $rnd
                # 2) GREENHORN: big neon tube letters, breathing
                for ($i = 0; $i -lt $big.Count; $i++) {
                    if ($i -eq $holeI) { continue }
                    $gk = $big[$i].Ch
                    $rows = $Glyphs[$gk]
                    $dy = [int][Math]::Round([Math]::Sin($sec * 2 + $i * 0.9) * 1.5)
                    for ($r = 0; $r -lt 6; $r++) {
                        $row = $rows[$r]
                        for ($c = 0; $c -lt 5; $c++) {
                            if ($row[$c] -ne '#') { continue }
                            $baseX = $bx0 + $big[$i].X + $c * 2
                            # the outer columns of a stroke are the dark tube edge, the inside glows
                            $leftEdge = $c -eq 0 -or $row[$c - 1] -ne '#'; $rightEdge = $c -eq 4 -or $row[$c + 1] -ne '#'
                            $shiny = [Math]::Abs($baseX - $bx0 + $r * 2 - $shineX) -lt 4
                            for ($a = 0; $a -lt 2; $a++) {
                                $py = $bpy0 + $r * 2 + $a + $dy
                                if ($py -lt 0 -or ($py -shr 1) -ge $H) { continue }
                                $rowBase = ($py -shr 1) * $W; $bit = 1 + ($py -band 1)
                                for ($b = 0; $b -lt 2; $b++) {
                                    $px = $baseX + $b
                                    if ($px -lt 0 -or $px -ge $W) { continue }
                                    $idx = $rowBase + $px
                                    $col = if ($shiny) { 231 } elseif (($b -eq 0 -and $leftEdge) -or ($b -eq 1 -and $rightEdge)) { $edge } else { $core }
                                    $half[$idx] = $half[$idx] -bor $bit; $hcol[$idx] = $col
                                }
                            }
                        }
                    }
                }
                # 3) WSL INSTALLER HAS LANDED!: small, calm wave
                Add-MiniLine $mini3 ($top + 15) $sec $t $W $H $half $hcol $rnd
                # 4) the marquee, scrolling right to left, fading at the edges
                $mRow = $top + 19
                if ($mRow + 1 -lt $H) {
                    $mLen = $marquee.Length
                    for ($x = 0; $x -lt $W; $x++) {
                        $m = $marquee[($t + $x) % $mLen]
                        if (-not $m) { continue }
                        $col = if ($x -lt 4 -or $x -ge $W - 4) { 94 } elseif ($x -lt 9 -or $x -ge $W - 9) { 172 } else { 214 }
                        $up = $m -band 3; $dn = ($m -shr 2) -band 3
                        if ($up) { $idx = $mRow * $W + $x; $half[$idx] = $half[$idx] -bor $up; $hcol[$idx] = $col }
                        if ($dn) { $idx = ($mRow + 1) * $W + $x; $half[$idx] = $half[$idx] -bor $dn; $hcol[$idx] = $col }
                    }
                }
                for ($idx = 0; $idx -lt $half.Length; $idx++) {
                    if ($half[$idx]) { $chars[$idx] = $halfChars[$half[$idx]]; $cols[$idx] = $hcol[$idx] }
                }
            } else {
                $top = [Math]::Max(1, [int](($H - 18) / 2))
                $lines = @($line1)
                if ($line2.Width -le $W - 2) { $lines += $line2 } else { $lines += , (New-BigLine '' 1) }
                $li = 0
                foreach ($L in $lines) {
                    $x0 = [int](($W - $L.Width) / 2)
                    foreach ($g in $L.Letters) {
                        if ($g.Space) { $li++; continue }
                        $dy = [int][Math]::Round([Math]::Sin($t * 0.32 + $li * 0.75) * 1.3)
                        $dx = if ($rnd.NextDouble() -lt 0.18) { $rnd.Next(-1, 2) } else { 0 }
                        $col = $Rainbow[($li * 2 + $t) % $Rainbow.Count]
                        for ($r = 0; $r -lt 6; $r++) {
                            $row = $g.Rows[$r]; $y = $top + $r + $dy
                            if ($y -lt 0 -or $y -ge $H) { continue }
                            for ($c = 0; $c -lt $row.Length; $c++) {
                                if ($row[$c] -ne '#') { continue }
                                for ($k = 0; $k -lt $L.Sx; $k++) {
                                    $x = $x0 + $g.X + $c * $L.Sx + $k + $dx
                                    if ($x -ge 0 -and $x -lt $W) { $chars[$y * $W + $x] = $block; $cols[$y * $W + $x] = $col }
                                }
                            }
                        }
                        $li++
                    }
                    $top += 8
                }
                if ($line2.Width -gt $W - 2) {
                    $msg = $Text2.ToCharArray() -join ' '; $x0 = [int](($W - $msg.Length) / 2)
                    for ($i = 0; $i -lt $msg.Length; $i++) {
                        $y = $top - 6 + [int][Math]::Round([Math]::Sin($t * 0.4 + $i * 0.5))
                        $chars[$y * $W + $x0 + $i] = $msg[$i]; $cols[$y * $W + $x0 + $i] = $Rainbow[($i + $t) % $Rainbow.Count]
                    }
                }
            }

            # --- menu ---
            $menu = if ($Seconds -gt 0) { @(@('', 0), @('', 0), @('', 0), @('Press any key to continue ... (yes, ANY key)', 244)) } else { @(
                @('Need a hand installing WSL (Linux inside Windows)?', 231),
                @('', 0),
                @('[1]  Yes please - show me the way!', 46),
                @('[2]  No thanks - get me out of here', 203)
            ) }
            $my = $H - 6
            foreach ($m in $menu) {
                $txt = $m[0]; $x0 = [int](($W - 44) / 2)
                if ($txt.Length -gt 44) { $x0 = [int](($W - $txt.Length) / 2) }
                for ($i = 0; $i -lt $txt.Length -and $x0 + $i -lt $W; $i++) {
                    if ($x0 + $i -lt 0) { continue }
                    $chars[$my * $W + $x0 + $i] = $txt[$i]; $cols[$my * $W + $x0 + $i] = $m[1]
                }
                $my++
            }
            if ($Seconds -eq 0) {
                $hint = if ($script:MusicOn) { [string][char]0x266A + ' m = stop the disco' } else { 'm = DISCO! ' + [char]0x266B }
                $hx = $W - $hint.Length - 1
                for ($i = 0; $i -lt $hint.Length; $i++) { $chars[($H - 1) * $W + $hx + $i] = $hint[$i]; $cols[($H - 1) * $W + $hx + $i] = 239 }
            }
            if ($DryRun) {
                $badge = ' DRY-RUN: nothing gets changed '
                for ($i = 0; $i -lt $badge.Length; $i++) { $chars[$i] = $badge[$i]; $cols[$i] = if ($t % 20 -lt 10) { 214 } else { 220 } }
            }

            # --- render ---
            [void]$sb.Clear()
            $cur = -1
            for ($y = 0; $y -lt $H; $y++) {
                [void]$sb.Append("$ESC[$($y + 1);1H")
                $base = $y * $W
                for ($x = 0; $x -lt $W; $x++) {
                    $ch = $chars[$base + $x]
                    if ($ch -eq [char]0) { [void]$sb.Append(' '); continue }
                    $co = $cols[$base + $x]
                    if ($co -ne $cur) { [void]$sb.Append("$ESC[38;5;${co}m"); $cur = $co }
                    [void]$sb.Append($ch)
                }
            }
            [Console]::Write($sb.ToString())

            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($Seconds -gt 0) { $result = 'done' }
                elseif ($k.KeyChar -in '1', 'j', 'J' -or $k.Key -eq 'Enter') { $result = 'go' }
                elseif ($k.KeyChar -in 'm', 'M') { Switch-Music }
                elseif ($k.KeyChar -in '2', 'q', 'Q', 'n', 'N' -or $k.Key -eq 'Escape' -or
                    ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control))) { $result = 'quit' }
            }
            $t++
            if ($Seconds -gt 0 -and $t * 45 -ge $Seconds * 1000) { $result = 'done' }
            $left = 45 - $sw.ElapsedMilliseconds
            if ($left -gt 0) { Start-Sleep -Milliseconds $left }
        }
    } finally {
        [Console]::TreatControlCAsInput = $oldCtrlC
        [Console]::Write("$RST$ESC[2J$ESC[H$ESC[?25h")
    }
    return $result
}
#endregion

#region ---------- WSL helpers ----------
function Get-OsBuild { [int](Get-CimInstance Win32_OperatingSystem).BuildNumber }

function Test-WslCore {
    if ($Fresh) { return $false }
    try { $null = & wsl.exe --version 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Get-FeatureState([string]$name) {
    if ($Fresh) { return 'Disabled' }
    try { return [string](Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop).State }
    catch { return 'Unknown (needs admin)' }
}

function Get-Distros {
    if ($Fresh) { return @() }
    try {
        $out = & wsl.exe -l -q 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notlike 'docker-desktop*' })
    } catch { return @() }
}

function Get-DistroDisks {
    Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        if ($p.DistributionName -and $p.BasePath) {
            $base = $p.BasePath -replace '^\\\\\?\\', ''
            $file = if ($p.PSObject.Properties['VhdFileName'] -and $p.VhdFileName) { $p.VhdFileName } else { 'ext4.vhdx' }
            $vhd = Join-Path $base $file
            if ($p.DistributionName -notlike 'docker-desktop*' -and (Test-Path -LiteralPath $vhd)) { [pscustomobject]@{ Name = $p.DistributionName; Vhd = $vhd } }
        }
    }
}

# Runs a shell script as root inside the distro (base64 avoids all quoting trouble)
function Invoke-InDistro([string]$distro, [string]$script) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($script -replace "`r", ''))
    $b64 = [Convert]::ToBase64String($bytes)
    & wsl.exe -d $distro -u root -e sh -c "echo $b64 | base64 -d | sh"
}

function Format-GB([double]$bytes) { '{0:N2} GB' -f ($bytes / 1GB) }

# Saves where we are, so a restart (planned or not) brings us back to the same step
function Save-ResumeState([string]$reason = 'net') {
    if ($DryRun) { return }
    $state = [ordered]@{
        Step      = $script:CurrentStep
        Reason    = $reason
        Distro    = $script:Distro
        NetMode   = $script:NetMode
        WinIp     = $Cfg.WinIp
        WslIp     = $Cfg.WslIp
        Broadcast = $Cfg.Broadcast
        Done      = @($script:Done)
        Oops      = $script:OopsCount
        Saved     = (Get-Date).ToString('s')
    }
    try {
        New-Item -ItemType Directory -Force -Path $Cfg.DataDir | Out-Null
        $state | ConvertTo-Json | Set-Content -Path $Cfg.StateFile -Encoding UTF8
    } catch {}
}

# The safety net: a copy of me in a safe place, resume.ps1, and a one-shot logon task
# (elevated, so no UAC prompt) that starts me again after any restart, planned or not.
# -Quiet gives one friendly line instead of every action (used when the guide starts).
function Register-Resume([string]$reason = 'reboot', [switch]$Quiet) {
    $ps1 = @"
# Sentinel Greenhorn - one-shot resume after reboot. Removes its own task and itself.
`$bat = '$($Cfg.SelfCopy)'
for (`$i = 0; `$i -lt 90 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); `$i++) { Start-Sleep -Seconds 1 }
Start-Sleep -Seconds 4
Unregister-ScheduledTask -TaskName '$($Cfg.ResumeTask)' -Confirm:`$false -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath `$bat) { Start-Process -FilePath `$bat -ArgumentList '--go', '--resume' }
Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@
    $copy  = {
        New-Item -ItemType Directory -Force -Path $Cfg.DataDir | Out-Null
        if ($Self -ne $Cfg.SelfCopy) { Copy-Item -LiteralPath $Self -Destination $Cfg.SelfCopy -Force }
    }
    $write = { Set-Content -Path $Cfg.ResumePs1 -Value $ps1 -Encoding UTF8 }
    $task  = {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($Cfg.ResumePs1)`""
        $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $Cfg.ResumeTask -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
    }
    if ($Quiet) {
        if ($DryRun) { Say "  [DRY-RUN] Safety net: task '$($Cfg.ResumeTask)' + resume.ps1 + resume.json (so I pop up again after a restart)" 214; return }
        try {
            & $copy; & $write; & $task
            Save-ResumeState $reason
            Info "Safety net is up: if the PC restarts along the way, I'll pop up again on my own."
        } catch { Warn "Couldn't put up the safety net (carrying on anyway): $($_.Exception.Message)" }
        return
    }
    Invoke-Action 'Copy the helper to a safe place' $copy "copy `"$Self`" -> $($Cfg.SelfCopy)"
    Invoke-Action "Remember where we were ($($script:CurrentStep))" { Save-ResumeState $reason } "$($Cfg.StateFile)  <-  Step=$($script:CurrentStep), Reason=$reason"
    Invoke-Action 'Write the startup script resume.ps1' $write "$($Cfg.ResumePs1): wait for the desktop -> start $($Cfg.SelfCopy) --go --resume -> clean up after itself"
    Invoke-Action "Scheduled task '$($Cfg.ResumeTask)' that starts me when you log in" $task "Register-ScheduledTask $($Cfg.ResumeTask)  (at logon, as administrator - no UAC prompt)"
}

function Restore-ResumeState {
    $st = $null
    if (Test-Path $Cfg.StateFile) {
        try { $st = Get-Content -Raw -Path $Cfg.StateFile | ConvertFrom-Json } catch {}
        if (-not $DryRun) { Remove-Item -Path $Cfg.StateFile -Force -ErrorAction SilentlyContinue }
    }
    if (-not $st -and $DryRun) {
        # Dry-run preview without a real reboot: pretend we come back from the WSL install (or the BIOS)
        $st = [pscustomobject]@{ Step = $(if ($AfterBios) { 'Step-Precheck' } else { 'Step-Core' }); Reason = $(if ($AfterBios) { 'bios' } else { 'reboot' }); Done = @() }
    }
    if (-not $st -or -not $st.Step) { return $false }
    $script:ResumeStep = $st.Step
    if ($st.Distro)    { $script:Distro = $st.Distro }
    if ($st.NetMode)   { $script:NetMode = $st.NetMode }
    if ($st.WinIp)     { $Cfg.WinIp = $st.WinIp; $Cfg.WslIp = $st.WslIp; $Cfg.Broadcast = $st.Broadcast }
    foreach ($d in @($st.Done)) { if ($d) { $script:Done.Add([string]$d) } }
    if ($st.Oops) { $script:OopsCount = [int]$st.Oops }
    if ($st.Reason -eq 'bios') { $script:AfterBios = $true }
    return $true
}

# Takes the safety net down again: the logon task, resume.json and resume.ps1
function Clear-Resume([switch]$Quiet) {
    if ($DryRun) { if (-not $Quiet) { Say "  [DRY-RUN] Take down the safety net (task + resume.json + resume.ps1)" 214 }; return }
    Unregister-ScheduledTask -TaskName $Cfg.ResumeTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $Cfg.StateFile, $Cfg.ResumePs1 -Force -ErrorAction SilentlyContinue
    if (-not $Quiet) { Ok 'Safety net taken down again. All tidied up - the PC is just like before, only better!' }
}

function Request-Reboot {
    Warn 'Windows needs a little nap (a restart) to finish this. Have you tried turning it off and on again?'
    Info 'No worries: when you log back in, I''ll be right here and we carry on where we left off.'
    Register-Resume 'reboot'
    if (Ask-YesNo 'Restart the PC now? (save anything you have open first!)' $true) {
        Invoke-Action 'Restart in 15 seconds' { & shutdown.exe /r /t 15 /c 'Sentinel Greenhorn: restarting for WSL' } 'shutdown.exe /r /t 15'
    } else {
        Info 'OK! Restart the PC yourself whenever it suits you - I''ll pop up again on my own afterwards.'
    }
}
#endregion

#region ---------- virtualization (BIOS) help ----------
# Where the setting usually lives, per brand. Matched against PC + motherboard maker.
$BiosHints = @(
    @{ M = 'ASUS';                 Key = 'F2 or Del';    Path = 'Press F7 (Advanced Mode) -> Advanced -> CPU Configuration' }
    @{ M = 'MSI|Micro-Star';       Key = 'Del';          Path = 'OC (Overclocking) -> CPU Features  (or Advanced -> CPU Configuration)' }
    @{ M = 'Gigabyte';             Key = 'Del';          Path = 'Tweaker (or M.I.T.) -> Advanced CPU Settings' }
    @{ M = 'ASRock';               Key = 'F2 or Del';    Path = 'Advanced -> CPU Configuration' }
    @{ M = 'Lenovo';               Key = 'F1 or F2 (ThinkPad: Enter, then F1)'; Path = 'Security -> Virtualization  (IdeaPad/Legion: Configuration)' }
    @{ M = 'HP|Hewlett';           Key = 'Esc, then F10'; Path = 'Advanced -> System Options  (or Security -> System Security)' }
    @{ M = 'Dell|Alienware';       Key = 'F2';           Path = 'Virtualization Support -> Virtualization' }
    @{ M = 'Acer';                 Key = 'F2 or Del';    Path = 'Advanced (or Main)' }
    @{ M = 'Samsung';              Key = 'F2';           Path = 'Advanced' }
    @{ M = 'Microsoft';            Key = 'hold Volume Up + press Power'; Path = 'Surface usually has it on already - try Windows Update' }
)
$script:BiosRebootScheduled = $false

function Show-VirtualizationHelp($cs, $cpu) {
    $isAmd   = $cpu.Manufacturer -match 'AMD'
    $setting = if ($isAmd) { "'SVM Mode' (also called 'AMD-V' or 'Virtualization')" } else { "'Intel Virtualization Technology' (also called 'VT-x' or 'VMX')" }
    $board   = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Manufacturer
    $makers  = "$($cs.Manufacturer) $board"
    $hint    = $BiosHints | Where-Object { $makers -match $_.M } | Select-Object -First 1
    if (-not $hint) { $hint = @{ Key = 'F2 or Del'; Path = "Look in the menus 'Advanced', 'CPU Configuration', 'Security' or 'Tweaker'" } }
    $uefi = ($env:firmware_type -eq 'UEFI')

    Oops 'Virtualization is switched OFF in the BIOS - and without it Linux won''t start.' 'We''ll fix it together! It takes a couple of minutes, and I''ll explain everything.'
    Say '  +--------------------------------------------------------------------+' 51
    Say "     Your PC:  $($cs.Manufacturer) $($cs.Model)" 231
    Say "     CPU:      $($cpu.Name.Trim())" 231
    Say '  +--------------------------------------------------------------------+' 51
    if ($uefi) { Say '   1. I''ll restart the PC straight into the BIOS for you - no frantic key mashing!' 231 }
    else       { Say "   1. Restart the PC and keep tapping $($hint.Key) while the logo is showing." 231 }
    Say "   2. Go to:  $($hint.Path)" 231
    Say "   3. Find $setting" 231
    Say '      and set it to  Enabled' 46
    Say '   4. Save and exit: press F10 and pick Yes / OK' 231
    Say '   5. Windows starts again, and I pop up on my own to check that it worked.' 231
    Say '  +--------------------------------------------------------------------+' 51
    Info 'Arrow keys + Enter to get around (the mouse works on many PCs too).'
    Info 'Do NOT change anything else in there - and if you goof: pick "Discard changes" / "Exit without saving".'
    Info 'Tip: take a photo of this screen with your phone, so you have the recipe with you in the BIOS.'
    [Console]::WriteLine()

    $q = if ($uefi) { 'Restart the PC straight into the BIOS now? (save anything you have open first!)' } else { 'Restart the PC now?' }
    if (Ask-YesNo $q $true) {
        Register-Resume 'bios'
        if ($uefi) {
            Invoke-Action 'Restart straight into the BIOS in 10 seconds' { & shutdown.exe /r /fw /t 10 /c 'Sentinel Greenhorn: off to the BIOS!' } 'shutdown.exe /r /fw /t 10' `
                "Restart the PC yourself and press $($hint.Key) while the logo is showing."
        } else {
            Invoke-Action 'Restart in 15 seconds' { & shutdown.exe /r /t 15 /c "Sentinel Greenhorn: press $($hint.Key) for the BIOS!" } 'shutdown.exe /r /t 15'
        }
        Say '  Bon voyage into the BIOS, Mr. Greenhorn! See you on the other side.' 219
        $script:BiosRebootScheduled = $true
    }
}

function Test-HypervisorOff {
    try { $o = & bcdedit.exe /enum '{current}' 2>$null; return [bool]($o -match 'hypervisorlaunchtype\s+Off') } catch { return $false }
}
#endregion

#region ---------- network sniffing ----------
function ConvertTo-IpNumber([string]$ip) {
    $b = ([Net.IPAddress]::Parse($ip)).GetAddressBytes(); [Array]::Reverse($b)
    [uint64][BitConverter]::ToUInt32($b, 0)
}

function Test-NetOverlap([string]$a, [int]$pa, [string]$b, [int]$pb) {
    $p = [Math]::Min($pa, $pb)
    $mask = if ($p -eq 0) { [uint64]0 } else { ([uint64]4294967295 -shl (32 - $p)) -band [uint64]4294967295 }
    ((ConvertTo-IpNumber $a) -band $mask) -eq ((ConvertTo-IpNumber $b) -band $mask)
}

# The router, home network and this PC's address, from the best default route
function Get-LanInfo {
    $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.InterfaceAlias -notlike 'vEthernet (WSL*' } |
        Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric }
    foreach ($r in $routes) {
        # Skip stale routes (e.g. a hotspot with only an APIPA address); prefer the address on the router's network
        $all = @(Get-NetIPAddress -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254.*' })
        $a = $all | Where-Object { Test-NetOverlap $_.IPAddress $_.PrefixLength $r.NextHop $_.PrefixLength } | Select-Object -First 1
        if (-not $a) { continue }
        $mask = ([uint64]4294967295 -shl (32 - $a.PrefixLength)) -band [uint64]4294967295
        $n = (ConvertTo-IpNumber $a.IPAddress) -band $mask
        $net = '{0}.{1}.{2}.{3}' -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255)
        return [pscustomobject]@{ Gateway = $r.NextHop; Alias = $r.InterfaceAlias; Ip = $a.IPAddress; Prefix = [int]$a.PrefixLength; Net = $net }
    }
    return $null
}

# Every IPv4 network Windows already knows about (LAN, VPN, Hyper-V, ...) except our own fixed link
function Get-UsedNets([string]$ownNet) {
    $nets = @()
    foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        if ($a.IPAddress -like '127.*' -or $a.IPAddress -like '169.254.*') { continue }
        if ($ownNet -and (Test-NetOverlap $a.IPAddress 24 $ownNet 24)) { continue }
        $nets += , @($a.IPAddress, [int]$a.PrefixLength)
    }
    foreach ($r in @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        $p = $r.DestinationPrefix.Split('/'); $len = [int]$p[1]
        if ($len -lt 8 -or $len -gt 30 -or $p[0] -match '^(127|169\.254|22[4-9]|2[3-5]\d)\.') { continue }
        if ($ownNet -and (Test-NetOverlap $p[0] 24 $ownNet 24)) { continue }
        $nets += , @($p[0], $len)
    }
    $nets
}

function Test-IpTaken([string]$ip) {
    $nb = Get-NetNeighbor -IPAddress $ip -ErrorAction SilentlyContinue |
        Where-Object { "$($_.State)" -in 'Reachable', 'Stale', 'Delay', 'Probe', 'Permanent' }
    if ($nb) { return $true }
    $o = & ping.exe -n 1 -w 400 $ip
    return [bool]($o -match 'TTL=')
}

# Returns a reason string if x.y.z.0/24 can't be used for the WSL link, else $null
function Test-LinkNet([string]$c24, $used) {
    foreach ($u in $used) { if (Test-NetOverlap "$c24.0" 24 $u[0] $u[1]) { return "clashes with $($u[0])/$($u[1])" } }
    foreach ($h in '1', '2') { if (Test-IpTaken "$c24.$h") { return "$c24.$h is already taken" } }
    return $null
}

function Set-LinkNet([string]$c24, [string]$wslHost = '2') {
    $Cfg.WinIp = "$c24.1"; $Cfg.WslIp = "$c24.$wslHost"; $Cfg.Broadcast = "$c24.255"
}

function Select-LinkNet {
    # Re-run: keep what we set up last time
    $helperPath = Join-Path $Cfg.DataDir 'wsl-fixed-ip.ps1'
    $own = $null
    if (Test-Path $helperPath) {
        $m = Select-String -Path $helperPath -Pattern "IPAddress '(\d+\.\d+\.\d+)\.1'" | Select-Object -First 1
        if ($m) { $own = $m.Matches[0].Groups[1].Value }
    }
    if ($own) { Set-LinkNet $own; Info "Keeping the setup from last time ($own.x)."; return }
    $used = Get-UsedNets $null
    foreach ($c in '192.168.250', '192.168.251', '192.168.249', '10.250.250', '10.251.251', '172.31.250') {
        $why = Test-LinkNet $c $used
        if (-not $why) { Set-LinkNet $c; Ok "Found a free network for Linux: $c.0/24  (checked against the router, VPN and everything else)"; return }
        Info "  $c.0/24 is taken ($why) - trying the next one ..."
    }
    Oops 'Couldn''t find a free network among my suggestions.' 'Pick [1] and type your own IP, e.g. 10.123.45.2'
}
#endregion

#region ---------- guide steps ----------
$script:Distro  = $null
$script:NetMode = 'none'
$script:Sparse  = $true
$script:Done    = New-Object System.Collections.Generic.List[string]
$script:Status  = 'ok'
# Steps report through $script:Status instead of output, so they can be called
# without capturing - interactive tools (wsl --install) need the real console.
function Set-Status([string]$s) { $script:Status = $s }

function Step-Precheck {
    Step 'Saying hello to your PC'
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $virt = [bool]$cs.HypervisorPresent -or [bool]$cpu.VirtualizationFirmwareEnabled
    if ($DryRun -and $SimNoVirt) { $virt = $false }
    $free = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
    $ramGb = [Math]::Round($cs.TotalPhysicalMemory / 1GB)

    Info "$($os.Caption)  (build $build)"
    Info "Memory: $ramGb GB    Free on $($env:SystemDrive) $(Format-GB $free)"
    if ($IsAdmin) { Ok 'Running as administrator' } elseif ($DryRun) { Warn 'Not administrator (fine in dry-run)' }

    if ($build -lt 19041) { Oops "Your Windows (build $build) is a bit too old for WSL 2." 'Run Windows Update (Start -> Settings -> Windows Update), restart the PC and run me again.'; return (Set-Status 'stop') }
    if ($build -lt 22000) { Warn 'This isn''t Windows 11, but WSL 2 works anyway.' } else { Ok 'Windows 11 - perfect' }
    if ($virt) {
        Ok 'Virtualization is switched on'
        if ($script:AfterBios -or $AfterBios) { Say '  *** VIRTUALIZATION IS ON! You went into the BIOS and lived to tell the tale! ***' 226 }
    } else {
        if ($script:AfterBios -or $AfterBios) { Say '  Hmm, it''s still off. Maybe it didn''t get saved with F10? Let''s go one more round!' 214 }
        Show-VirtualizationHelp $cs $cpu
        if ($DryRun) { Info '(In dry-run we pretend you fixed it in the BIOS, and carry on.)' }
        elseif ($script:BiosRebootScheduled) { return (Set-Status 'reboot') }
        elseif (-not (Ask-YesNo 'Carry on with the rest anyway? (Linux won''t start until virtualization is on)' $false)) { return (Set-Status 'stop') }
    }
    if ($free -lt 10GB) { Warn 'Less than 10 GB free - Linux needs a little room to stretch its legs.' }
    return (Set-Status 'ok')
}

function Step-Core {
    Step 'The WSL engine'
    $fWsl = Get-FeatureState 'Microsoft-Windows-Subsystem-Linux'
    $fVmp = Get-FeatureState 'VirtualMachinePlatform'
    $core = Test-WslCore
    Info "Windows feature 'Subsystem for Linux':      $fWsl"
    Info "Windows feature 'Virtual Machine Platform':  $fVmp"
    if ($fWsl -eq 'EnablePending' -or $fVmp -eq 'EnablePending') { Request-Reboot; return (Set-Status 'reboot') }

    if ($core -and $fVmp -ne 'Disabled') {
        $ver = (& wsl.exe --version 2>$null | Select-Object -First 1)
        Ok "WSL is already installed ($ver)"
        if (-not $DryRun -and -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent -and (Test-HypervisorOff)) {
            Oops 'The Windows hypervisor is switched off (hypervisorlaunchtype = Off). Some games and programs do that - but then Linux won''t start.' 'I''ll switch it back on for you now, and then a quick restart.'
            Invoke-Action 'Switch on the Windows hypervisor' { & bcdedit.exe /set hypervisorlaunchtype auto } 'bcdedit /set hypervisorlaunchtype auto'
            Request-Reboot
            return (Set-Status 'reboot')
        }
        return (Set-Status 'ok')
    }
    Info 'WSL isn''t installed yet. No worries - we''re flipping the right switches in Windows now.'
    if (-not (Ask-YesNo 'Shall we install WSL now? (say yes, it''s fun!)' $true)) { return (Set-Status 'stop') }

    $script:rc = 0
    Invoke-Action 'Install WSL' { & wsl.exe --install --no-distribution; $script:rc = $LASTEXITCODE; $global:LASTEXITCODE = 0 } 'wsl.exe --install --no-distribution'
    if (-not $DryRun -and $script:rc -ne 0) {
        Oops "wsl --install gave error code $($script:rc)." 'No sweat! I have a plan B and I''m trying the old-school way (DISM) myself right now ...'
        & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Host
        & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Host
    }
    $script:Done.Add('WSL installert')
    if ($DryRun) {
        Info '(This is where the PC would normally need a restart. In dry-run we pretend it happened.)'
        Request-Reboot
        return (Set-Status 'ok')
    }
    if ((Get-FeatureState 'VirtualMachinePlatform') -eq 'EnablePending' -or -not (Test-WslCore)) { Request-Reboot; return (Set-Status 'reboot') }
    return (Set-Status 'ok')
}

function Step-Distro {
    Step 'Picking a Linux'
    Invoke-Action 'Update WSL to the latest version' { & wsl.exe --update } 'wsl.exe --update'
    Invoke-Action 'Make WSL 2 the default' { & wsl.exe --set-default-version 2 | Out-Null } 'wsl.exe --set-default-version 2'

    $have = Get-Distros
    if ($have.Count -gt 0) {
        Ok ("Installed distros: " + ($have -join ', '))
        if ($have.Count -eq 1) { $script:Distro = $have[0] }
        else {
            for ($i = 0; $i -lt $have.Count; $i++) { Say ("    [{0}] {1}" -f ($i + 1), $have[$i]) 231 }
            $c = Ask-Choice 'Which one shall we set up? (Enter = 1)' (1..$have.Count | ForEach-Object { "$_" }) '1'
            $script:Distro = $have[[int]$c - 1]
        }
        Info "We'll carry on with: $($script:Distro)"
        return (Set-Status 'ok')
    }

    Say '    [1] Ubuntu         (recommended - most popular, most guides online)' 231
    Say '    [2] Ubuntu-24.04   (a fixed LTS version)' 231
    $c = Ask-Choice 'Pick a distro (Enter = 1)' @('1', '2') '1'
    $pick = @('Ubuntu', 'Ubuntu-24.04')[[int]$c - 1]
    [Console]::WriteLine()
    Info "Now downloading $pick. At the end it asks for:"
    Info '  1) a username  (lower case, no spaces, e.g. greenhorn)'
    Info '  2) a password  (it does NOT show while you type - totally normal, nothing is broken!)'
    Info 'When you see a Linux line ending in $ , type  exit  and press Enter to come back here.'
    if (-not (Ask-YesNo "Ready to install $pick?" $true)) { return (Set-Status 'stop') }
    Invoke-Action "Install $pick" { & wsl.exe --install -d $pick } "wsl.exe --install -d $pick" "Check that the internet works, restart the PC and run me again."
    $script:Distro = $pick
    if (-not $DryRun) {
        if ((Get-Distros) -notcontains $pick) { Oops "Couldn't find $pick after the install." "Restart the PC and run me again - that's often all it takes.`nIf that doesn't help: $DefaultFix"; return (Set-Status 'stop') }
        & wsl.exe --set-default $pick | Out-Null
    }
    $script:Done.Add("$pick installert")
    Ok "$pick is in the house!"
    return (Set-Status 'ok')
}

function Step-NetworkChoice {
    Step 'Fixed IP address'
    Info 'Normally WSL gets a new random IP every time the PC starts. That''s a pain for servers, SSH and friends.'
    Info 'First I''ll have a little sniff around your network ...'
    $script:Lan = Get-LanInfo
    if ($script:Lan) {
        Say "      Your router (gateway):  $($script:Lan.Gateway)" 231
        Say "      Your home network:      $($script:Lan.Net)/$($script:Lan.Prefix)   (via $($script:Lan.Alias))" 231
        Say "      Your PC:                $($script:Lan.Ip)" 231
    } else { Warn 'No router found - are you offline right now? That''s fine too.' }
    Select-LinkNet
    [Console]::WriteLine()
    Say "    [1] Its own fixed IP: Linux is ALWAYS $($Cfg.WslIp), Windows is $($Cfg.WinIp)  (recommended)" 231
    Info "        + the name '$($Cfg.HostName)' works from Windows"
    Say '    [2] Mirrored network: Linux shares the Windows IP, localhost works both ways' 231
    Say '    [3] Skip' 231
    $c = Ask-Choice 'Pick one (Enter = 1)' @('1', '2', '3') '1'
    $script:NetMode = @('fixed', 'mirrored', 'none')[[int]$c - 1]
    if ($script:NetMode -eq 'fixed') {
        $used = $null
        while ($true) {
            $own = Read-Host "  Enter = use $($Cfg.WslIp), or type your own IP for Linux (e.g. 10.0.77.2)"
            if ([string]::IsNullOrWhiteSpace($own)) { break }
            $own = $own.Trim(); $ipObj = $null
            if (-not [Net.IPAddress]::TryParse($own, [ref]$ipObj) -or $own -notmatch '^(\d+\.\d+\.\d+)\.(\d+)$' -or [int]$Matches[2] -lt 2 -or [int]$Matches[2] -gt 254) {
                Warn 'That doesn''t quite look like an IP address. Try something like 10.0.77.2 (last number between 2 and 254).'; continue
            }
            $c24 = $Matches[1]; $hostNo = $Matches[2]
            if ($null -eq $used) { $used = Get-UsedNets $null }
            $why = $null
            foreach ($u in $used) { if (Test-NetOverlap "$c24.0" 24 $u[0] $u[1]) { $why = "that network clashes with $($u[0])/$($u[1])"; break } }
            if (-not $why -and (Test-IpTaken "$c24.1")) { $why = "$c24.1 (the Windows side) is already taken" }
            if (-not $why -and (Test-IpTaken $own)) { $why = "$own is already taken" }
            if ($why) { Warn "Whoops, no can do: $why. Try another one!"; continue }
            Set-LinkNet $c24 $hostNo
            Ok "$own is free - it's all yours!"
            break
        }
    }
    if ($script:NetMode -eq 'mirrored' -and (Get-OsBuild) -lt 22621) {
        Warn 'Mirrored networking needs Windows 11 22H2 or newer. Using a fixed IP of its own instead.'
        $script:NetMode = 'fixed'
    }
    Ok "Picked: $($script:NetMode)"
    return (Set-Status 'ok')
}

function Step-WslConfig {
    Step 'Speed and memory (.wslconfig)'
    $ramGb = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $mem = [Math]::Max(2, [Math]::Floor($ramGb / 2))
    Info "Linux gets at most $mem GB of the PC's $ramGb GB of memory, and hands unused memory back to Windows."
    Info "A 'sparse' disk means the Linux disk shrinks by itself when you delete files -"
    Info 'the space goes straight back to Windows, without you lifting a finger.'
    Say '  >>> You''re supposed to press Yes here, Mr. Greenhorn! <<<' 226
    if (Ask-YesNo 'Switch on the sparse disk?' $true) { Ok 'Sparse disk: ON. Smart cookie!' }
    else { Say '  No? Nice try, Mr. Greenhorn! It''s getting switched on anyway - Sentinel has spoken. ;)' 219 }
    $script:Sparse = $true

    $lines = @(
        "# Generated by Sentinel Greenhorn $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        '[wsl2]',
        "memory=${mem}GB",
        'swap=4GB',
        'localhostForwarding=true'
    )
    if ($script:NetMode -eq 'mirrored') { $lines += 'networkingMode=mirrored', 'dnsTunneling=true', 'firewall=true', 'autoProxy=true' }
    $lines += '', '[experimental]', 'autoMemoryReclaim=gradual'
    if ($script:Sparse) { $lines += 'sparseVhd=true' }
    if ($script:NetMode -eq 'mirrored') { $lines += 'hostAddressLoopback=true' }

    $path = Join-Path $env:USERPROFILE '.wslconfig'
    $bak = "$path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if (Test-Path $path) {
        Invoke-Action "Back up the old .wslconfig" { Copy-Item $path $bak } "copy $path -> $bak"
    }
    Invoke-Action "Write $path" { Set-Content -Path $path -Value $lines -Encoding ASCII } ($lines -join "`n")
    Invoke-Action 'Restart WSL so the settings kick in' { & wsl.exe --shutdown } 'wsl.exe --shutdown'

    if ($script:Sparse -and $script:Distro) {
        Invoke-Action "Make the $($script:Distro) disk sparse" {
            & wsl.exe --manage $script:Distro --set-sparse true
            # Newer WSL versions want an explicit --allow-unsafe for existing disks
            if ($LASTEXITCODE -ne 0) { & wsl.exe --manage $script:Distro --set-sparse true --allow-unsafe }
            if ($LASTEXITCODE -ne 0) { Warn 'This WSL version refused sparse on an existing disk - no problem, the clean-up step does the job instead.' }
            $global:LASTEXITCODE = 0
        } "wsl.exe --manage $($script:Distro) --set-sparse true"
    }
    $script:Done.Add('.wslconfig satt opp')
    return (Set-Status 'ok')
}

function Step-FixedIp {
    Step 'Setting up the fixed IP'
    if ($script:NetMode -eq 'none') { Info 'Skipped.'; return (Set-Status 'ok') }
    if ($script:NetMode -eq 'mirrored') {
        Ok 'Mirrored networking is set in .wslconfig - Linux now uses the same IP as Windows.'
        Info 'Servers in Linux are reachable on localhost from Windows, and from other PCs on the Windows IP.'
        if ($script:Lan) {
            Info "Phones, TVs and other PCs reach Linux on $($script:Lan.Ip)."
            Info "Tip: reserve $($script:Lan.Ip) for this PC in your router ($($script:Lan.Gateway)), so it never changes."
            if (Ask-YesNo "Open the router page ($($script:Lan.Gateway)) in the browser now?" $false) {
                Invoke-Action 'Open the router page' { Start-Process "http://$($script:Lan.Gateway)" } "start http://$($script:Lan.Gateway)"
            }
        }
        $script:Done.Add('Mirrored networking')
        return (Set-Status 'ok')
    }
    if (-not $script:Distro) { Warn 'No distro picked - skipping.'; return (Set-Status 'ok') }

    $d = $script:Distro
    $ipCmd = "ip addr add $($Cfg.WslIp)/$($Cfg.Prefix) broadcast $($Cfg.Broadcast) dev eth0 label eth0:1 2>/dev/null || true"

    # 1) Linux side: add the fixed address every time the distro boots
    $sh = @"
set -e
f=/etc/wsl.conf
if [ -f "`$f" ]; then cp "`$f" "`$f.bak-greenhorn"; else touch "`$f"; fi
sed -i '/# greenhorn-fixed-ip/,+1d' "`$f"
line='command = "$ipCmd"'
if grep -q '^\[boot\]' "`$f"; then
  if grep -q '^command' "`$f"; then echo 'wsl.conf already has a [boot] command - not touching it'; exit 3; fi
  sed -i "/^\[boot\]/a # greenhorn-fixed-ip\n`$line" "`$f"
else
  printf '\n[boot]\n# greenhorn-fixed-ip\n%s\n' "`$line" >> "`$f"
fi
$ipCmd
echo 'wsl.conf updated'
"@
    Invoke-Action "Linux: $d always gets $($Cfg.WslIp) (via /etc/wsl.conf)" {
        Invoke-InDistro $d $sh
        if ($LASTEXITCODE -eq 3) {
            Oops '/etc/wsl.conf already has its own boot command, and I won''t step on its toes.' "Type  sudo nano /etc/wsl.conf  in Linux and add this to the end of the command line:`n  ; $ipCmd"
            $global:LASTEXITCODE = 0
        }
    } "[boot] command = `"$ipCmd`"   (in /etc/wsl.conf)"

    # 2) Windows side: a small script that puts $WinIp on the WSL adapter
    $helper = @"
# Sentinel Greenhorn - keeps the fixed Windows-side IP on the WSL adapter
`$ErrorActionPreference = 'SilentlyContinue'
`$a = Get-NetAdapter -IncludeHidden | Where-Object { `$_.Name -like 'vEthernet (WSL*' } | Select-Object -First 1
if (-not `$a) {
    & wsl.exe -d '$d' -u root -e /bin/true
    for (`$i = 0; `$i -lt 30 -and -not `$a; `$i++) {
        Start-Sleep -Seconds 1
        `$a = Get-NetAdapter -IncludeHidden | Where-Object { `$_.Name -like 'vEthernet (WSL*' } | Select-Object -First 1
    }
}
if (-not `$a) { exit 1 }
if (-not (Get-NetIPAddress -InterfaceIndex `$a.ifIndex -IPAddress '$($Cfg.WinIp)')) {
    New-NetIPAddress -InterfaceIndex `$a.ifIndex -IPAddress '$($Cfg.WinIp)' -PrefixLength $($Cfg.Prefix) | Out-Null
}
"@
    $helperPath = Join-Path $Cfg.DataDir 'wsl-fixed-ip.ps1'
    Invoke-Action "Windows: write the helper script $helperPath" {
        New-Item -ItemType Directory -Force -Path $Cfg.DataDir | Out-Null
        Set-Content -Path $helperPath -Value $helper -Encoding UTF8
    } "New-NetIPAddress $($Cfg.WinIp)/$($Cfg.Prefix) on 'vEthernet (WSL...)'"

    # 3) Scheduled task: at logon + every 5 minutes (the adapter is recreated when WSL restarts)
    Invoke-Action "Scheduled task '$($Cfg.TaskName)' (at logon + every 5 minutes)" {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helperPath`""
        $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $trg.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition
        $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Register-ScheduledTask -TaskName $Cfg.TaskName -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
    } "Register-ScheduledTask $($Cfg.TaskName) -> powershell -File $helperPath"

    # 4) Name in the Windows hosts file
    $hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $entry = "$($Cfg.WslIp)`t$($Cfg.HostName)`t# greenhorn-wsl"
    Invoke-Action "Add '$($Cfg.HostName)' to the hosts file" {
        $cur = @(Get-Content $hosts -ErrorAction SilentlyContinue)
        $new = @($cur | Where-Object { $_ -notmatch '# greenhorn-wsl' }) + $entry
        if (($cur -join "`n") -ne ($new -join "`n")) {
            Copy-Item $hosts "$hosts.bak-greenhorn" -Force
            Set-Content -Path $hosts -Value $new -Encoding ASCII
        }
    } "$hosts  +=  $entry"

    # 5) Apply now and test
    Invoke-Action 'Switch it on now and test' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helperPath
        Invoke-InDistro $d $ipCmd
        if (Test-Connection -ComputerName $Cfg.WslIp -Count 1 -Quiet) { Ok "Windows -> Linux ($($Cfg.WslIp)) answers!" }
        else { Oops "Linux ($($Cfg.WslIp)) isn't answering ping yet." "Restart the PC - that settles everything. Or run:  schtasks /run /tn $($Cfg.TaskName)" }
    } "ping $($Cfg.WslIp)"
    $script:Done.Add("Fixed IP: Linux $($Cfg.WslIp) / Windows $($Cfg.WinIp) / name $($Cfg.HostName)")
    return (Set-Status 'ok')
}

function Step-Disk {
    Step 'Spring cleaning the disk'
    Info 'The Linux disk is like a garage: it fills up when you download stuff, but it does NOT tidy itself.'
    Info 'So now we do a proper spring clean: take out the trash, sweep the floor and pack it all up. Vacuum cleaner ready!'
    if (-not (Ask-YesNo 'Free up disk space now?' $true)) { return (Set-Status 'ok') }

    $disks = @(Get-DistroDisks)
    if ($DryRun -and $disks.Count -eq 0 -and $script:Distro) {
        $disks = @([pscustomobject]@{ Name = $script:Distro; Vhd = "$env:LOCALAPPDATA\wsl\{guid}\ext4.vhdx" })
    }
    if ($disks.Count -eq 0) { Warn 'No Linux disks found.'; return (Set-Status 'ok') }

    $clean = @'
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
journalctl --vacuum-size=50M 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
fstrim -av 2>/dev/null || true
'@
    $before = @{}
    foreach ($k in $disks) {
        if (Test-Path -LiteralPath $k.Vhd) { $before[$k.Name] = (Get-Item -LiteralPath $k.Vhd).Length; Info "$($k.Name): $(Format-GB $before[$k.Name])  ($($k.Vhd))" }
        Invoke-Action "Tidy up inside $($k.Name) (apt cache, logs, temp) + fstrim" { Invoke-InDistro $k.Name $clean } 'apt-get clean; journalctl --vacuum-size=50M; rm -rf /tmp/*; fstrim -av'
    }
    Invoke-Action 'Switch off WSL so the disk can be compacted' { & wsl.exe --shutdown; Start-Sleep -Seconds 3 } 'wsl.exe --shutdown'

    $useOptimize = [bool](Get-Command Optimize-VHD -ErrorAction SilentlyContinue)
    foreach ($k in $disks) {
        $show = if ($useOptimize) { "Optimize-VHD -Path `"$($k.Vhd)`" -Mode Full" }
                else { "diskpart: select vdisk file=`"$($k.Vhd)`" / attach vdisk readonly / compact vdisk / detach vdisk" }
        Invoke-Action "Compact the $($k.Name) disk" {
            try {
                if ($useOptimize) { Optimize-VHD -Path $k.Vhd -Mode Full -ErrorAction Stop }
                else {
                    $tmp = Join-Path $env:TEMP 'greenhorn-diskpart.txt'
                    @("select vdisk file=`"$($k.Vhd)`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk') |
                        Set-Content -Path $tmp -Encoding Oem
                    & diskpart.exe /s $tmp | Out-Host
                    Remove-Item $tmp -ErrorAction SilentlyContinue
                }
                $after = (Get-Item -LiteralPath $k.Vhd).Length
                Ok ("{0}: {1} -> {2}  (saved {3})" -f $k.Name, (Format-GB $before[$k.Name]), (Format-GB $after), (Format-GB ($before[$k.Name] - $after)))
            } catch { Oops "Compacting $($k.Name) failed: $($_.Exception.Message)" 'Close all Linux windows and VS Code, and run me again - then the disk is free.' }
        } $show
    }
    $script:Done.Add('Diskplass ryddet')
    return (Set-Status 'ok')
}

function Step-Verify {
    Step 'Does Linux work? (the big test)'
    if (-not $script:Distro) { Oops 'No Linux distro to test.' 'Run me again and pick a distro in step 3.'; return (Set-Status 'stop') }
    $d = $script:Distro
    if ($DryRun -and (Get-Distros) -notcontains $d) {
        Info "(dry-run: $d doesn't exist here, so I pretend all the checks went fine)"
        return (Set-Status 'ok')
    }
    Info "Knock knock! Checking whether anyone is home in $d ..."
    $probe = @'
echo BARD_OK
uname -r
. /etc/os-release
echo "$ID|$VERSION_ID|$PRETTY_NAME"
ps -p 1 -o comm=
getent hosts github.com >/dev/null && echo DNS_OK
'@
    $out = @(Invoke-InDistro $d $probe 2>$null)
    $fails = 0
    if ($out -contains 'BARD_OK') { Ok "$d answers - Linux is alive!" }
    else {
        Oops "$d didn't answer." "Restart the PC and run me again.`nIf that doesn't help: open Start, type wsl and see what it says - take a screenshot and send it to Sentinel."
        return (Set-Status 'stop')
    }
    if ($out[1] -match 'WSL2') { Ok "WSL 2 (kernel $($out[1]))" }
    else { $fails++; Oops "$d is running on old WSL 1." "Type this in PowerShell (as admin):  wsl --set-version $d 2" }
    $os = "$($out[2])".Split('|')
    if ($os[0] -eq 'ubuntu' -and $os[1] -in '22.04', '24.04', '26.04') { Ok "$($os[2]) - just what Tortugarr likes" }
    else { Warn "$($os[2]): Tortugarr is tested on Ubuntu 22.04, 24.04 and 26.04. It may work anyway, but Ubuntu is the safe bet." }
    if ($out -contains 'systemd') { Ok 'systemd is running (Tortugarr needs it)' }
    else { $fails++; Oops 'systemd isn''t running inside Linux.' "Run this in Linux:  echo -e '[boot]\nsystemd=true' | sudo tee -a /etc/wsl.conf`nThen in PowerShell:  wsl --shutdown  - and run me again." }
    if ($out -contains 'DNS_OK') { Ok 'Linux can get out on the internet' }
    else { $fails++; Oops 'Linux can''t find the internet (DNS).' 'Check that the PC is online, run  wsl --shutdown  in PowerShell, and try again.' }
    if ($fails -eq 0) { Say '  WSL 2 is installed and working 100 %. Hooray! Now the fun begins!' 226 }
    return (Set-Status 'ok')
}

$Tortugarr = @{
    Repo     = 'tortugarr/tortugarr'
    Page     = 'https://github.com/tortugarr/tortugarr'
    Releases = 'https://github.com/tortugarr/tortugarr/releases/latest'
    Port     = 8765
}

function Get-TortugarrRelease {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Tortugarr.Repo)/releases/latest" -Headers @{ 'User-Agent' = 'Greenhorn-WSL-helper' } -TimeoutSec 20
        $pick = { param($rx) $r.assets | Where-Object { $_.name -match $rx } | Select-Object -First 1 }
        [pscustomobject]@{
            Tag    = $r.tag_name
            Server = & $pick '^tortugarr-server-.*\.tar$'
            Tv     = & $pick '^tortugarr-tv-.*\.apk$'
            Phone  = & $pick '^tortugarr-phone-.*\.apk$'
            Sums   = & $pick '^SHA256SUMS'
        }
    } catch { $null }
}

function ConvertTo-WslPath([string]$p) { '/mnt/' + $p.Substring(0, 1).ToLower() + ($p.Substring(2) -replace '\\', '/') }

function Save-Asset($asset, [string]$dir) {
    $dest = Join-Path $dir $asset.name
    if ((Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -eq $asset.size) { Ok "$($asset.name) is already downloaded"; return $dest }
    $size = if ($asset.size -lt 1MB) { '{0:N0} KB' -f [Math]::Max(1, $asset.size / 1KB) } else { '{0:N0} MB' -f ($asset.size / 1MB) }
    Invoke-Action "Download $($asset.name)  ($size)" {
        & curl.exe -L --fail --progress-bar -o $dest $asset.browser_download_url
    } "curl.exe -L -o `"$dest`" $($asset.browser_download_url)" 'Check that the internet works and run me again - I''ll pick up where we left off.'
    return $dest
}

function Test-AssetHash([string]$file, [string]$sumsFile) {
    if ($DryRun -or -not (Test-Path -LiteralPath $file) -or -not (Test-Path -LiteralPath $sumsFile)) { return }
    $name = Split-Path $file -Leaf
    $line = Get-Content -LiteralPath $sumsFile | Where-Object { $_ -match "\s\*?$([regex]::Escape($name))$" } | Select-Object -First 1
    if (-not $line) { return }
    $want = ($line -split '\s+')[0].ToLower()
    $have = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
    if ($want -eq $have) { Ok "$name - checksum OK, no pirates have tampered with it!" }
    else {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Oops "$name got damaged on the way (the checksum doesn't match)." 'I''ve deleted it - just run me again and I''ll fetch a fresh one.'
    }
}

# Tiny one-off web server so the TV and phone can fetch the APKs with a short address
function Start-ApkShop($apks) {
    $ip = if ($script:Lan) { $script:Lan.Ip } else { $l = Get-LanInfo; if ($l) { $l.Ip } }
    if (-not $ip) { Oops 'Couldn''t find the PC on the home network.' "Use the GitHub address instead:`n$($Tortugarr.Releases)"; return }
    $base = "http://${ip}:$($Tortugarr.Port)"
    $rule = 'Mr. Greenhorn APK shop (temporary)'
    [Console]::WriteLine()
    Say '  +--------------------------------------------------------------------+' 51
    Say '     MR. GREENHORN''S APK SHOP - open now, on your home network only' 226
    if ($apks.ContainsKey('tv'))    { Say "     The TV (in Downloader):    $base/tv" 46 }
    if ($apks.ContainsKey('phone')) { Say "     The phone (in Chrome):     $base/phone" 46 }
    Say '  +--------------------------------------------------------------------+' 51
    Info 'The TV and the phone must be on the same Wi-Fi/network as the PC.'
    if ($DryRun -or -not $Interactive) {
        Invoke-Action "Open the APK shop on $base" { } "New-NetFirewallRule '$rule' TCP $($Tortugarr.Port)`nHttpListener http://+:$($Tortugarr.Port)/  (/tv, /phone)`n... until you press a key, then the firewall rule is removed"
        return
    }
    $listener = $null
    try {
        New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $Tortugarr.Port -Action Allow -Profile Any -ErrorAction Stop | Out-Null
        $listener = New-Object Net.HttpListener
        $listener.Prefixes.Add("http://+:$($Tortugarr.Port)/")
        $listener.Start()
    } catch {
        Oops "The APK shop couldn't open: $($_.Exception.Message)" "Use the GitHub address instead:`n$($Tortugarr.Releases)"
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        return
    }
    Say '  The shop is open! Press a key HERE when the TV and the phone have got their apps.' 226
    try {
        $task = $listener.GetContextAsync()
        while ($true) {
            if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }
            if (-not $task.Wait(250)) { continue }
            $ctx = $task.Result; $task = $listener.GetContextAsync()
            $key = $ctx.Request.Url.AbsolutePath.Trim('/').ToLower()
            $who = $ctx.Request.RemoteEndPoint.Address
            $res = $ctx.Response
            try {
                if ($apks.ContainsKey($key)) {
                    $f = $apks[$key]; $name = Split-Path $f -Leaf
                    Info "$who is fetching $name ..."
                    $res.ContentType = 'application/vnd.android.package-archive'
                    $res.AddHeader('Content-Disposition', "attachment; filename=`"$name`"")
                    $fs = [IO.File]::OpenRead($f)
                    try { $res.ContentLength64 = $fs.Length; $fs.CopyTo($res.OutputStream) } finally { $fs.Dispose() }
                    Ok "$who got $name!"
                    Yay
                } else {
                    $links = ($apks.Keys | Sort-Object | ForEach-Object { "<p><a href='/$_' style='font-size:2em'>Tortugarr for $_</a></p>" }) -join ''
                    $b = [Text.Encoding]::UTF8.GetBytes("<html><body style='font-family:sans-serif;text-align:center;padding:2em'><h1>Ahoy, Mr. Greenhorn!</h1>$links</body></html>")
                    $res.ContentType = 'text/html; charset=utf-8'; $res.ContentLength64 = $b.Length
                    $res.OutputStream.Write($b, 0, $b.Length)
                }
            } catch { Warn "The transfer to $who was interrupted - just try again from the TV/phone." }
            finally { try { $res.Close() } catch {} }
        }
    } finally {
        try { $listener.Stop(); $listener.Close() } catch {}
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        Ok 'The shop is closed and the firewall is back to normal.'
    }
}

function Step-Tortugarr {
    Step 'Next stop: Tortugarr on GitHub!'
    Say '  Now we fetch Tortugarr - your very own streaming service, on your very own TV. No subscription! (Yes, you read that right.)' 231
    [Console]::WriteLine()
    Say '  First a quick trip to GitHub school. No homework, I promise!' 51
    Info 'GitHub is where programmers share their programs - a bit like an app store for nerds.'
    Info 'You need NO account. No forms, no salesperson calling you back. Just look, download and go.'
    Info "The good stuff is under 'Releases' (on the right of the page), tagged with a green 'Latest'."
    Info "There are 4 files there - and I'll tell you exactly which one goes where."
    [Console]::WriteLine()

    $rel = Get-TortugarrRelease
    if (-not $rel -or -not $rel.Server) {
        Oops 'Couldn''t reach GitHub right now.' "Open this page in the browser and download the files yourself:`n$($Tortugarr.Releases)"
        return (Set-Status 'ok')
    }
    Ok "Latest version: Tortugarr $($rel.Tag)"
    Say ("    {0,-36} -> the server, into Linux on the PC" -f $rel.Server.name) 231
    if ($rel.Tv)    { Say ("    {0,-36} -> the app for the TV (Android TV / Google TV)" -f $rel.Tv.name) 231 }
    if ($rel.Phone) { Say ("    {0,-36} -> the app for the Android phone" -f $rel.Phone.name) 231 }
    if ($rel.Sums)  { Say ("    {0,-36} -> checksums (I use that one, you don't need to think about it)" -f $rel.Sums.name) 244 }
    [Console]::WriteLine()
    if (Ask-YesNo 'Want to see the GitHub page in the browser too? (just for a peek)' $true) {
        Invoke-Action 'Open Tortugarr on GitHub' { Start-Process $Tortugarr.Releases } "start $($Tortugarr.Releases)"
    }
    $wantTv = Ask-YesNo 'Do you have an Android TV or Google TV?' $true

    $dir = Join-Path $env:USERPROFILE 'Downloads\Tortugarr'
    Invoke-Action "Create the folder $dir" { New-Item -ItemType Directory -Force -Path $dir | Out-Null } "mkdir $dir"
    $sums = if ($rel.Sums) { Save-Asset $rel.Sums $dir }
    $serverFile = Save-Asset $rel.Server $dir
    Test-AssetHash $serverFile $sums
    $apks = @{}
    if ($rel.Phone) { $apks['phone'] = Save-Asset $rel.Phone $dir; Test-AssetHash $apks['phone'] $sums }
    if ($wantTv -and $rel.Tv) { $apks['tv'] = Save-Asset $rel.Tv $dir; Test-AssetHash $apks['tv'] $sums }
    if (-not $DryRun) { $script:Done.Add("Tortugarr $($rel.Tag) downloaded to $dir") }

    # --- TV ---
    if ($apks.ContainsKey('tv')) {
        [Console]::WriteLine()
        Say '  How to get the app onto the TV:' 51
        Say '    1. On the TV: open Google Play, search for  Downloader  (by AFTVnews) and install it.' 231
        Say '    2. Settings -> Apps -> Security & restrictions -> Unknown sources -> switch on Downloader.' 231
        Info '       Can''t find it? Settings -> System -> About -> click "Android TV OS build" 7 times.'
        Info '       "You are now a developer!" - and the option shows up. (Yes, you''re a developer now, Mr. Greenhorn.)'
        Say '    3. Open Downloader, type the address I''ll show you in a moment, and press Go.' 231
        Say '    4. Press Install -> Open. Ahoy!' 231
    }
    # --- phone ---
    if ($apks.ContainsKey('phone')) {
        [Console]::WriteLine()
        Say '  How to get the app onto the phone:' 51
        Say '    1. Open Chrome on the phone and go to the address I''ll show you in a moment.' 231
        Say '    2. Tap Download -> Open.' 231
        Say '    3. Android says "For your security ..." -> Settings -> switch on "Allow from this source" -> back.' 231
        Say '    4. Tap Install. Play Protect says "Unknown app"? -> More details -> Install anyway.' 231
        Info 'Tip: the Obtainium app can keep Tortugarr up to date straight from GitHub - fully automatic.'
    }
    if ($apks.Count) {
        [Console]::WriteLine()
        if (Ask-YesNo 'Shall I send the apps straight from the PC over Wi-Fi? (a much shorter address to type on the TV)' $true) {
            Start-ApkShop $apks
        } else {
            Info 'No problem! Then you use the GitHub addresses:'
            if ($rel.Tv -and $apks.ContainsKey('tv'))       { Say "    TV:     $($rel.Tv.browser_download_url)" 46 }
            if ($rel.Phone -and $apks.ContainsKey('phone')) { Say "    Phone:  $($rel.Phone.browser_download_url)" 46 }
            Info "Or: copy the APK file from $dir to a USB stick and plug it into the TV."
        }
    }

    # --- server: only point the way, Tortugarr has its own (good) installer ---
    $wslFile = ConvertTo-WslPath $serverFile
    $tarName = $rel.Server.name
    $cmds = @("cd ~", "cp `"$wslFile`" .", "tar -xf $tarName", 'cd tortugarr-server', 'sudo ./install.sh')
    [Console]::WriteLine()
    Say '  And the server? Tortugarr has its own, really good installer for that.' 51
    Say '  When you''re ready (set aside about 15 minutes):' 231
    Say "    1. Open Start, type  wsl  (or $($script:Distro)) and press Enter." 231
    Say '    2. Paste this in (right-click in the Linux window = paste):' 231
    foreach ($c in $cmds) { Say "         $c" 46 }
    Say '    3. Answer the questions - Enter takes the default, and that''s nearly always right.' 231
    Say "    4. When it asks about the Windows helper: pick  'let the installer do it'." 231
    $ip = if ($script:Lan) { $script:Lan.Ip } else { '<PC-ens IP>' }
    Say "    5. In the app, connect to  http://${ip}:8096  with Quick Connect." 231
    Invoke-Action 'Put the commands on the clipboard' { Set-Clipboard -Value ($cmds -join "`n") } 'Set-Clipboard'
    Info "The full guide is at $($Tortugarr.Page)"
    return (Set-Status 'ok')
}

function Step-Summary {
    Step 'Done! Hooray!'
    if ($script:OopsCount -eq 0) { Say '  Zero errors! Hooray! Mr. Greenhorn, you''re a hero. Grab a coffee and a doughnut - you''ve earned it!' 226 }
    else { Say "  We tripped $($script:OopsCount) time(s), but crossed the finish line anyway. Hooray! That's how heroes do it!" 226 }
    if ($script:Done.Count) { foreach ($d in $script:Done) { Ok $d } }
    [Console]::WriteLine()
    Say '  Handy tricks:' 51
    Say '    wsl                          start Linux' 231
    Say '    wsl --shutdown               switch off Linux (frees memory)' 231
    Say '    \\wsl$                       the Linux files in Explorer (paste into the address bar)' 231
    Say '    explorer.exe .               (inside Linux) open the folder you''re in, in Windows' 231
    Say '    code .                       (inside Linux) open the folder in VS Code' 231
    Say '    wsl --manage <distro> --move D:\WSL     move Linux to another disk' 231
    if ($script:NetMode -eq 'fixed') {
        Say "    ssh user@$($Cfg.HostName)              once you've installed openssh-server" 231
        Say "    schtasks /run /tn $($Cfg.TaskName)   set the fixed IP again right away" 231
    }
    Say '    Run this file again and do the clean-up step when the disk has grown.' 231
    if (-not $DryRun) { Info "Log: $($Cfg.LogFile)" }
    if ($DryRun) { [Console]::WriteLine(); Say '  DRY-RUN done - nothing was changed.' 214 }
}

$script:ResumeStep = $null
$script:CurrentStep = $null
$script:GuideDone = $false
function Start-Guide {
    $steps = @('Step-Precheck', 'Step-Core', 'Step-Distro', 'Step-NetworkChoice', 'Step-WslConfig', 'Step-FixedIp', 'Step-Disk', 'Step-Verify', 'Step-Tortugarr')
    $start = 0
    if ($script:ResumeStep) { $start = [Math]::Max(0, [Array]::IndexOf($steps, $script:ResumeStep)) }
    $script:StepNo = $start
    $script:CurrentStep = $steps[$start]
    Register-Resume 'net' -Quiet
    for ($n = $start; $n -lt $steps.Count; $n++) {
        $s = $steps[$n]
        $script:CurrentStep = $s
        Save-ResumeState 'net'
        & $s
        if ($script:Status -eq 'reboot') { return }
        if ($script:Status -ne 'ok') { Clear-Resume -Quiet; Say '  No problem, let''s take a little break! Maybe a coffee and a cookie? Run me again when you''re ready - I''m always in a good mood.' 51; return }
        Yay
    }
    if ($Interactive) {
        $txt = if ($DryRun) { 'TEST PASSED!' } else { 'YOU DID IT!' }
        [void](Show-Intro $txt 6)
    }
    Step-Summary
    $script:GuideDone = $true
}
#endregion

#region ---------- main ----------
if ($argv -contains '--help' -or $argv -contains '/?') {
    Say 'Sentinel-Greenhorn.bat [--dry-run] [--fresh] [--oops] [--novirt] [--resume] [--quiet] [--go]' 231
    Say '  --dry-run   show everything that would happen, change nothing' 244
    Say '  --fresh     (with --dry-run) pretend WSL is not installed' 244
    Say '  --go        skip the fireworks' 244
    Say '  --oops      (with --dry-run) pretend something fails, so you can see the error messages' 244
    Say '  --novirt    (with --dry-run) pretend virtualization is off in the BIOS' 244
    Say '  --quiet     no music  (M in the menu turns it on and off)' 244
    Say '  --resume    carry on after a restart (used by the startup task; with --dry-run: a preview)' 244
    exit 0
}

Start-Music
$choice = if ($GoDirect) { 'go' } else { Show-Intro 'WSL INSTALLER HAS LANDED!' -Fun }
if ($choice -ne 'go') {
    Say ''
    Say '   Bye bye, Mr. Greenhorn! *waves* Help is here whenever you need it. Sentinel has got your back!' 51
    Start-Sleep -Milliseconds 1200
    exit 0
}

if (-not $IsAdmin -and -not $DryRun) {
    Info 'I need administrator rights. Windows will ask you now - press "Yes".'
    try {
        $relaunch = @('--go'); if ($Resume) { $relaunch += '--resume' }; if (-not $script:MusicOn) { $relaunch += '--quiet' }
        Start-Process -FilePath $Self -ArgumentList $relaunch -Verb RunAs -ErrorAction Stop | Out-Null
        exit 0
    } catch {
        Oops 'I didn''t get administrator rights (did you press No? Totally allowed!).' 'Right-click the file, pick "Run as administrator", and press Yes when Windows asks.'
        Pause-Key
        exit 1
    }
}

if ($DryRun) { Say '  *** DRY-RUN: I''m showing what would happen, but changing nothing ***' 214 }
else { try { Start-Transcript -Path $Cfg.LogFile -Append | Out-Null } catch {} }

if ($Resume -and (Restore-ResumeState)) {
    if ($Interactive) { [void](Show-Intro 'WELCOME BACK!' 4) }
    Say '  Welcome back, Mr. Greenhorn! So good to see you again! The PC had a little nap, and I remembered where we were.' 51
    Info 'I''ll check that everything stuck, and then we carry on. Onwards!'
    $script:ForcedCheer = 'Brilliant, Mr. Greenhorn! Bang on target!'
} else {
    Say '  Hi there, Mr. Greenhorn! Now we''re going to tuck Linux inside your Windows. It''s going to be great fun - I promise!' 51
    Say '  You don''t need to know a single thing. Just read, press Enter and smile. Easy peasy!' 231
}
try { Start-Guide }
catch { Clear-Resume -Quiet; Oops "Something totally unexpected happened: $($_.Exception.Message)" "$DefaultFix`nThe log is here: $($Cfg.LogFile)" }

if ($script:GuideDone) { [Console]::WriteLine(); Clear-Resume }
if (-not $DryRun) { try { Stop-Transcript | Out-Null } catch {} }
Pause-Key
exit 0
#endregion
