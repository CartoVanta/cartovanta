#!/usr/bin/env perl
# cartovanta - Main command line tool for the CartoVanta card system
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

my @arguma; # Environments to pass to the subcommand
my $subcm; # Subcommand to search for
my $subcn; # Name of subcommand
my $counto; # Used for argument counting:

my $pathvar; # The path along wich to search for subcommands:
my @pathpart; # $pathvar after being chopped by colon
my $patheach; # Each element of path
my $possib; # Each possible location of subcommand

# Process the command line:
@arguma = @ARGV;
$counto = @arguma;
if ( $counto < 0.5 )
{
  die("\nFATAL ERROR:\n  Usage: cartovanta [subcommand] ([arguments])\n\n");
}
$subcn = shift(@arguma);
$subcm = $subcn . '-exe';

# Put together the value for $pathvar
$pathvar = $ENV{'CARTOVANTA_PATH'};
if ( $pathvar ne '' ) { $pathvar .= ':'; }
$pathvar .= $ENV{'HOME'} . '/local/cartovanta-bin';
$pathvar .= ':/usr/local/cartovanta-bin';

@pathpart = split(quotemeta(':'),$pathvar);
foreach $patheach (@pathpart)
{
  $possib = $patheach . '/' . $subcm;
  if ( -f $possib )
  {
    if ( -x $possib )
    {
      exec($possib,@arguma);
      die("\nchobakwrap: Execution failed for `" . $subcn . "`:\n" .
        "  Please inspect the following executable:\n" .
        "    " . $possib . "\n" .
        "  Permissions or an ACL entry may be preventing the file from executing.\n" .
      "\n");
    }
  }
}

die("\nFATAL ERROR:\n No such -cartovanta- subcommand: " . $subcn . " :\n\n");


