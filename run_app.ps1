param(
  # ✅ Your GitHub repo URL
  [string]$RepoUrl = "https://github.com/tetalisriteja439/auto_updater.git",

  # ✅ Local repo path — this is exactly your folder
  [string]$AppRoot = "$HOME\OneDrive - WFS\Desktop\WFS\auto_updater",

  # ✅ Entry point at repo root
  [string]$Entry   = "gui.py",

  # ✅ Required Python version (installs user-only if missing/older)
  [string]$RequiredPythonVersion = "3.12.6",

  # Leave empty to auto-use newest release tag (vX.Y.Z); or pass: main / v1.2.3 / <sha>
  [string]$Ref     = ""
)

### --- PYTHON ENSURE --- ###

function Get-PythonVersion {
    param([string]$PythonExe)
    try {
        $v = & $PythonExe -c 'import platform; print(platform.python_version())'
        if ($LASTEXITCODE -eq 0) { return $v.Trim() }
    } catch { }
    return $null
}

function Find-PythonExe {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $userPath = "$env:LOCALAPPDATA\Programs\Python"
    if (Test-Path $userPath) {
        $exe = Get-ChildItem -Path $userPath -Recurse -Filter "python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Get-Python {
    param([string]$RequiredPythonVersion)

    $pyExe = Find-PythonExe
    if ($pyExe) {
        $curVer = Get-PythonVersion -PythonExe $pyExe
        if ($curVer -and ([version]$curVer -ge [version]$RequiredPythonVersion)) {
            Write-Host "Python $curVer already present at $pyExe."
            return $pyExe
        } else {
            Write-Host "Python found ($curVer) but below required $RequiredPythonVersion. Will install new version."
        }
    } else {
        Write-Host "Python not found. Will install $RequiredPythonVersion."
    }

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "win32" }
    $url  = "https://www.python.org/ftp/python/$RequiredPythonVersion/python-$RequiredPythonVersion-$arch.exe"
    $tmp  = Join-Path $env:TEMP ("python-$RequiredPythonVersion-$arch-" + [guid]::NewGuid().ToString() + ".exe")

    Write-Host "Downloading Python $RequiredPythonVersion from $url..."
    Invoke-WebRequest -Uri $url -OutFile $tmp
    if (-not (Test-Path $tmp)) { throw "Download failed." }

    $installArgs = "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_tcltk=1"
    Write-Host "Installing Python $RequiredPythonVersion (user-only)..."
    $p = Start-Process -FilePath $tmp -ArgumentList $installArgs -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Python installer failed with exit code $($p.ExitCode)" }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    # Refresh PATH for this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","Machine")

    $pyExe = Find-PythonExe
    if (-not $pyExe) { throw "Installed Python but couldn't locate python.exe. Open a new PowerShell and retry." }

    $newVer = Get-PythonVersion -PythonExe $pyExe
    Write-Host "Installed Python $newVer at $pyExe"
    return $pyExe
}

### --- GIT / REPO --- ###

function Test-GitInstalled { if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found in PATH" } }

function Resolve-Ref {
    param([string]$Ref)
    if ($Ref) { return $Ref }  # explicit branch|tag|sha

    # Get all tags, trim CRLFs, and keep only semver-like tags vX.Y.Z
    $tagsRaw = git tag --list --sort=-version:refname
    $tags = $tagsRaw -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }

    if (-not $tags -or $tags.Count -eq 0) {
        throw "No version tags found. Create a release tag like v0.1.0."
    }
    return $tags[0]  # newest
}

function Update-Repository {
    param([string]$RepoUrl,[string]$AppRoot,[string]$Ref)

    # Test if the folder is a git repo. If not, clone into a temp and move, or error out.
    if (-not (Test-Path (Join-Path $AppRoot ".git"))) {
        if (Get-ChildItem -LiteralPath $AppRoot -Force | Where-Object { $_.Name -notin @(".","..") }){
            throw "Folder exists but is not a git repo. Either 'git init' and set remote to $RepoUrl, or move files aside so this script can clone."
        }
        # Parent exists? If not, create it.
        $parent = Split-Path $AppRoot -Parent
        if (-not (Test-Path $parent)) { New-Item -Path $parent -ItemType Directory | Out-Null }
        git clone --no-checkout $RepoUrl $AppRoot | Out-Null
    }

    Push-Location $AppRoot

    # Ensure remote is set correctly
    $origin = (git remote get-url origin) 2>$null
    if (-not $origin) { git remote add origin $RepoUrl | Out-Null }
    elseif ($origin -ne $RepoUrl) { Write-Host "WARNING: origin is $origin, expected $RepoUrl" }

    git fetch --all --tags --prune | Out-Null

    $target = Resolve-Ref -Ref $Ref
    $commit = (git rev-parse $target) 2>$null
    if (-not $commit) { throw "Unknown ref: $target" }

    git checkout --detach $commit | Out-Null

    # Build metadata for GUI
    $env:APP_GIT_SHA = (git rev-parse --short HEAD).Trim()
    $env:APP_CHECKED_OUT_TAG = $target

    # Parse owner/repo for GUI to call GitHub API
    if ($RepoUrl -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
        $env:APP_GITHUB_OWNER = $Matches.owner
        $env:APP_GITHUB_REPO  = $Matches.repo
    }

    Write-Host "Checked out $target ($env:APP_GIT_SHA)"
    Pop-Location
    return $target
}

### --- VENV / RUN --- ###

function New-Venv {
    param([string]$AppRoot,[string]$PythonExe)
    $venv = Join-Path $AppRoot ".venv"
    $py = (Join-Path $venv "Scripts\python.exe") -replace "'", ""
    Write-Host "Python executable path: $py"
    if (-not (Test-Path $py)) {
        Push-Location $AppRoot; & "$PythonExe" -m venv ".venv"; Pop-Location
        if ($LASTEXITCODE -ne 0) { throw "Failed to create virtualenv" }
    }
    $null = & "$py" -m pip install --upgrade pip
    $req = Join-Path $AppRoot "requirements.txt"
    if (Test-Path $req) { $null = & "$py" -m pip install -r $req }
    Write-Host "Python executable path: $py"
    return $py
}

function Invoke-Application {
    param([string]$AppRoot,[string]$Entry,[string]$VenvPython)
    $entryPath = Join-Path $AppRoot $Entry
    if (-not (Test-Path $entryPath)) { throw "Entry not found: $entryPath" }
    Write-Host "Running command: $VenvPython $entryPath"
    & $VenvPython $entryPath
}

### --- MAIN --- ###

try {
    Test-GitInstalled
    $pyExe = Get-Python -RequiredPythonVersion $RequiredPythonVersion
    Update-Repository -RepoUrl $RepoUrl -AppRoot $AppRoot -Ref $Ref
    $venvPy  = New-Venv -AppRoot $AppRoot -PythonExe $pyExe
    Invoke-Application -AppRoot $AppRoot -Entry $Entry -VenvPython $venvPy
} catch {
    Write-Error $_
    exit 1
}
