# Hawking-cli

## AKA einstein-but-for-losers


A lightweight Bash utility to submit assignment files to Hawking, automatically detect response errors, decode base64 test cases, and display a character-by-character colorized diff between expected and actual outputs.

## Requirements

* **`curl`**
* **`jq`** (`brew install jq` or `sudo apt install jq`)
* **`bash`** (v4.0+)

## Features

* **Auto-Login Management (`hawking-login`):** Automatically triggers authentication and handles cookie-jar storage (`~/.hawking_cookie`) whenever sessions expire or are missing.
* **Module ID Caching & Cycling:** Remembers successfully used module IDs, stores them with **most-recently-used prioritization**, and automatically **cycles through all cached IDs** if a `404` or module mismatch occurs.
* **Auto-File Detection:** Picks the most recently modified file in the current directory if no file is specified.
* **Smart Session Validation:** Detects HTTP status codes (401/403 vs 404/500) so wrong assignment IDs won't overwrite your saved session cookie.
* **Base64 Decoding:** Decodes `.testStdout` values provided in the JSON payload using `base64`.
* **Visual Diffing:** Prints character-level differences in **red** on test failures while keeping character alignment clear.
* **Debug Mode:** Allows dumping raw JSON responses directly to stdout.

## Installation
```bash
git clone <this repo>
cd hawking-cli
./install.sh
```

## Usage

### Basic Command Structure

```bash
hawking [--debug] <module_id> [file_to_submit]
```
