# cartovanta txtdeck

## NAME

**[subcommand name to be chosen later]** — Generate a CartoVanta deck from a text file, a back-of-card image, and font files.

## SYNOPSIS

```text
cartovanta txtdeck [back-image] [input-file] [default-font-file] [output-directory] [options]
```

## DESCRIPTION

This subcommand generates a CartoVanta deck directory from a text source.

It copies the supplied back-of-card image into the generated deck, creates one front image per card, and writes the deck metadata files needed by the CartoVanta format.

The generated front images are PNG files.
The generated deck metadata reflects the actual generated front-card dimensions.

This subcommand is intended to be run through `cartovanta`.
It does **not** implement its own `--help` option.

## REQUIRED POSITIONAL ARGUMENTS

### `[back-image]`

Path to the shared back-of-card image.

The file must exist.
Its extension must be one of the following:

* `.png`
* `.jpg`
* `.jpeg`
* `.webp`

The back image is copied into the generated deck's `imagia/` directory.
Its dimensions are also used as the geometric basis for the generated front-card dimensions.

### `[input-file]`

Path to the text file containing the card-name source.

The file must exist.
Each non-ignored input line produces one card.

### `[default-font-file]`

Path to the default font file used when rendering card text.

The file must exist.
This should be the pathname of a font file such as a `.ttf`, `.otf`, or `.ttc` file.

This positional argument supplies the default font for lines that do not receive a line-specific font override.

### `[output-directory]`

Path to the output directory to be created.

This directory must **not** already exist.
Its parent directory **must** already exist.

## OPTIONS

### `--height [pixels]`

Generate front-card images at the specified height, in pixels.

When this option is used, the generated front-card width is recalculated so that the geometric ratio of the back image is preserved.

The resulting generated dimensions are the dimensions written into `deck.json`.

This option changes the generated deck geometry.
It is **not** a viewer-display option.

### `--font [font-file]`

Override the default font file.

This option takes a font-file pathname.
It overrides the `[default-font-file]` positional argument.

### `--lfont [line#] [font-file]`

Set the font file for a specific explicit line number within a card name.

The line number starts at **1**.
The font must be given as a font-file pathname.

This applies to explicit lines created by `\n` in the input syntax.

### `--fsize [font-size]`

Set the general font size.

This is the base size used for lines that do not receive a line-specific size override.

### `--lfsize [line#] [font-size]`

Set an absolute font size for a specific explicit line number.

The line number starts at **1**.

A given line may not use both `--lfsize` and `--lfsizep`.

### `--lfsizep [line#] [percent]`

Set the font size for a specific explicit line as a percentage of the general font size.

The line number starts at **1**.

A given line may not use both `--lfsizep` and `--lfsize`.

### `--vmargin [pixels]`

Set the top and bottom text margins.

If this option is omitted, a default vertical margin is chosen automatically from the card height.

### `--hmargin [pixels]`

Set the left and right text margins.

If this option is omitted, a default horizontal margin is chosen automatically from the card width.

### `--deck-id [id]`

Override the generated `deckId` value written to `deck.json`.

If omitted, the deck id is derived from the output-directory name.

### `--deck-name [name]`

Override the generated `deckName` value written to `deck.json` and `meta.json`.

If omitted, the deck name is derived from the output-directory name.

### `--version [value]`

Override the generated deck version string.

If omitted, the default version string is based on the current UTC date in the form:

```text
YYYY-MM-DD-1
```

## INPUT-FILE SYNTAX

### Ignored lines

A line is ignored if either of the following is true:

* it is blank or contains only whitespace
* its first nonblank character is `#`

### One card per non-ignored input line

Each non-ignored input line produces one card.

### Supported escapes inside content

The following backslash escapes are recognized inside content:

* `\\` — literal backslash
* `\#` — literal hash sign
* `\n` — explicit line break
* `\k` — trimming barrier

### Trimming behavior

Leading and trailing whitespace is trimmed from each explicit `\n`-separated part.

The escape `\k` acts as a trimming barrier.
It is not rendered, but it prevents trimming across its position.

A line whose only meaningful content is trimming barriers may therefore still produce an intentionally empty rendered card name.

## OUTPUT STRUCTURE

The generated output directory has this structure:

```text
[output-directory]/
  deck.json
  meta.json
  imagia/
    back.[original-extension]
    card-N.png
```

When needed, the generated card numbers may be zero-padded.

## NOTES

This subcommand is for **deck generation**, not viewer presentation.

Viewer-side decisions such as limiting on-screen spread-card height belong in the HTML/JavaScript layer of `cartovanta-web`, not here.

## EXAMPLE

```text
cartovanta [subcommand] back.png cards.txt /path/to/font.ttf mydeck
```

Example with options:

```text
cartovanta [subcommand] back.png cards.txt /path/to/font.ttf mydeck \
  --height 900 \
  --fsize 84 \
  --lfont 2 /path/to/other-font.ttf \
  --lfsizep 2 80 \
  --vmargin 90 \
  --hmargin 70 \
  --deck-name "Greek Myth Deck"
```

## STATUS

This helpfile describes the current intended behavior of the Perl/ImageMagick implementation.
Some rendering details may still evol

