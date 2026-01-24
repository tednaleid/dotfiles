#!/usr/bin/env -S uv run --script
# ABOUTME: Setup script for auto-committing Claude Code plan files to git.
# ABOUTME: Creates a git repo in ~/.claude/plans and installs a launchd watcher.
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""
Setup script for auto-committing Claude Code plan files.

Creates a git repo in ~/.claude/plans and installs a launchd watcher
that automatically commits changes whenever plan files are modified.

Usage:
    chmod +x autocommit-claude-plans.py
    ./autocommit-claude-plans.py

To uninstall:
    ./autocommit-claude-plans.py --uninstall
"""

import os
import subprocess
import sys
from pathlib import Path

# Configuration
PLANS_DIR = Path.home() / ".claude" / "plans"
SCRIPTS_DIR = Path.home() / ".local" / "bin"
COMMIT_SCRIPT = SCRIPTS_DIR / "commit-claude-plans.sh"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
PLIST_NAME = "com.user.claude-plan-autocommit.plist"
PLIST_PATH = LAUNCH_AGENTS_DIR / PLIST_NAME


def run(cmd: list[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a command and optionally capture output."""
    return subprocess.run(cmd, check=check, capture_output=capture, text=True)


def is_loaded() -> bool:
    """Check if the launchd job is currently loaded."""
    result = run(["launchctl", "list"], capture=True, check=False)
    return "com.user.claude-plan-autocommit" in result.stdout


def create_commit_script() -> None:
    """Create the shell script that performs the git commit."""
    SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    
    script_content = f"""#!/bin/bash
# Auto-commit script for Claude Code plans
# Installed by autocommit-claude-plans.py

PLANS_DIR="{PLANS_DIR}"
LOGFILE="{Path.home()}/.claude/plans-autocommit.log"

# Prevent git from reading ~/.gitconfig (launchd jobs lack macOS privacy permissions)
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

cd "$PLANS_DIR" || exit 1

# Check if there are any changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
fi

# Stage and commit
git add -A
git -c user.name='Plan Auto-commit' -c user.email='auto@local' commit -m "Auto-commit: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOGFILE" 2>&1
"""
    
    COMMIT_SCRIPT.write_text(script_content)
    COMMIT_SCRIPT.chmod(0o755)
    print(f"[ok] Created commit script: {COMMIT_SCRIPT}")


def create_plist() -> None:
    """Create the launchd plist file."""
    LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
    
    plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.claude-plan-autocommit</string>
    <key>WatchPaths</key>
    <array>
        <string>{PLANS_DIR}</string>
    </array>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>ProgramArguments</key>
    <array>
        <string>{COMMIT_SCRIPT}</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>{Path.home()}/.claude/plans-autocommit.log</string>
    <key>StandardErrorPath</key>
    <string>{Path.home()}/.claude/plans-autocommit.log</string>
</dict>
</plist>
"""
    
    PLIST_PATH.write_text(plist_content)
    print(f"[ok] Created launchd plist: {PLIST_PATH}")


def init_git_repo() -> None:
    """Initialize git repo in plans directory."""
    PLANS_DIR.mkdir(parents=True, exist_ok=True)
    
    git_dir = PLANS_DIR / ".git"
    if git_dir.exists():
        print(f"[ok] Git repo already exists: {PLANS_DIR}")
    else:
        run(["git", "init"], check=True, capture=True)
        
        # Create initial commit if there are existing files
        run(["git", "add", "-A"], check=True, capture=True)
        result = run(["git", "diff", "--cached", "--quiet"], check=False)
        if result.returncode != 0:
            run(["git", "commit", "-m", "Initial commit of existing plans"], capture=True)
            print(f"[ok] Initialized git repo with existing files: {PLANS_DIR}")
        else:
            # Create empty initial commit
            run(["git", "commit", "--allow-empty", "-m", "Initialize plans repository"], capture=True)
            print(f"[ok] Initialized empty git repo: {PLANS_DIR}")
    
    os.chdir(Path.home())  # Return to home directory


def load_launchd() -> None:
    """Load the launchd job."""
    if is_loaded():
        print("[ok] Launchd job already loaded, reloading...")
        run(["launchctl", "unload", str(PLIST_PATH)], check=False)
    
    run(["launchctl", "load", str(PLIST_PATH)])
    print("[ok] Launchd job loaded")


def unload_launchd() -> None:
    """Unload the launchd job."""
    if is_loaded():
        run(["launchctl", "unload", str(PLIST_PATH)], check=False)
        print("[ok] Launchd job unloaded")
    else:
        print("  Launchd job was not loaded")


def install() -> None:
    """Run full installation."""
    print("\nSetting up Claude Plans auto-commit...\n")
    
    # Change to plans directory for git operations
    PLANS_DIR.mkdir(parents=True, exist_ok=True)
    os.chdir(PLANS_DIR)
    
    init_git_repo()
    create_commit_script()
    create_plist()
    load_launchd()
    
    print("\nSetup complete!\n")
    print("Your Claude Code plans will now be automatically committed to git.")
    print(f"  Plans directory: {PLANS_DIR}")
    print(f"  Log file: {Path.home()}/.claude/plans-autocommit.log")
    print("\nTo view commit history:")
    print(f"  cd {PLANS_DIR} && git log --oneline")
    print("\nTo uninstall:")
    print(f"  {sys.argv[0]} --uninstall")


def uninstall() -> None:
    """Remove the auto-commit setup."""
    print("\nRemoving Claude Plans auto-commit...\n")
    
    unload_launchd()
    
    if PLIST_PATH.exists():
        PLIST_PATH.unlink()
        print(f"[ok] Removed plist: {PLIST_PATH}")
    
    if COMMIT_SCRIPT.exists():
        COMMIT_SCRIPT.unlink()
        print(f"[ok] Removed script: {COMMIT_SCRIPT}")
    
    print("\nUninstall complete!")
    print(f"\nNote: Git repo preserved at {PLANS_DIR}")
    print("Delete manually if you don't want the history.")


def main() -> None:
    if sys.platform != "darwin":
        print("Error: This script is for macOS only (uses launchd)")
        sys.exit(1)
    
    if "--uninstall" in sys.argv or "uninstall" in sys.argv:
        uninstall()
    else:
        install()


if __name__ == "__main__":
    main()