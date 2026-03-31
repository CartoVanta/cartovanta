#! /usr/bin/env perl
# cartovanta txtdeck - Portable subcommand for generating text-based card decks
# Copyright (C) 2026  Sophia Elizabeth Shapira
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


use strict;
use warnings;

# cartovanta textdeck-style generator in Perl
#
# This program creates a CartoVanta deck from:
# - a shared back-of-card image
# - a text file listing card names
# - a default font file used for rendering
# - an output directory that must not already exist
#
# This version is intended as a cartovanta subcommand implementation.
# It does not implement its own --help option.
#
# Major behavioral decisions for this version:
# - no built-in --help option
# - no notes.txt output
# - no --size option
# - --height changes the generated front-card size while preserving
#   the back-image aspect ratio, and deck.json reflects that size
# - the Perl/ImageMagick version uses explicit font file paths rather than
#   relying on ImageMagick font-family name resolution

use Getopt::Long qw(GetOptions);
use JSON::PP;
use File::Basename qw(fileparse);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Open3;
use POSIX qw(strftime);
use Symbol qw(gensym);

our %opt;    # Parsed option state for the whole program.

my $gc_cartovanta_format_id = 'cartovanta-v0.1';    # Deck format identifier written to output files.


# Return the default version string for newly generated decks.
sub default_version_string
{
    my $lc_out;    # Default version string based on the current UTC date.

    $lc_out = strftime('%Y-%m-%d-1', gmtime());
    return $lc_out;
}


# Stop the program with a user-facing error message.
sub fail
{
    my ($lc_message) = @_;    # The error message to print before exiting.

    die "Error: $lc_message\n";
}


# Validate that a value is a positive integer and return it.
sub require_positive_int
{
    my ($lc_value, $lc_label) = @_;    # Value to check, and the option/field name for errors.

    if ( !defined($lc_value) )
    {
        fail("$lc_label requires a value.");
    }

    if ( $lc_value !~ /\A\d+\z/ )
    {
        fail("$lc_label expects a positive integer.");
    }

    if ( $lc_value <= 0 )
    {
        fail("$lc_label must be positive.");
    }

    return int($lc_value);
}


# Validate that a value is a nonnegative integer and return it.
sub require_nonnegative_int
{
    my ($lc_value, $lc_label) = @_;    # Value to check, and the option/field name for errors.

    if ( !defined($lc_value) )
    {
        fail("$lc_label requires a value.");
    }

    if ( $lc_value !~ /\A\d+\z/ )
    {
        fail("$lc_label expects a nonnegative integer.");
    }

    return int($lc_value);
}


# Validate that a value is a positive number and return it.
sub require_positive_number
{
    my ($lc_value, $lc_label) = @_;    # Value to check, and the option/field name for errors.

    if ( !defined($lc_value) )
    {
        fail("$lc_label requires a value.");
    }

    if ( $lc_value !~ /\A(?:\d+(?:\.\d*)?|\.\d+)\z/ )
    {
        fail("$lc_label expects a positive number.");
    }

    if ( $lc_value <= 0 )
    {
        fail("$lc_label must be positive.");
    }

    return 0 + $lc_value;
}


# Return the ImageMagick executable path, or die if none can be found.
sub find_magick
{
    my @lc_candidates;    # Hard-coded executable locations to try first.
    my $lc_found;         # Executable path discovered from the shell.

    @lc_candidates = (
        '/usr/bin/magick',
        '/usr/local/bin/magick',
        '/opt/homebrew/bin/magick',
        '/bin/magick',
    );

    foreach my $lc_candidate (@lc_candidates)
    {
        if ( -x $lc_candidate )
        {
            return $lc_candidate;
        }
    }

    $lc_found = qx{command -v magick 2>/dev/null};
    chomp($lc_found);
    if ( $lc_found ne '' )
    {
        return $lc_found;
    }

    $lc_found = qx{command -v convert 2>/dev/null};
    chomp($lc_found);
    if ( $lc_found ne '' )
    {
        return $lc_found;
    }

    fail('ImageMagick executable not found.');
}


# Run an external command and die with stderr if it fails.
sub run_cmd_or_die
{
    my (@lc_cmd) = @_;    # Command and arguments to execute.

    my $lc_err_fh;        # Filehandle that captures stderr from the child process.
    my $lc_pid;           # PID of the child process.
    my $lc_status;        # Exit status of the child process.
    my $lc_err_text;      # Collected stderr text from the child process.

    $lc_err_fh = gensym();
    $lc_pid = open3(undef, undef, $lc_err_fh, @lc_cmd);
    waitpid($lc_pid, 0);
    $lc_status = $?;

    $lc_err_text = do {
        local $/ = undef;
        <$lc_err_fh>;
    };

    if ( $lc_status != 0 )
    {
        if ( defined($lc_err_text) )
        {
            $lc_err_text =~ s/\A\s+//;
            $lc_err_text =~ s/\s+\z//;
        }

        if ( !(defined($lc_err_text)) || ($lc_err_text eq '') )
        {
            fail('External ImageMagick command failed.');
        }

        fail($lc_err_text);
    }
}


# Infer an image's width and height using ImageMagick identify.
sub infer_image_size
{
    my ($lc_path) = @_;    # Path to the image whose dimensions we need.

    my $lc_magick;         # ImageMagick executable path.
    my $lc_out;            # Raw output from identify.
    my $lc_width;          # Parsed image width.
    my $lc_height;         # Parsed image height.

    $lc_magick = find_magick();
    $lc_out = qx{$lc_magick identify -format "%w %h" "$lc_path" 2>/dev/null};
    chomp($lc_out);

    if ( $lc_out !~ /\A(\d+)\s+(\d+)\z/ )
    {
        fail("Could not infer image dimensions from '$lc_path'.");
    }

    $lc_width = int($1);
    $lc_height = int($2);

    return ($lc_width, $lc_height);
}


# Return the lowercase file extension for the back image, without the dot.
sub detect_back_extension
{
    my ($lc_path) = @_;    # Path to the back image file.

    my $lc_ext;            # Parsed lowercase extension.

    $lc_ext = lc( (fileparse($lc_path, qr/\.[^.]*/))[2] );
    $lc_ext =~ s/\A\.//;

    if ( ($lc_ext ne 'png') && ($lc_ext ne 'jpg') && ($lc_ext ne 'jpeg') && ($lc_ext ne 'webp') )
    {
        fail('Back image must have extension .png, .jpg, .jpeg, or .webp.');
    }

    return $lc_ext;
}


# Turn a directory name into a deck id that fits simple identifier expectations.
sub sanitize_deck_id
{
    my ($lc_source) = @_;    # Source text from which to derive a deck id.

    my $lc_lower;            # Lowercased form of the source text.

    $lc_lower = lc($lc_source);
    $lc_lower =~ s/[^a-z0-9]+/-/g;
    $lc_lower =~ s/\A-+//;
    $lc_lower =~ s/-+\z//;

    if ( $lc_lower eq '' )
    {
        return 'deck';
    }

    return $lc_lower;
}


# Convert one raw input line into a rendered card name, or undef if ignored.
sub parse_input_line
{
    my ($lc_raw_line) = @_;    # Raw line from the source file.

    my $lc_work;               # Working copy of the line while parsing escapes.
    my $lc_has_barrier;        # Whether the line contains at least one \k barrier.
    my @lc_parts;              # Explicit \n-separated parts before trimming.
    my @lc_processed;          # Final paragraph strings after trimming.
    my $lc_part;               # One explicit paragraph while processing.
    my $lc_text;               # Recombined final card name text.

    if ( $lc_raw_line !~ /\S/ )
    {
        return undef;
    }

    if ( $lc_raw_line =~ /\A\s*#/ )
    {
        return undef;
    }

    $lc_work = $lc_raw_line;
    $lc_has_barrier = ( $lc_work =~ /\\k/ ) ? 1 : 0;
    @lc_parts = split(/\\n/, $lc_work, -1);
    @lc_processed = ();

    foreach $lc_part (@lc_parts)
    {
        my $lc2_left_blocked;    # Whether a leading trim barrier is present in this paragraph.
        my $lc2_right_blocked;   # Whether a trailing trim barrier is present in this paragraph.
        my $lc2_piece;           # Working paragraph copy before final unescaping.

        $lc2_piece = $lc_part;
        $lc2_left_blocked = ( $lc2_piece =~ s/\A\\k// ) ? 1 : 0;
        $lc2_right_blocked = ( $lc2_piece =~ s/\\k\z// ) ? 1 : 0;
        $lc2_piece =~ s/\\k//g;

        if ( !$lc2_left_blocked )
        {
            $lc2_piece =~ s/\A\s+//;
        }

        if ( !$lc2_right_blocked )
        {
            $lc2_piece =~ s/\s+\z//;
        }

        $lc2_piece =~ s/\\\\/__CARTOVANTA_LITERAL_BACKSLASH__/g;
        $lc2_piece =~ s/\\#/#/g;
        $lc2_piece =~ s/__CARTOVANTA_LITERAL_BACKSLASH__/\\/g;

        push(@lc_processed, $lc2_piece);
    }

    $lc_text = join("\n", @lc_processed);

    if ( ($lc_text eq '') && !$lc_has_barrier )
    {
        return undef;
    }

    return $lc_text;
}


# Load the input file and return the list of card-name strings.
sub read_cards_from_input_file
{
    my ($lc_path) = @_;    # Path to the input text file.

    my $lc_fh;             # Filehandle for the input file.
    my @lc_cards;          # Parsed card names that will become cards.
    my $lc_line;           # One raw line from the input file.
    my $lc_card_name;      # Parsed card name returned from parse_input_line().

    open($lc_fh, '<', $lc_path) or fail("Could not open input file '$lc_path'.");

    @lc_cards = ();

    while ( $lc_line = <$lc_fh> )
    {
        chomp($lc_line);
        $lc_card_name = parse_input_line($lc_line);

        if ( defined($lc_card_name) )
        {
            push(@lc_cards, $lc_card_name);
        }
    }

    close($lc_fh);
    return @lc_cards;
}


# Register one line-specific font override from the option parser.
sub register_lfont
{
    my ($lc_line_no, $lc_font_path) = @_;    # Line number and replacement font file path.

    if ( $lc_line_no < 1 )
    {
        fail('--lfont line number must be at least 1.');
    }

    if ( !-f $lc_font_path )
    {
        fail("--lfont font file not found: $lc_font_path");
    }

    $opt{'line_overrides'}->{$lc_line_no}->{'font_path'} = $lc_font_path;
}


# Register one line-specific absolute font-size override from the option parser.
sub register_lfsize
{
    my ($lc_line_no, $lc_font_size) = @_;    # Line number and absolute font size.

    if ( $lc_line_no < 1 )
    {
        fail('--lfsize line number must be at least 1.');
    }

    $lc_font_size = require_positive_number($lc_font_size, '--lfsize');

    if ( defined($opt{'line_overrides'}->{$lc_line_no}->{'percent_size'}) )
    {
        fail("Line $lc_line_no cannot use both --lfsize and --lfsizep.");
    }

    $opt{'line_overrides'}->{$lc_line_no}->{'absolute_size'} = $lc_font_size;
}


# Register one line-specific percentage font-size override from the option parser.
sub register_lfsizep
{
    my ($lc_line_no, $lc_percent_size) = @_;    # Line number and percentage size.

    if ( $lc_line_no < 1 )
    {
        fail('--lfsizep line number must be at least 1.');
    }

    $lc_percent_size = require_positive_number($lc_percent_size, '--lfsizep');

    if ( defined($opt{'line_overrides'}->{$lc_line_no}->{'absolute_size'}) )
    {
        fail("Line $lc_line_no cannot use both --lfsize and --lfsizep.");
    }

    $opt{'line_overrides'}->{$lc_line_no}->{'percent_size'} = $lc_percent_size;
}


# Parse command-line options into the global %opt hash.
sub parse_options
{
    $opt{'version'} = default_version_string();
    $opt{'line_overrides'} = {};

    GetOptions(
        \%opt,
        'font=s',
        'fsize=f',
        'vmargin=i',
        'hmargin=i',
        'deck-id=s',
        'deck-name=s',
        'version=s',
        'height=i',
        'lfont=s{2}' => sub {
            my ($lc_name, @lc_values) = @_;    # Callback name and the two option arguments.
            register_lfont($lc_values[0], $lc_values[1]);
        },
        'lfsize=s{2}' => sub {
            my ($lc_name, @lc_values) = @_;    # Callback name and the two option arguments.
            register_lfsize($lc_values[0], $lc_values[1]);
        },
        'lfsizep=s{2}' => sub {
            my ($lc_name, @lc_values) = @_;    # Callback name and the two option arguments.
            register_lfsizep($lc_values[0], $lc_values[1]);
        },
    ) or fail('Invalid option syntax.');

    if ( @ARGV != 4 )
    {
        fail('Expected positional arguments: [back-image] [input-file] [default-font-file] [output-directory].');
    }

    $opt{'back_image_path'} = $ARGV[0];
    $opt{'input_file_path'} = $ARGV[1];
    $opt{'default_font_path'} = $ARGV[2];
    $opt{'output_directory_path'} = $ARGV[3];

    if ( defined($opt{'font'}) )
    {
        $opt{'default_font_path'} = $opt{'font'};
    }

    if ( !-f $opt{'default_font_path'} )
    {
        fail("Default font file not found: $opt{'default_font_path'}");
    }

    if ( defined($opt{'height'}) )
    {
        $opt{'height'} = require_positive_int($opt{'height'}, '--height');
    }

    if ( defined($opt{'fsize'}) )
    {
        $opt{'fsize'} = require_positive_number($opt{'fsize'}, '--fsize');
    }

    if ( defined($opt{'vmargin'}) )
    {
        $opt{'vmargin'} = require_nonnegative_int($opt{'vmargin'}, '--vmargin');
    }

    if ( defined($opt{'hmargin'}) )
    {
        $opt{'hmargin'} = require_nonnegative_int($opt{'hmargin'}, '--hmargin');
    }
}


# Build the list of styled paragraphs for one card name.
sub build_styled_paragraphs
{
    my ($lc_card_name, $lc_card_height) = @_;    # Card name text, and generated card height in pixels.

    my $lc_general_size;                         # Default font size for lines without a line-specific override.
    my @lc_paragraph_texts;                      # Explicit newline-separated paragraphs from the card name.
    my @lc_styled;                               # Paragraph records with font and size information.
    my $lc_index;                                # Zero-based paragraph index while iterating.

    $lc_general_size = defined($opt{'fsize'}) ? $opt{'fsize'} : ($lc_card_height * 0.12);
    @lc_paragraph_texts = split(/\n/, $lc_card_name, -1);
    @lc_styled = ();

    for ( $lc_index = 0 ; $lc_index <= $#lc_paragraph_texts ; $lc_index += 1 )
    {
        my $lc2_line_no;        # Human-readable 1-based paragraph number.
        my $lc2_override;       # Line override hash for this paragraph, if any.
        my $lc2_font_path;      # Final font file path to use for this paragraph.
        my $lc2_font_size;      # Final base font size to use for this paragraph.

        $lc2_line_no = $lc_index + 1;
        $lc2_override = $opt{'line_overrides'}->{$lc2_line_no} || {};
        $lc2_font_path = defined($lc2_override->{'font_path'}) ? $lc2_override->{'font_path'} : $opt{'default_font_path'};

        if ( defined($lc2_override->{'absolute_size'}) )
        {
            $lc2_font_size = $lc2_override->{'absolute_size'};
        }
        elsif ( defined($lc2_override->{'percent_size'}) )
        {
            $lc2_font_size = $lc_general_size * ($lc2_override->{'percent_size'} / 100.0);
        }
        else
        {
            $lc2_font_size = $lc_general_size;
        }

        push(
            @lc_styled,
            {
                'text' => $lc_paragraph_texts[$lc_index],
                'font_path' => $lc2_font_path,
                'base_font_size' => $lc2_font_size,
            }
        );
    }

    return @lc_styled;
}


# Render one styled paragraph into a temporary transparent PNG.
sub render_paragraph_image
{
    my ($lc_output_path, $lc_paragraph_ref, $lc_text_width, $lc_text_height) = @_;    # Output path, paragraph data, and text-box bounds.

    my $lc_magick;        # ImageMagick executable path.
    my $lc_pointsize;     # Point size used to render this paragraph.
    my $lc_temp_fh;       # Filehandle for the temporary paragraph text file.
    my $lc_temp_path;     # Temporary text file path for ImageMagick caption input.

    $lc_magick = find_magick();
    $lc_pointsize = int( ($lc_paragraph_ref->{'base_font_size'}) + 0.5 );
    ($lc_temp_fh, $lc_temp_path) = tempfile('cartovanta-paragraph-XXXXXX', TMPDIR => 1, UNLINK => 0);
    print {$lc_temp_fh} $lc_paragraph_ref->{'text'};
    close($lc_temp_fh);

    run_cmd_or_die(
        $lc_magick,
        '-background', 'none',
        '-fill', 'black',
        '-font', $lc_paragraph_ref->{'font_path'},
        '-gravity', 'center',
        '-size', "${lc_text_width}x${lc_text_height}",
        '-pointsize', $lc_pointsize,
        'caption:@' . $lc_temp_path,
        '-trim',
        '+repage',
        $lc_output_path,
    );

    unlink($lc_temp_path);
}


# Render one card face as a PNG using ImageMagick.
#
# This version now renders each explicit paragraph separately so that
# per-line font-path and font-size overrides actually affect output.
sub render_card_face
{
    my ($lc_output_path, $lc_card_name, $lc_width, $lc_height) = @_;    # Output path, card text, and generated dimensions.

    my $lc_magick;            # ImageMagick executable path.
    my $lc_hmargin;           # Left/right text margin in pixels.
    my $lc_vmargin;           # Top/bottom text margin in pixels.
    my $lc_text_width;        # Width of the usable text box.
    my $lc_text_height;       # Height of the usable text box.
    my @lc_styled;            # Styled paragraphs used to build the card.
    my $lc_temp_dir;          # Temporary directory that holds rendered paragraph images.
    my @lc_para_paths;        # Paragraph-image paths in render order.
    my @lc_para_heights;      # Heights of rendered paragraph images.
    my $lc_index;             # Paragraph index while rendering and measuring.
    my $lc_para_path;         # Temporary image path for one rendered paragraph.
    my $lc_para_width;        # Width of one rendered paragraph image.
    my $lc_para_height;       # Height of one rendered paragraph image.
    my $lc_gap_height;        # Vertical gap inserted between explicit paragraphs.
    my $lc_total_height;      # Total rendered paragraph height plus gaps.
    my $lc_offset_y;          # Top offset used to vertically center the text block.
    my @lc_cmd;               # Final ImageMagick command used to composite the card.

    $lc_magick = find_magick();
    $lc_hmargin = defined($opt{'hmargin'}) ? $opt{'hmargin'} : int( ($lc_width * 0.10) + 0.5 );
    $lc_vmargin = defined($opt{'vmargin'}) ? $opt{'vmargin'} : int( ($lc_height * 0.12) + 0.5 );
    $lc_text_width = $lc_width - (2 * $lc_hmargin);
    $lc_text_height = $lc_height - (2 * $lc_vmargin);

    if ( ($lc_text_width <= 0) || ($lc_text_height <= 0) )
    {
        fail('Margins leave no drawable text box.');
    }

    if ( $lc_card_name eq '' )
    {
        run_cmd_or_die(
            $lc_magick,
            '-size', "${lc_width}x${lc_height}",
            'xc:white',
            $lc_output_path,
        );
        return;
    }

    @lc_styled = build_styled_paragraphs($lc_card_name, $lc_height);
    $lc_temp_dir = File::Temp::tempdir('cartovanta-card-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    @lc_para_paths = ();
    @lc_para_heights = ();
    $lc_total_height = 0;

    for ( $lc_index = 0 ; $lc_index <= $#lc_styled ; $lc_index += 1 )
    {
        $lc_para_path = File::Spec->catfile($lc_temp_dir, 'paragraph-' . $lc_index . '.png');
        render_paragraph_image($lc_para_path, $lc_styled[$lc_index], $lc_text_width, $lc_text_height);
        ($lc_para_width, $lc_para_height) = infer_image_size($lc_para_path);
        push(@lc_para_paths, $lc_para_path);
        push(@lc_para_heights, $lc_para_height);
        $lc_total_height += $lc_para_height;
    }

    if ( @lc_styled > 1 )
    {
        $lc_gap_height = int( (($lc_styled[0]->{'base_font_size'}) * 0.45) + 0.5 );
        $lc_total_height += ( $lc_gap_height * $#lc_styled );
    }
    else
    {
        $lc_gap_height = 0;
    }

    if ( $lc_total_height > $lc_text_height )
    {
        fail("Unable to fit text inside card bounds for card name '$lc_card_name'.");
    }

    $lc_offset_y = $lc_vmargin + int( (($lc_text_height - $lc_total_height) / 2) + 0.5 );
    @lc_cmd = (
        $lc_magick,
        '-size', "${lc_width}x${lc_height}",
        'xc:white',
    );

    for ( $lc_index = 0 ; $lc_index <= $#lc_para_paths ; $lc_index += 1 )
    {
        push(
            @lc_cmd,
            $lc_para_paths[$lc_index],
            '-gravity', 'north',
            '-geometry', '+0+' . $lc_offset_y,
            '-composite',
        );

        $lc_offset_y += $lc_para_heights[$lc_index];

        if ( $lc_index < $#lc_para_paths )
        {
            $lc_offset_y += $lc_gap_height;
        }
    }

    push(@lc_cmd, $lc_output_path);
    run_cmd_or_die(@lc_cmd);
}


# Create the output deck structure and all generated files.
sub create_output_structure
{
    my (@lc_cards) = @_;    # Parsed card names that will become generated card files.

    my $lc_output_dir;      # Destination directory for the generated deck.
    my $lc_parent_dir;      # Parent directory that must already exist.
    my $lc_back_ext;        # Lowercase extension of the back image.
    my $lc_back_width;      # Back-image width inferred from the source image.
    my $lc_back_height;     # Back-image height inferred from the source image.
    my $lc_front_height;    # Generated front-card height after applying --height or defaults.
    my $lc_front_width;     # Generated front-card width calculated from the back-image ratio.
    my $lc_imagia_dir;      # imagia/ output directory path.
    my $lc_back_copy_name;  # Output filename for the copied back image.
    my $lc_digits;          # Zero-padding width used for generated card filenames.
    my @lc_json_cards;      # Card records written into deck.json.
    my $lc_index;           # Zero-based card index while generating output.
    my $lc_number;          # One-based card number.
    my $lc_number_string;   # Zero-padded card number string.
    my $lc_front_name;      # Generated PNG filename for a front image.
    my $lc_front_path;      # Filesystem path for a generated front image.
    my $lc_deck_dir_name;   # Last path component of the output directory.
    my $lc_deck_name;       # Final deck name written to output files.
    my $lc_deck_id;         # Final deck id written to output files.
    my $lc_json;            # JSON encoder object.
    my $lc_deck_data;       # Perl structure that becomes deck.json.
    my $lc_meta_data;       # Perl structure that becomes meta.json.
    my $lc_deck_fh;         # Filehandle for deck.json.
    my $lc_meta_fh;         # Filehandle for meta.json.

    $lc_output_dir = $opt{'output_directory_path'};
    $lc_parent_dir = (fileparse($lc_output_dir))[1];

    if ( -e $lc_output_dir )
    {
        fail("Output directory already exists: $lc_output_dir");
    }

    if ( !-d $lc_parent_dir )
    {
        fail("Parent directory does not exist: $lc_parent_dir");
    }

    if ( !-f $opt{'back_image_path'} )
    {
        fail("Back image not found: $opt{'back_image_path'}");
    }

    if ( !-f $opt{'input_file_path'} )
    {
        fail("Input file not found: $opt{'input_file_path'}");
    }

    $lc_back_ext = detect_back_extension($opt{'back_image_path'});
    ($lc_back_width, $lc_back_height) = infer_image_size($opt{'back_image_path'});
    $lc_front_height = defined($opt{'height'}) ? $opt{'height'} : $lc_back_height;
    $lc_front_width = int( (($lc_back_width * $lc_front_height) / $lc_back_height) + 0.5 );

    if ( $lc_front_width <= 0 )
    {
        fail('--height results in an invalid card width.');
    }

    make_path($lc_output_dir);
    $lc_imagia_dir = File::Spec->catdir($lc_output_dir, 'imagia');
    make_path($lc_imagia_dir);

    $lc_back_copy_name = 'back.' . $lc_back_ext;
    copy(
        $opt{'back_image_path'},
        File::Spec->catfile($lc_imagia_dir, $lc_back_copy_name),
    ) or fail('Could not copy back image into imagia/.');

    $lc_digits = length( scalar(@lc_cards) || 1 );
    @lc_json_cards = ();

    for ( $lc_index = 0 ; $lc_index <= $#lc_cards ; $lc_index += 1 )
    {
        $lc_number = $lc_index + 1;
        $lc_number_string = sprintf("%0*d", $lc_digits, $lc_number);
        $lc_front_name = 'card-' . $lc_number_string . '.png';
        $lc_front_path = File::Spec->catfile($lc_imagia_dir, $lc_front_name);

        render_card_face(
            $lc_front_path,
            $lc_cards[$lc_index],
            $lc_front_width,
            $lc_front_height,
        );

        push(
            @lc_json_cards,
            {
                'id' => 'card-' . $lc_number_string,
                'name' => $lc_cards[$lc_index],
                'frontImage' => 'imagia/' . $lc_front_name,
                'meta' => {},
            }
        );
    }

    $lc_deck_dir_name = (File::Spec->splitdir($lc_output_dir))[-1];
    $lc_deck_name = defined($opt{'deck-name'}) ? $opt{'deck-name'} : $lc_deck_dir_name;
    $lc_deck_id = defined($opt{'deck-id'}) ? $opt{'deck-id'} : sanitize_deck_id($lc_deck_dir_name);

    $lc_deck_data = {
        'format' => $gc_cartovanta_format_id,
        'deckId' => $lc_deck_id,
        'deckName' => $lc_deck_name,
        'version' => $opt{'version'},
        'backImage' => 'imagia/' . $lc_back_copy_name,
        'cardSize' => {
            'width' => $lc_front_width,
            'height' => $lc_front_height,
        },
        'meta' => {},
        'cards' => \@lc_json_cards,
    };

    $lc_meta_data = {
        'format' => $gc_cartovanta_format_id,
        'deckName' => $lc_deck_name,
        'meta' => {},
    };

    $lc_json = JSON::PP->new()->utf8()->pretty();

    open($lc_deck_fh, '>', File::Spec->catfile($lc_output_dir, 'deck.json')) or fail('Could not create deck.json.');
    print {$lc_deck_fh} $lc_json->encode($lc_deck_data);
    close($lc_deck_fh);

    open($lc_meta_fh, '>', File::Spec->catfile($lc_output_dir, 'meta.json')) or fail('Could not create meta.json.');
    print {$lc_meta_fh} $lc_json->encode($lc_meta_data);
    close($lc_meta_fh);
}


# Main program flow.
sub main
{
    my @lc_cards;    # Parsed card names from the input file.

    parse_options();
    @lc_cards = read_cards_from_input_file($opt{'input_file_path'});
    create_output_structure(@lc_cards);
}


main();
