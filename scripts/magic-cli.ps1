# Check if CANGJIE_HOME environment variable is set
if (-not ($env:CANGJIE_HOME)) {
    Write-Error "Error: CANGJIE_HOME is not set!"
    exit 1
}

# Store CANGJIE_HOME path
$CANGJIE_HOME = $env:CANGJIE_HOME

# Check if MAGIC_PATH environment variable is set
if (-not ($env:MAGIC_PATH)) {
    Write-Error "Error: MAGIC_PATH is not set!"
    exit 1
}
$MAGIC_PATH = $env:MAGIC_PATH

# Recursively search for the first 'dynamic/stdx' directory under MAGIC_PATH
$STDX_LIB_PATH = Get-ChildItem -Path $MAGIC_PATH -Recurse -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -eq 'stdx' -and $_.Parent.Name -eq 'dynamic' } |
                 Select-Object -First 1 -ExpandProperty FullName

if (-not $STDX_LIB_PATH) {
    Write-Warning "Warning: STDX_LIB_PATH not found under MAGIC_PATH: $MAGIC_PATH"
}

# Get the directory of the current script robustly
$SCRIPT_PATH = $PSCommandPath
if (-not $SCRIPT_PATH) {
    Write-Warning "Script path not available (e.g., interactive session). Using current directory."
    $SCRIPT_PATH = $PWD.Path
}
$SCRIPT_DIR = Split-Path -Parent $SCRIPT_PATH

# Normalize path to resolve '.' and '..'
$SCRIPT_DIR = Resolve-Path $SCRIPT_DIR

# Define library paths relative to the script directory
$CLI_LIB_PATH = "$SCRIPT_DIR\..\target\release\metis", "$SCRIPT_DIR\..\ffi"
$MAGIC_LIB_PATH = "$SCRIPT_DIR\..\target\release\magic"

# Combine all library paths using Windows path separator ';'
$LIB_PATHS = ($CLI_LIB_PATH + $MAGIC_LIB_PATH + $STDX_LIB_PATH | Where-Object { $_ }) -join ';'

# Path to the CLI executable (Windows .exe)
$CLI_BIN = "$SCRIPT_DIR\..\target\release\bin\metis.exe"

# Verify the executable exists
if (-not (Test-Path $CLI_BIN -PathType Leaf)) {
    Write-Error "Error: Executable not found at $CLI_BIN"
    exit 1
}

# Add all library paths to $env:Path so Windows can locate required DLLs
$env:Path = "$LIB_PATHS;$env:Path"

# Execute the CLI binary and pass all arguments received by the script
& $CLI_BIN @args

# Exit with the same exit code as the CLI process
exit $LASTEXITCODE
