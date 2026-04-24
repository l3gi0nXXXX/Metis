#!/usr/bin/env python3
"""
Magic CLI Release Script - Python Implementation
Automates building and releasing Magic CLI for multiple platforms
"""

import os
import sys
import subprocess
import platform
import argparse
from pathlib import Path
from typing import Optional, Tuple, Dict, Any


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    GRAY = '\033[0;37m'
    NC = '\033[0m'  # No Color


class ReleaseManager:
    """Manages the release process for Magic CLI"""

    def __init__(self, owner: str, repo: str, access_token: str, version: str = "v0.0.1"):
        self.script_dir = Path(__file__).parent.absolute()
        self.owner = owner
        self.repo = repo
        self.access_token = access_token
        self.version = version
        self.platform = self.get_platform()
        self.tag = f"{version}-{self.platform}"

    # Colored output functions
    @staticmethod
    def print_info(message: str) -> None:
        print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")

    @staticmethod
    def print_success(message: str) -> None:
        print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")

    @staticmethod
    def print_warning(message: str) -> None:
        print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")

    @staticmethod
    def print_error(message: str) -> None:
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")

    @staticmethod
    def print_step(message: str) -> None:
        print(f"{Colors.PURPLE}[STEP]{Colors.NC} {message}")

    @staticmethod
    def print_header(message: str) -> None:
        print(f"{Colors.WHITE}================================{Colors.NC}")
        print(f"{Colors.WHITE}{message}{Colors.NC}")
        print(f"{Colors.WHITE}================================{Colors.NC}")

    def get_platform(self) -> str:
        """Detect current platform (OS-architecture combination)"""
        # Get operating system
        os_name = platform.system().lower()
        os_mapping = {
            'darwin': 'macos',
            'linux': 'linux',
            'windows': 'windows',
            'freebsd': 'freebsd'
        }
        os_name = os_mapping.get(os_name, 'unknown')

        # Get architecture
        arch = platform.machine().lower()
        arch_mapping = {
            'x86_64': 'x86_64',
            'x64': 'x86_64',
            'aarch64': 'aarch64',
            'arm64': 'aarch64',
            'armv7l': 'armv7',
            'armv6l': 'armv6',
            'i386': 'x86',
            'i686': 'x86'
        }
        arch = arch_mapping.get(arch, arch)

        return f"{os_name}-{arch}"

    def display_config(self) -> None:
        """Display current configuration"""
        self.print_info("Configuration:")
        print(f"  {Colors.GRAY}Owner:{Colors.NC} {Colors.CYAN}{self.owner}{Colors.NC}")
        print(f"  {Colors.GRAY}Repository:{Colors.NC} {Colors.CYAN}{self.repo}{Colors.NC}")
        print(f"  {Colors.GRAY}Tag:{Colors.NC} {Colors.CYAN}{self.tag}{Colors.NC}")
        print(f"  {Colors.GRAY}Platform:{Colors.NC} {Colors.CYAN}{self.platform}{Colors.NC}")
        print(f"  {Colors.GRAY}Release Name:{Colors.NC} {Colors.CYAN}{self.tag}{Colors.NC}")
        print()

    def run_command(self, command: list, capture_output: bool = True) -> Tuple[int, str, str]:
        """Run a shell command and return exit code, stdout, stderr"""
        try:
            if capture_output:
                result = subprocess.run(
                    command,
                    capture_output=True,
                    text=True
                )
                return result.returncode, result.stdout, result.stderr
            else:
                result = subprocess.run(command)
                return result.returncode, "", ""
        except Exception as e:
            return 1, "", str(e)

    def build_magic_cli(self) -> bool:
        """Build magic-cli using the build script"""
        self.print_step(f"Step 1: Building magic-cli for {Colors.CYAN}{self.platform}{Colors.NC}")
        print()

        build_script = self.script_dir / "../build-static/build-magic-cli.sh"
        if not build_script.exists():
            self.print_error(f"Build script not found: {build_script}")
            return False

        exit_code, stdout, stderr = self.run_command(["bash", str(build_script)], capture_output=False)

        if exit_code == 0:
            self.print_success("Build completed successfully!")
        else:
            self.print_error("Build failed!")
            if stderr:
                print(f"Error: {stderr}")
            return False

        print()
        return True

    def create_release(self) -> bool:
        """Create release on GitCode"""
        self.print_step(f"Step 2: Creating release {Colors.CYAN}{self.tag}{Colors.NC} for {Colors.CYAN}{self.platform}{Colors.NC}")
        print()

        gitcode_script = self.script_dir / "gitcode.py"
        if not gitcode_script.exists():
            self.print_error(f"gitcode.py script not found: {gitcode_script}")
            return False

        # First attempt to create release
        exit_code, stdout, stderr = self.run_command([
            "python3", str(gitcode_script), "release",
            "--owner", self.owner,
            "--repo", self.repo,
            "--tag", self.tag,
            "--access-token", self.access_token,
            "--release-name", self.tag,
            "--release-body", f"Release {self.tag}"
        ])

        if exit_code == 0:
            self.print_success("Release created successfully!")
            print()
            return True

        # Check if tag already exists
        if "tag already exists" in stderr.lower() or "tag already exists" in stdout.lower():
            self.print_warning(f"Tag {self.tag} already exists. Deleting existing tag and retrying...")
            print()

            # Delete existing tag
            self.print_step(f"Deleting existing tag {Colors.CYAN}{self.tag}{Colors.NC}")
            exit_code, _, stderr = self.run_command([
                "python3", str(gitcode_script), "delete-tag",
                "--owner", self.owner,
                "--repo", self.repo,
                "--tag", self.tag,
                "--access-token", self.access_token
            ])

            if exit_code != 0:
                self.print_error(f"Failed to delete existing tag {self.tag}")
                if stderr:
                    print(f"Error: {stderr}")
                return False

            self.print_success("Tag deleted successfully!")
            print()

            # Retry creating release
            self.print_step(f"Retrying release creation for {Colors.CYAN}{self.tag}{Colors.NC}")
            print()

            exit_code, stdout, stderr = self.run_command([
                "python3", str(gitcode_script), "release",
                "--owner", self.owner,
                "--repo", self.repo,
                "--tag", self.tag,
                "--access-token", self.access_token,
                "--release-name", self.tag,
                "--release-body", f"Release {self.tag}"
            ])

            if exit_code == 0:
                self.print_success("Release created successfully!")
                print()
                return True
            else:
                self.print_error(f"Failed to create release {self.tag} for {self.platform}")
                if stderr:
                    print(f"Error: {stderr}")
                return False
        else:
            self.print_error(f"Failed to create release {self.tag} for {self.platform}")
            if stderr:
                print(f"Error: {stderr}")
            return False

    def upload_binary(self) -> bool:
        """Upload binary to the release"""
        self.print_step(f"Step 3: Uploading binary for {Colors.CYAN}{self.platform}{Colors.NC}")
        print()

        gitcode_script = self.script_dir / "gitcode.py"
        binary_path = self.script_dir / "../../binary/magic-cli"

        if not gitcode_script.exists():
            self.print_error(f"gitcode.py script not found: {gitcode_script}")
            return False

        if not binary_path.exists():
            self.print_error(f"Binary not found: {binary_path}")
            return False

        exit_code, stdout, stderr = self.run_command([
            "python3", str(gitcode_script), "upload",
            "--owner", self.owner,
            "--repo", self.repo,
            "--tag", self.tag,
            "--access-token", self.access_token,
            str(binary_path),
            "--remote-name", f"magic-cli-{self.platform}"
        ])

        if exit_code == 0:
            print()
            self.print_header("✅ Release Process Completed!")
            print(f"{Colors.GREEN}🎉 Magic CLI {self.tag} has been released for {self.platform}!{Colors.NC}")
            print(f"{Colors.GRAY}Binary name: magic-cli-{self.platform}{Colors.NC}")
            return True
        else:
            self.print_error("Binary upload failed!")
            if stderr:
                print(f"Error: {stderr}")
            return False

    def run_release(self) -> bool:
        """Run the complete release process"""
        self.print_header("🚀 Magic CLI Release Script")
        self.display_config()

        # Step 1: Build
        if not self.build_magic_cli():
            return False

        # Step 2: Create release
        if not self.create_release():
            return False

        # Step 3: Upload binary
        if not self.upload_binary():
            return False

        return True


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Magic CLI Release Script")
    parser.add_argument("--owner", required=True, help="GitCode repository owner")
    parser.add_argument("--repo", required=True, help="GitCode repository name")
    parser.add_argument("--access-token", required=True, help="GitCode access token")
    parser.add_argument("--version", default="v0.0.1", help="Release version (default: v0.0.1)")

    args = parser.parse_args()

    try:
        release_manager = ReleaseManager(
            owner=args.owner,
            repo=args.repo,
            access_token=args.access_token,
            version=args.version
        )

        success = release_manager.run_release()
        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        print("\nRelease process interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()