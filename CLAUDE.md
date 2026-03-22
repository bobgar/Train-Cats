# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Train Cats

A game about cats in a cat caffe trying to knock over trains.

## Tech Stack

- Godot 4.6.1 (GDScript only, no C#)
- WebGL/HTML5 export target
- Godot binary: `C:\tools\Godot_v4.6.1-stable_win64.exe`

## Commands

Run the game in Godot editor:
```
"C:\tools\Godot_v4.6.1-stable_win64.exe" --path "c:\projects\WillowsGame"
```

Export as HTML5 (for testing):
```
"C:\tools\Godot_v4.6.1-stable_win64.exe" --path "c:\projects\WillowsGame" --export-release "HTML5" "exports/index.html"
```

Run a specific scene directly:
```
"C:\tools\Godot_v4.6.1-stable_win64.exe" --path "c:\projects\WillowsGame" res://scenes/main.tscn
```

## Architecture

**Key patterns:**
- Prefer signals over direct node references between unrelated systems
- Components should be self-contained and communicate upward via signals
- Autoloads handle cross-scene state; scenes should not directly reference each other

## Code Style

- `snake_case` for functions and variables
- `PascalCase` for class names and node names
- Type hints required on all function parameters and return types
- `@export` vars for designer-facing properties

## Testing

Always export as HTML5 and verify there are no errors before considering a feature complete. Report any export or runtime errors found.
