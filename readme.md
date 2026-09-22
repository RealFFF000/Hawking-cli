# Hawking-cli

## AKA einstein-but-for-losers

A lightweight **Bash utility** that submits assignment files through Hawking's official API and displays a colorized diff between expected and actual outputs.

## Requirements

* **`curl`**
* **`jq`** (`brew install jq` or `sudo apt install jq`)
* **`bash`** (v4.0+)

## Configuration

Runtime assumptions are stored in [`config.yaml`](config.yaml). It controls the API URL, GitHub updater source and branch, update interval, credential paths, network timeouts, and automatic file-selection exclusions. The installer copies it alongside the installed CLI, and built-in defaults are used if a setting is missing.

## Features

* **Official API transport:** Uses Basic Auth with `/api/auth`, `/api/moduleForTask/{filename}`, and `/api/upload/{module_id}/{filename}`.
* **Secure credential storage:** Uses macOS Keychain or `secret-tool` when available, and prompts for a password otherwise.
* **Module Resolution:** Resolves the correct module from the submitted filename through the API; cached module IDs are retained as a convenience.
* **Auto-File Detection:** Picks the **most recently modified suitable file** when no file is specified. It ignores hidden files, extensionless files, the CLI script, and configured extensions such as `.out`.
* **Visual Diffing:** Prints character-level differences in red and explicitly shows missing final newlines as `<newline>`.
* **Built-in Auto-Update:** Quietly clones the configured GitHub branch and runs `./install.sh` in a temporary staging directory. The installed copy is replaced only after the update succeeds.
* **Manual Update Flag (`--update`):** Forces the same quiet GitHub update immediately.
* **Debug Mode:** Dumps the normalized JSON response used by the renderer.

## Installation

```bash
git clone https://github.com/RealFFF000/Hawking-cli.git
cd hawking-cli
./install.sh
```

## Usage

### Basic Command Structure

```bash
hawking [file_to_submit]
```

By default, if no file is specified, hawking picks the most-recently edited suitable file in the current working directory. Files excluded by `config.yaml` are skipped.

### Additional Flags

* **`--update`**: Force an immediate repository **update**.
* **`--vocal`**: Enable **verbose output** and logs.
* **`--debug`**: Dump raw **JSON response**.
* **`--runner`**: Open test runner source from the response in **Neovim**.
* **`--modules`**: List all cached module IDs.
* **`--add-module <ID>`**: Manually add a module ID to cache.
* **`--clear-cache`**: Clear the history cache.
* **`--logout`**: Clear saved credentials from the system keychain and remove local session files.
* **`--version`**: Print the installed version information.

### Ignored File Extensions

Multiple extensions can be configured as a comma-separated list:

```yaml
file_selection.ignore_extensions: ".out,.exe,.o,.log"
```
