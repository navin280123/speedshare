import os
import re
import subprocess
from typing import List, Set
import shutil  # Used to find the dart executable
import sys     # Used to check the operating system

# --- Configuration ---
# Set the target directory for refactoring.
# For a standard Flutter project, 'lib' is the correct folder.
TARGET_DIRECTORY = 'lib'


def find_dart_executable() -> str | None:
    """
    Finds the full path to the Dart executable on the system's PATH.

    Returns the path as a string or None if it's not found.
    """
    # shutil.which() is the modern, cross-platform way to find an executable.
    # It checks the PATH environment variable automatically.
    dart_path = shutil.which('dart')
    
    # On Windows, `shutil.which` might find 'dart' but we might prefer 'dart.bat'.
    # If a .bat file exists at the same location, we'll use it as it often
    # sets up the necessary environment for the command.
    if sys.platform == "win32" and dart_path:
        bat_path = dart_path + ".bat"
        if os.path.exists(bat_path):
            return bat_path
            
    return dart_path


def main():
    """
    Main function to run the refactoring scripts on the target directory.
    """
    print(f"--- Starting Dart refactoring on directory: '{TARGET_DIRECTORY}' ---")

    # Find the dart executable path once at the beginning.
    dart_executable_path = find_dart_executable()
    if not dart_executable_path:
        print("\n[WARNING] 'dart' command not found in your system's PATH.")
        print("           Code refactoring will proceed, but the final formatting step will be SKIPPED.")
    else:
        print(f"Found Dart executable at: {dart_executable_path}")

    # Find all Dart files once to avoid redundant directory walks.
    dart_files = _find_dart_files(TARGET_DIRECTORY)
    if not dart_files:
        print("No .dart files found. Exiting.")
        return

    # Keep track of files that have been modified.
    modified_files: Set[str] = set()

    # Run the refactoring functions.
    modified_by_alpha = replace_with_alpha(dart_files)
    modified_by_print = replace_print_with_debug_print(dart_files)

    # Combine the sets of modified files.
    modified_files.update(modified_by_alpha)
    modified_files.update(modified_by_print)

    if not modified_files:
        print("\nNo changes were needed in any files.")
    else:
        print(f"\nTotal files modified: {len(modified_files)}")
        # Only attempt to format if dart was found and files were changed.
        if dart_executable_path:
            format_dart_directory(TARGET_DIRECTORY, dart_executable_path)
        else:
            print("\nSkipping formatting because 'dart' was not found.")

    print("\n--- Refactoring complete. ---")


def _find_dart_files(directory: str) -> List[str]:
    """
    Walks through a directory and returns a list of all .dart file paths.
    """
    dart_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                dart_files.append(os.path.join(root, file))
    return dart_files


def replace_with_alpha(dart_files: List[str]) -> Set[str]:
    """
    Replaces '.withOpacity(value)' with '.withAlpha(value * 255)'.
    Returns a set of file paths that were modified.
    """
    print("\n1. Checking for '.withOpacity()' to convert to '.withAlpha()'")
    # Regex to find .withOpacity(0.123)
    regex = re.compile(r'\.withOpacity\((0\.\d+)\)')
    modified_files: Set[str] = set()

    def replace_opacity(match: re.Match) -> str:
        """Calculates the alpha value from the opacity value."""
        opacity_value = float(match.group(1))
        # Clamp the value between 0.0 and 1.0 before conversion
        opacity_value = max(0.0, min(1.0, opacity_value))
        alpha_value = int(round(opacity_value * 255))
        return f".withAlpha({alpha_value})"

    for file_path in dart_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()

            updated_content = regex.sub(replace_opacity, content)

            if content != updated_content:
                with open(file_path, 'w', encoding='utf-8') as file:
                    file.write(updated_content)
                print(f"   - Converted opacity in: {file_path}")
                modified_files.add(file_path)
        except Exception as e:
            print(f"   - Error processing {file_path}: {e}")
            
    return modified_files


def replace_print_with_debug_print(dart_files: List[str]) -> Set[str]:
    """
    Replaces 'print(...);' with 'debugPrint(...);'.
    Returns a set of file paths that were modified.
    """
    print("\n2. Checking for 'print()' to convert to 'debugPrint()'")
    # Regex to find a whole word 'print', followed by parentheses.
    # The '?' makes the '.*' non-greedy to handle multiple statements on one line.
    regex = re.compile(r'\bprint\s*\((.*?)\);')
    modified_files: Set[str] = set()

    for file_path in dart_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()

            # Using a simple f-string replacement is safe and clear here.
            updated_content = regex.sub(r'debugPrint(\1);', content)

            if content != updated_content:
                with open(file_path, 'w', encoding='utf-8') as file:
                    file.write(updated_content)
                print(f"   - Replaced print in: {file_path}")
                modified_files.add(file_path)
        except Exception as e:
            print(f"   - Error processing {file_path}: {e}")

    return modified_files


def format_dart_directory(directory: str, dart_executable_path: str):
    """
    Runs 'dart format' on the specified directory using the provided executable path.
    """
    print(f"\n3. Formatting all .dart files in '{directory}'...")
    try:
        # The 'capture_output' and 'text' arguments are used to hide the
        # command's stdout unless an error occurs.
        result = subprocess.run(
            [dart_executable_path, 'format', directory],
            check=True,
            capture_output=True,
            text=True
        )
        print("   - Formatting successful.")
    except FileNotFoundError:
        # This error is now a fallback, but shutil.which should prevent it.
        print(f"\n   [ERROR] The specified Dart executable was not found at: '{dart_executable_path}'")
    except subprocess.CalledProcessError as e:
        print(f"\n   [ERROR] 'dart format' failed with exit code {e.returncode}:")
        print(e.stderr)


if __name__ == "__main__":
    main()