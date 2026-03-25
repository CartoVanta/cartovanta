## Usage

`deckgen.swift [back-image] [input-file] [output-directory] [options]`

## Required positional arguments

- `[back-image]` — Path to the shared back-of-card image.
- `[input-file]` — Path to the text file containing card names.
- `[output-directory]` — Path to a directory that must not already exist.

## Options

- `--size [width] [height]` — Override card dimensions instead of inferring them from the back image.
- `--height [pixels]` — Override only the `deck.json` card height while preserving the base aspect ratio.
- `--font [font-name]` — Set the default font for all cards. Default: Helvetica.
- `--lfont [line#] [font-name]` — Set the font for an explicit `\n`-separated line number, starting at 1.
- `--fsize [font-size]` — Set the general font size in points/pixels.
- `--lfsize [line#] [font-size]` — Set an explicit font size in points/pixels for a specific line.
- `--lfsizep [line#] [percent]` — Set a line size as a percentage of the general font size.
- `--vmargin [pixels]` — Set the top and bottom margin.
- `--hmargin [pixels]` — Set the left and right margin.
- `--deck-id [id]` — Override the deckId. Default: derived from output directory name.
- `--deck-name [name]` — Override the deckName. Default: derived from output directory name.
- `--version [value]` — Override the deck version string. Default: current UTC date plus `-1`.
- `--help` — Print this help text.

## Input-file syntax

- Blank or whitespace-only lines are ignored.
- A line whose first nonblank character is an unescaped `#` is ignored as a comment.
- Backslash escapes are recognized inside content:
  - `\\` — literal backslash
  - `\#` — literal hash
  - `\n` — forced paragraph break with extra spacing
  - `\k` — trimming barrier; not rendered, but blocks trimming across its position
- Trimming removes leading/trailing whitespace in each explicit `\n`-separated paragraph, except where blocked by `\k`.
- A line whose sole printable content is `\k` creates a card with an intentionally empty name.

## Output structure

- `[output-directory]/`
  - `deck.json`
  - `meta.json`
  - `notes.txt`
  - `imagia/`
    - `back.[original-extension]`
    - `card-N.png` (or zero-padded when needed)

