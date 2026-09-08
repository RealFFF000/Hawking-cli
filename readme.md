# Hawking-cli

A lightweight Bash utility to submit assignment files to Hawking, automatically detect response errors, decode base64 test cases, and display a character-by-character colorized diff between expected and actual outputs.

## Requirements

* **`curl`**
* **`jq`** (`brew install jq` or `sudo apt install jq`)
* **`bash`** (v4.0+)

## Features

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

### Where can I find the module ID?

It's the number at the very end of the URL - for example https://hawking.computing.dcu.ie/hawking/120 would have an ID of 120


### Where can I find the cookie the script asks me for?

https://hawking.computing.dcu.ie/hawking > right click > inspect > application > cookies > and you copy the value of PHPSESSID

I may add the login support one day
