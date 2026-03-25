#!/usr/bin/env perl
# cartovanta mdview - A command-line terminal viewer for MarkDown
# install.pl - Main install script for -cartovanta-
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
use utf8;
use open ':std', ':encoding(UTF-8)';

# Coordinate the overall program flow: read options, load the Markdown file,
# render it into styled terminal text, and then send the result to either a
# pager or standard output.
sub main {
    my $lc_file;
    my $lc_mode;
    my $lc_width;
    my $lc_raw_md;
    my $lc_rendered;

    $lc_mode  = 'auto';
    $lc_width = 78;

    parse_args(\$lc_file, \$lc_mode, \$lc_width);

    if (!defined $lc_file) {
        die usage();
    }

    $lc_raw_md   = slurp_file($lc_file);
    $lc_rendered = render_markdown($lc_raw_md, $lc_width);

    output_text($lc_rendered, $lc_mode);
    return 0;
}

# Parse command-line options and fill in the caller's file, mode, and width
# variables. This centralizes argument handling so the rest of the program can
# assume it is working with validated settings.
sub parse_args {
    my $lc_file_ref;
    my $lc_mode_ref;
    my $lc_width_ref;
    my @lc_args;
    my $lc_arg;

    ($lc_file_ref, $lc_mode_ref, $lc_width_ref) = @_;

    @lc_args = @ARGV;

    while (@lc_args) {
        $lc_arg = shift @lc_args;

        if ($lc_arg eq '--pager') {
            $$lc_mode_ref = 'pager';
        }
        elsif ($lc_arg eq '--no-pager') {
            $$lc_mode_ref = 'stdout';
        }
        elsif ($lc_arg =~ /\A--width=(\d+)\z/) {
            $$lc_width_ref = $1;
        }
        elsif ($lc_arg eq '--width') {
            if (!@lc_args) {
                die "--width requires an integer\n";
            }
            $lc_arg = shift @lc_args;
            if ($lc_arg !~ /\A\d+\z/) {
                die "--width requires an integer\n";
            }
            $$lc_width_ref = $lc_arg;
        }
        elsif ($lc_arg eq '--help') {
            print usage();
            exit 0;
        }
        elsif ($lc_arg =~ /\A--/) {
            die "Unknown option: $lc_arg\n" . usage();
        }
        else {
            if (defined $$lc_file_ref) {
                die "Only one input file may be specified\n" . usage();
            }
            $$lc_file_ref = $lc_arg;
        }
    }
}

# Return the command-line help text shown for --help or argument errors.
sub usage {
    return <<"END_USAGE";
Usage:
  cartovanta-mdview [--pager | --no-pager] [--width N] FILE.md

Description:
  Render a restrained Markdown subset as ANSI-styled terminal text.

Options:
  --pager        Force paging through less -R
  --no-pager     Force direct output to stdout
  --width N      Set wrap width (default: 78)
  --help         Show this help
END_USAGE
}

# Read the entire input file as UTF-8 text and normalize line endings to \n so
# the renderer can process the content consistently across platforms.
sub slurp_file {
    my $lc_file;
    my $lc_fh;
    my $lc_content;

    ($lc_file) = @_;

    open($lc_fh, '<:encoding(UTF-8)', $lc_file)
      or die "Could not open '$lc_file' for reading: $!\n";

    local $/;
    $lc_content = <$lc_fh>;

    close($lc_fh)
      or die "Could not close '$lc_file' after reading: $!\n";

    if (!defined $lc_content) {
        $lc_content = '';
    }

    $lc_content =~ s/\r\n/\n/g;
    $lc_content =~ s/\r/\n/g;

    return $lc_content;
}

# Decide whether to write directly to stdout or pipe through a pager, based on
# the requested mode and whether stdout appears to be an interactive terminal.
sub output_text {
    my $lc_text;
    my $lc_mode;
    my $lc_use_pager;
    my $lc_fh;
    my $lc_pager;

    ($lc_text, $lc_mode) = @_;

    if ($lc_mode eq 'pager') {
        $lc_use_pager = 1;
    }
    elsif ($lc_mode eq 'stdout') {
        $lc_use_pager = 0;
    }
    else {
        $lc_use_pager = -t STDOUT ? 1 : 0;
    }

    if ($lc_use_pager) {
        $lc_pager = $ENV{'PAGER'};
        if (!defined $lc_pager || $lc_pager eq '') {
            $lc_pager = 'less -R';
        }

        open($lc_fh, '|-', $lc_pager)
          or die "Could not open pager '$lc_pager': $!\n";

        print {$lc_fh} $lc_text
          or die "Could not write to pager '$lc_pager': $!\n";

        close($lc_fh)
          or die "Pager '$lc_pager' exited unsuccessfully\n";
    }
    else {
        print $lc_text;
    }
}

# Convert the restrained Markdown subset used by CartoVanta helpfiles into
# ANSI-styled terminal text. This is the main block-level renderer that
# classifies lines and dispatches to the appropriate helper routines.
sub render_markdown {
    my $lc_md;
    my $lc_width;
    my @lc_lines;
    my @lc_out;
    my @lc_para;
    my $lc_in_code;
    my @lc_code_lines;
    my $lc_line;
    my $lc_i;
    my $lc_next_line;

    ($lc_md, $lc_width) = @_;

    @lc_lines = split /\n/, $lc_md, -1;
    @lc_out = ();
    @lc_para = ();
    $lc_in_code = 0;
    @lc_code_lines = ();

    for ($lc_i = 0; $lc_i <= $#lc_lines; $lc_i++) {
        $lc_line = $lc_lines[$lc_i];

        # Inside a fenced code block, preserve lines verbatim until the closing
        # fence is encountered.
        if ($lc_in_code) {
            if ($lc_line =~ /\A```/) {
                push @lc_out, render_code_block(\@lc_code_lines);
                @lc_code_lines = ();
                $lc_in_code = 0;
            }
            else {
                push @lc_code_lines, $lc_line;
            }
            next;
        }

        # A new fence ends any current paragraph and starts verbatim code-block
        # collection.
        if ($lc_line =~ /\A```/) {
            flush_para(\@lc_para, \@lc_out, $lc_width);
            $lc_in_code = 1;
            next;
        }

        # Blank lines terminate the current paragraph.
        if ($lc_line =~ /\A\s*\z/) {
            flush_para(\@lc_para, \@lc_out, $lc_width);
            next;
        }

        # Markdown thematic breaks become a dim horizontal rule spanning the
        # configured render width.
        if ($lc_line =~ /\A\s*([-*_])(?:\s*\1){2,}\s*\z/) {
            flush_para(\@lc_para, \@lc_out, $lc_width);
            push @lc_out, stylize('dim', ('─' x $lc_width)) . "\n\n";
            next;
        }

        # Headings are handled separately by level so the most important levels
        # can receive underline-style decoration.
        if ($lc_line =~ /\A(#{1,6})[ \t]+(.*)\z/) {
            my $lc2_level;
            my $lc2_text;
            my $lc2_prefix;
            my $lc2_rendered;
            my $lc2_rule_len;

            flush_para(\@lc_para, \@lc_out, $lc_width);

            $lc2_level = length($1);
            $lc2_text = $2;
            $lc2_text =~ s/\s+\z//;
            $lc2_text = render_inline($lc2_text);

            if ($lc2_level == 1) {
                $lc2_rendered = stylize('h1', ('  ' . $lc2_text));
                push @lc_out, $lc2_rendered . "\n";
                $lc2_rule_len = visible_length(strip_ansi($lc2_text));
                push @lc_out, stylize('h1rule', ('  ' . ('=' x $lc2_rule_len))) . "\n\n";
            }
            elsif ($lc2_level == 2) {
                $lc2_rendered = stylize('h2', $lc2_text);
                push @lc_out, $lc2_rendered . "\n";
                $lc2_rule_len = visible_length(strip_ansi($lc2_text));
                push @lc_out, stylize('h2rule', ('-' x $lc2_rule_len)) . "\n\n";
            }
            else {
                $lc2_prefix = ('#' x $lc2_level) . ' ';
                $lc2_rendered = wrap_styled_text($lc2_prefix . $lc2_text, $lc_width, '');
                push @lc_out, stylize('h3plus', $lc2_rendered) . "\n\n";
            }

            next;
        }

        # Consume a contiguous run of unordered list items as one block,
        # rendering each item with a normalized bullet marker.
        if ($lc_line =~ /\A([ \t]*)([-*+])[ \t]+(.*)\z/) {
            my $lc2_item;
            my $lc2_indent;

            flush_para(\@lc_para, \@lc_out, $lc_width);

            while ($lc_i <= $#lc_lines && $lc_lines[$lc_i] =~ /\A([ \t]*)([-*+])[ \t]+(.*)\z/) {
                $lc2_indent = $1;
                $lc2_item = $3;
                push @lc_out, render_list_item('• ', $lc2_item, $lc_width, $lc2_indent);
                $lc_i++;
            }

            while ($lc_i <= $#lc_lines && $lc_lines[$lc_i] =~ /\A\s*\z/) {
                $lc_i++;
            }

            if ($lc_i <= $#lc_lines) {
                push @lc_out, "\n";
                $lc_i--;
            }

            next;
        }

        # Consume a contiguous run of ordered list items while preserving each
        # item's visible number in the rendered prefix.
        if ($lc_line =~ /\A([ \t]*)(\d+)\.[ \t]+(.*)\z/) {
            my $lc2_num;
            my $lc2_item;
            my $lc2_prefix;
            my $lc2_indent;

            flush_para(\@lc_para, \@lc_out, $lc_width);

            while ($lc_i <= $#lc_lines && $lc_lines[$lc_i] =~ /\A([ \t]*)(\d+)\.[ \t]+(.*)\z/) {
                $lc2_indent = $1;
                $lc2_num = $2;
                $lc2_item = $3;
                $lc2_prefix = $lc2_num . '. ';
                push @lc_out, render_list_item($lc2_prefix, $lc2_item, $lc_width, $lc2_indent);
                $lc_i++;
            }

            while ($lc_i <= $#lc_lines && $lc_lines[$lc_i] =~ /\A\s*\z/) {
                $lc_i++;
            }

            if ($lc_i <= $#lc_lines) {
                push @lc_out, "\n";
                $lc_i--;
            }

            next;
        }

        # Block quotes are rendered immediately rather than accumulated into the
        # paragraph buffer.
        if ($lc_line =~ /\A>[ \t]?(.*)\z/) {
            my $lc2_quote;

            flush_para(\@lc_para, \@lc_out, $lc_width);
            $lc2_quote = $1;
            push @lc_out, render_block_quote($lc2_quote, $lc_width);
            next;
        }

        push @lc_para, $lc_line;
    }

    # If the file ends before a closing fence appears, render the accumulated
    # code anyway so unterminated fenced blocks still display sensibly.
    if ($lc_in_code) {
        push @lc_out, render_code_block(\@lc_code_lines);
    }

    flush_para(\@lc_para, \@lc_out, $lc_width);

    return join('', @lc_out);
}

# Finish the paragraph currently being accumulated, render its inline markup,
# wrap it to the requested width, and append it to the output buffer.
sub flush_para {
    my $lc_para_ref;
    my $lc_out_ref;
    my $lc_width;
    my $lc_text;
    my $lc_rendered;

    ($lc_para_ref, $lc_out_ref, $lc_width) = @_;

    if (!@$lc_para_ref) {
        return;
    }

    # Collapse the paragraph's source lines into a single wrapped prose block
    # before applying inline styling.
    $lc_text = join(' ', map { s/^\s+//r =~ s/\s+$//r } @$lc_para_ref);
    $lc_text = render_inline($lc_text);
    $lc_rendered = wrap_styled_text($lc_text, $lc_width, '');

    push @$lc_out_ref, $lc_rendered . "\n\n";
    @$lc_para_ref = ();
}

# Render a single list item with the supplied bullet or numeric prefix and
# align any wrapped continuation lines under the text rather than the marker.
sub render_list_item {
    my $lc_prefix;
    my $lc_text;
    my $lc_width;
    my $lc_indent;
    my $lc_rendered;
    my $lc_base_indent;

    ($lc_prefix, $lc_text, $lc_width, $lc_base_indent) = @_;
    
    # Set the default for $lc_base_indent if it wasn't defined:
    if ( !(defined($lc_base_indent)) ) { $lc_base_indent = ''; }

    # Continuation lines align under the list text, not under the bullet or
    # list number.
    $lc_indent = $lc_base_indent . (' ' x visible_length($lc_prefix));
    $lc_text = render_inline($lc_text);
    $lc_rendered = wrap_styled_text($lc_base_indent . $lc_prefix . $lc_text, $lc_width, $lc_indent, $lc_base_indent);

    return $lc_rendered . "\n";
}

# Render a single block-quote line with a styled quote bar and wrapped quoted
# text.
sub render_block_quote {
    my $lc_text;
    my $lc_width;
    my $lc_prefix;
    my $lc_indent;
    my $lc_rendered;

    ($lc_text, $lc_width) = @_;

    # Keep the visible quote marker outside the quoted text styling so the bar
    # remains visually distinct.
    $lc_prefix = stylize('quote_bar', '│ ');
    $lc_indent = '  ';
    $lc_text = render_inline($lc_text);
    $lc_rendered = wrap_styled_text($lc_prefix . stylize('quote', $lc_text), $lc_width, $lc_indent);

    return $lc_rendered . "\n\n";
}

# Build the fixed-width separator used above and below fenced code blocks.
sub dotted_fence_line {
    my $lc_line;

    $lc_line = '- ' x 39;
    $lc_line .= '-' if length($lc_line) < 78;
    $lc_line = substr($lc_line, 0, 78);

    return $lc_line;
}

# Render a fenced code block using the dotted separator and preserve each code
# line verbatim inside the styled block.
sub render_code_block {
    my $lc_code_ref;
    my @lc_lines;
    my @lc_out;
    my $lc_line;
    my $lc_fence;

    ($lc_code_ref) = @_;

    @lc_lines = @$lc_code_ref;
    @lc_out = ();
    # Reuse the same separator above and below the code block to frame verbatim
    # content without attempting syntax highlighting.
    $lc_fence = dotted_fence_line();

    push @lc_out, stylize('code_fence', $lc_fence) . "\n";

    foreach $lc_line (@lc_lines) {
        push @lc_out, stylize('codeblock', $lc_line) . "\n";
    }

    push @lc_out, stylize('code_fence', $lc_fence) . "\n";
    push @lc_out, "\n";

    return join('', @lc_out);
}

# Apply the supported inline Markdown transforms in a fixed order so links,
# code spans, strong text, and emphasis are styled before wrapping.
sub render_inline {
    my $lc_text;

    ($lc_text) = @_;

    # Apply inline transforms in a consistent sequence before wrapping.
    $lc_text = render_links($lc_text);
    $lc_text = render_code_spans($lc_text);
    $lc_text = render_strong($lc_text);
    $lc_text = render_emphasis($lc_text);

    return $lc_text;
}

# Convert inline Markdown links into styled link text followed by a dimmer
# parenthesized URL.
sub render_links {
    my $lc_text;

    ($lc_text) = @_;

    $lc_text =~ s{
        \[([^\]]+)\]
        \(
            ([^)]+)
        \)
    }{
        stylize('link_text', $1) . stylize('link_url', " ($2)")
    }gex;

    return $lc_text;
}

# Convert backtick-delimited inline code spans into terminal styling.
sub render_code_spans {
    my $lc_text;

    ($lc_text) = @_;

    $lc_text =~ s{
        `([^`]+)`
    }{
        stylize('code_inline', $1)
    }gex;

    return $lc_text;
}

# Convert the supported strong-emphasis forms (**text** and __text__) into
# bold terminal styling.
sub render_strong {
    my $lc_text;

    ($lc_text) = @_;

    $lc_text =~ s{
        \*\*([^*]+)\*\*
    }{
        stylize('strong', $1)
    }gex;

    $lc_text =~ s{
        __([^_]+)__
    }{
        stylize('strong', $1)
    }gex;

    return $lc_text;
}

# Convert the supported emphasis forms (*text* and _text_) into italic terminal
# styling while avoiding the strong-emphasis delimiters handled elsewhere.
sub render_emphasis {
    my $lc_text;

    ($lc_text) = @_;

    $lc_text =~ s{
        (?<!\*)\*([^*]+)\*(?!\*)
    }{
        stylize('em', $1)
    }gex;

    $lc_text =~ s{
        (?<!_)_([^_]+)_(?!_)
    }{
        stylize('em', $1)
    }gex;

    return $lc_text;
}

# Wrap styled text to the target width while measuring only visible characters,
# so ANSI escape sequences do not distort the layout.
sub wrap_styled_text {
    my $lc_text;
    my $lc_width;
    my $lc_subsequent_indent;
    my @lc_tokens;
    my @lc_lines;
    my $lc_current;
    my $lc_token;
    my $lc_visible_current;
    my $lc_visible_token;

    ($lc_text, $lc_width, $lc_subsequent_indent, $lc_current) = @_;

    if ( !(defined($lc_subsequent_indent)) ) { $lc_subsequent_indent = ''; }
    if ( !(defined($lc_current)) ) { $lc_current = ''; }

    @lc_tokens = split_preserving_ansi_words($lc_text);
    @lc_lines = ();

    foreach $lc_token (@lc_tokens) {
        if ($lc_token =~ /\A\s+\z/) {
            next;
        }

        $lc_visible_current = visible_length(strip_ansi($lc_current));
        $lc_visible_token   = visible_length(strip_ansi($lc_token));

        if (strip_ansi($lc_current) =~ /\A\s*\z/) {
            $lc_current .= $lc_token;
        }
        elsif (($lc_visible_current + 1 + $lc_visible_token) <= $lc_width) {
            $lc_current .= ' ' . $lc_token;
        }
        else {
            push @lc_lines, $lc_current;
            $lc_current = $lc_subsequent_indent . $lc_token;
        }
    }

    if (strip_ansi($lc_current) !~ /\A\s*\z/) {
        push @lc_lines, $lc_current;
    }

    return join("\n", @lc_lines);
}

# Split text into alternating word and whitespace tokens so wrapped output can
# be rebuilt one token at a time without losing embedded ANSI styling.
sub split_preserving_ansi_words {
    my $lc_text;
    my @lc_parts;
    my @lc_tokens;
    my $lc_part;
    my $lc_active_style;
    my @lc_chunks;
    my $lc_chunk;

    ($lc_text) = @_;

    @lc_parts = split /(\e\[[0-9;]*m)/, $lc_text;
    @lc_tokens = ();
    $lc_active_style = '';
    @lc_chunks = ();

    foreach $lc_part (@lc_parts) {
        if ($lc_part =~ /\A\e\[[0-9;]*m\z/) {
            if ($lc_part eq "\e[0m") {
                $lc_active_style = '';
            }
            else {
                $lc_active_style = $lc_part;
            }
            next;
        }

        next if $lc_part eq '';

        foreach $lc_chunk (split /(\s+)/, $lc_part) {
            next if $lc_chunk eq '';

            if ($lc_chunk =~ /\A\s+\z/) {
                push @lc_tokens, $lc_chunk;
            }
            elsif ($lc_active_style ne '') {
                push @lc_tokens, $lc_active_style . $lc_chunk . "\e[0m";
            }
            else {
                push @lc_tokens, $lc_chunk;
            }
        }
    }

    return @lc_tokens;
}

# Remove ANSI escape sequences so width calculations can work with visible
# characters only.
sub strip_ansi {
    my $lc_text;

    ($lc_text) = @_;

    $lc_text =~ s/\e\[[0-9;]*m//g;

    return $lc_text;
}

# Return the visible character count used by the wrapper. This is currently a
# simple length calculation, kept separate so width logic has one place to
# change later if needed.
sub visible_length {
    my $lc_text;

    ($lc_text) = @_;

    return length($lc_text);
}

# Apply one of the program's named ANSI styles to a text fragment and append a
# reset sequence when styling was actually added.
sub stylize {
    my $lc_style;
    my $lc_text;
    my %lc_styles;
    my $lc_prefix;
    my $lc_suffix;

    ($lc_style, $lc_text) = @_;

    %lc_styles = (
        h1          => "\e[1;36m",
        h1rule      => "\e[1;36m",
        h2          => "\e[1;36m",
        h2rule      => "\e[2;36m",
        h3plus      => "\e[1;33m",
        strong      => "\e[1m",
        em          => "\e[3m",
        code_inline => "\e[1;36m",
        codeblock   => "\e[1;38;5;245m",
        code_fence  => "\e[1;32m",
        quote       => "\e[38;5;252m",
        quote_bar   => "\e[38;5;244m",
        link_text   => "\e[4;34m",
        link_url    => "\e[2;34m",
        dim         => "\e[2m",
    );

    $lc_prefix = $lc_styles{$lc_style} // '';
    $lc_suffix = $lc_prefix ne '' ? "\e[0m" : '';

    return $lc_prefix . $lc_text . $lc_suffix;
}

exit main();
