#!/usr/bin/env perl
# cartovanta cp-w-border - Creates a copy of an image with a solid-color border added on
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

my $borderpx; # The width of the border to add (in pixels)
my $rgbcolor; # Color of the border to add (in RRGGBB)
my $before; # The "before" image
my $after; # The "after" image (which will be created)

# Get the command-line arguments.
($borderpx,$rgbcolor,$before,$after) = @ARGV;

# Run the command.
# SAMPLE: magick export.png -bordercolor '#ffff00' -border 80x80 zik.png
system('magick',$before,'-bordercolor',('#'.$rgbcolor),'-border',($borderpx.'x'.$borderpx),$after);

