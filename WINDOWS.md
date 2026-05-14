# Valkyrie Installation on Windows

Complete guide for installing Valkyrie on Windows systems.

## Prerequisites

### 1. Choose Your Environment

Valkyrie supports three Windows environments:

#### Git Bash (Recommended) ✅
- **Pros**: Native feel, good compatibility, lightweight
- **Cons**: Some Unix commands may behave differently
- **Install**: [Git for Windows](https://git-scm.com/download/win)

#### WSL2 (Ubuntu) ✅
- **Pros**: Full Linux compatibility, best for power users
- **Cons**: Slightly more setup, file system considerations
- **Install**: [WSL2 Setup Guide](https://docs.microsoft.com/en-us/windows/wsl/install)

#### PowerShell ⚠️
- **Status**: Limited support (bash script won't run natively)
- **Alternative**: Use Git Bash or WSL2

### 2. Install Python 3.7+

Download from [python.org](https://www.python.org/downloads/) or use:

```powershell
# PowerShell (Run as Administrator)
winget install Python.Python.3.12
```

**Important**: During installation, check "Add Python to PATH"

Verify installation:
```bash
python3 --version  # Should show 3.7 or higher
```

If `python3` command not found, try:
```bash
python --version   # Windows often uses 'python' instead of 'python3'
```

### 3. Install Claude Code

Follow the official installation guide at [claude.ai/code](https://claude.ai/code)

## Installation Steps

### 1. Clone the Repository

```bash
# Git Bash or WSL
cd ~
git clone https://github.com/BunnyDAO/Valkyrie.git valkyrie
cd valkyrie
```

### 2. Run the Installer

```bash
./install.sh
```

The installer will:
1. Detect your Windows environment automatically
2. Validate Python and bash versions
3. Create backups of existing settings
4. Install all Valkyrie components
5. Run validation tests

### 3. Verify Installation

You should see output like:
```
==> Detected Windows (Git Bash/MSYS)
==> Validating installation requirements
  ✓ Python 3.12 detected
  ✓ All requirements met
...
✓ Valkyrie installed successfully!
```

### 4. Restart Claude Code

Close and reopen Claude Code to activate the new statusline and hooks.

## Common Issues

### Issue: "python3: command not found"

**Solution 1**: Create an alias (Git Bash)
```bash
echo 'alias python3=python' >> ~/.bashrc
source ~/.bashrc
```

**Solution 2**: Add Python to PATH
1. Search "Environment Variables" in Windows
2. Edit "Path" under System Variables
3. Add Python installation directory (e.g., `C:\Python312`)
4. Restart Git Bash

### Issue: "Permission denied" errors

**Solution**: Run Git Bash as Administrator
1. Right-click Git Bash icon
2. Select "Run as administrator"
3. Navigate to `~/valkyrie`
4. Run `./install.sh` again

### Issue: Path issues with spaces

If your username has spaces (e.g., "John Doe"):

**Workaround**: The installer handles this automatically using `os.path.expanduser()`, but if you see issues:

```bash
# Check your paths
echo $HOME
ls "$HOME/.claude"
```

### Issue: Symlinks not working

Windows sometimes restricts symlink creation.

**Solution**: Enable Developer Mode
1. Settings → Update & Security → For developers
2. Enable "Developer Mode"
3. Restart Git Bash
4. Run `./install.sh` again

### Issue: "settings.json was invalid JSON"

This usually happens if another tool modified settings during installation.

**Solution**: The installer creates automatic backups
```bash
# List backups
ls ~/.claude/settings.json.pre-valkyrie-*

# Restore if needed
cp ~/.claude/settings.json.pre-valkyrie-TIMESTAMP ~/.claude/settings.json

# Re-run installer
./install.sh
```

### Issue: Statusline not appearing

**Check 1**: Verify settings.json
```bash
cat ~/.claude/settings.json | grep statusLine
# Should show: "statusLine": { ... }
```

**Check 2**: Verify Python script exists
```bash
ls ~/.claude/valkyrie/statusline.py
python3 ~/.claude/valkyrie/statusline.py  # Test directly
```

**Check 3**: Restart Claude Code completely
- Close all Claude Code windows
- End any Claude Code processes in Task Manager
- Reopen Claude Code

### Issue: Hooks not triggering

**Check**: Verify hook installation
```bash
cat ~/.claude/settings.json | grep valk-guard
ls -la ~/.claude/hooks/valk-guard.sh
bash ~/.claude/hooks/valk-guard.sh  # Test directly
```

## Path Differences: Git Bash vs WSL

### Git Bash Paths
```bash
# Windows paths in Git Bash
/c/Users/username/.claude           # C:\Users\username\.claude
/c/Program Files/Python312          # C:\Program Files\Python312
```

### WSL Paths
```bash
# WSL has its own filesystem
~/.claude                           # /home/username/.claude
/mnt/c/Users/username              # Access Windows files
```

**Note**: Valkyrie automatically detects and handles path differences.

## Performance Notes

### Git Bash
- Slightly slower than native Linux
- symlink operations may take longer
- Python I/O is comparable to native

### WSL2
- Near-native Linux performance
- File operations across /mnt/c are slower
- Keep Valkyrie files in WSL filesystem for best performance

## Uninstallation

```bash
cd ~/valkyrie
./uninstall.sh           # Remove Valkyrie, keep settings backup
./uninstall.sh --restore # Remove and restore previous settings
```

## Getting Help

### 1. Check Installation Logs

```bash
# Re-run with verbose output
bash -x ~/valkyrie/install.sh 2>&1 | tee install.log
```

### 2. Verify Claude Code Configuration

```bash
# Check settings.json is valid
python3 -c "import json; print(json.load(open('$HOME/.claude/settings.json')))"
```

### 3. File an Issue

If problems persist, create an issue at:
https://github.com/BunnyDAO/Valkyrie/issues

Include:
- Windows version (Win 10/11)
- Environment (Git Bash/WSL)
- Python version (`python3 --version`)
- Bash version (`bash --version`)
- Error messages from `install.log`

## Advanced: Multiple Claude Code Profiles

If you use multiple Claude Code profiles or configurations:

```bash
# Install to specific profile
CLAUDE_HOME="$HOME/.claude-profile1" ./install.sh

# Uninstall from specific profile
CLAUDE_HOME="$HOME/.claude-profile1" ./uninstall.sh
```

## Tips for Windows Users

1. **Use Windows Terminal**: Better experience than default Git Bash
   - Install from Microsoft Store
   - Add Git Bash as a profile

2. **Keep paths simple**: Avoid spaces and special characters in usernames

3. **Use Developer Mode**: Enables symlinks without admin rights

4. **WSL2 for serious development**: Best Linux compatibility

5. **Regular backups**: `install.sh` creates them automatically, but keep external copies for safety
