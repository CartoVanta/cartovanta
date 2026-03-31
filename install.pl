#!/usr/bin/env perl
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
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Getopt::Long qw(GetOptions);

my $starting_dir; # Directory from which the install is invoked
my %opt = (); # Home of the Command-Line Options

GetOptions(
  'fakeroot=s'   => \$opt{'fakeroot'},
  'bindir=s'   => \$opt{'bindir'},
  'cartovanta-bindir=s' => \$opt{'cartovanta_bindir'},
  'systemwide'  => \$opt{'systemwide'},
  'help'        => \$opt{'help'},
) or die "Bad command-line option.\n";

if ( $opt{'systemwide'} )
{  if ( $> != 0 )
  {
    die "Systemwide installation requires root privileges.\n";
  }
}

# Journey to the install script's own directory:
{
  my $lc_sldir;
  
  # Find where we came from
  $starting_dir = abs_path('.') or die "You did not invoke this install script from a valid place.\n";
  
  # Find where we should go
  $lc_sldir = dirname( abs_path($0) )
    or die "Could not determine script directory for $0\n";
  
  # Go there.
  chdir $lc_sldir
    or die "Could not chdir to $lc_sldir: $!\n";
}



my @pathset; # All locations on the PATH
my $bindest; # Install destination for -cartovanta-
my $cartov_bin; # Install destination for -cartovanta- subcommands

# Find @pathset
{
  my $lc_a;
  $lc_a = $ENV{'PATH'};
  @pathset = split(quotemeta(':'),$lc_a);
}

# Find $cartov_bin
$cartov_bin = &find_cartovbin();
sub find_cartovbin {
  my $lc_hme;
  
  if ( $opt{'fakeroot'} )
  {
    my $lc2_ds;
    $lc2_ds = $opt{'fakeroot'};
    if ( $opt{'cartovanta_bindir'} )
    {
      $lc2_ds .= $opt{'cartovanta_bindir'};
    } else {
      $lc2_ds .= '/usr/local/cartovanta-bin';
    }
    return $lc2_ds;
  }
  if ( $opt{'cartovanta_bindir'} ) { return($opt{'cartovanta_bindir'}); }
  
  if ( $opt{'systemwide'} ) { return('/usr/local/bin'); }
  
  $lc_hme = $ENV{'HOME'};
  if ( $lc_hme eq '' )
  {
    $lc_hme = `(cd && pwd)`; chomp($lc_hme);
  }
  return($lc_hme . '/local/cartovanta-bin');
}

# Find $bindest
$bindest = &findbin();
sub findbin {
  my $lc_hme;
  my $lc_pos;
  
  if ( $opt{'fakeroot'} )
  {
    my $lc2_ds;
    $lc2_ds = $opt{'fakeroot'};
    if ( $opt{'bindir'} )
    {
      $lc2_ds .= $opt{'bindir'};
    } else {
      $lc2_ds .= '/usr/local/bin';
    }
    return $lc2_ds;
  }
  if ( $opt{'bindir'} ) { return($opt{'bindir'}); }
  
  if ( $opt{'systemwide'} ) { return('/usr/local/bin'); }
  
  $lc_hme = $ENV{'HOME'};
  if ( $lc_hme eq '' )
  {
    $lc_hme = `(cd && pwd)`; chomp($lc_hme);
  }
  $lc_pos = $lc_hme . '/local/bin';
  if ( &found_in_path($lc_pos) ) { return $lc_pos; }
  $lc_pos = $lc_hme . '/bin';
  if ( &found_in_path($lc_pos) ) { return $lc_pos; }
  die(
    "\nFATAL ERROR:\n  Could not find where to install -cartovanta-\n" .
    "  Please make sure one of the following two is\n" .
    "        on the \$PATH environment variable:\n" .
    "    " . $lc_hme . "/local/bin\n" .
    "    " . $lc_hme . "/bin\n" .
  "\n");
}

if ( $opt{'help'} )
{
  exec('perl','mdview-res/core-plain.pl','install-helpfile.md');
  die("\nProblem invoking helpfile.\n\n");
}

# And when I try ot find $bindest, I will need to check if
# a given possibility is on the PATH
sub found_in_path {
  my $lc_a;
  foreach $lc_a (@pathset)
  {
    if ( $lc_a eq $_[0] ) { return(2>1); }
  }
  return(1>2);
}

# Go ahead and install the thing
{
  my $lc_ds; # Destination of main command
  my $lc_eds; # Destination of helpfile displayer
  my $lc_cm;
  
  $lc_ds = ($bindest . '/cartovanta');
  $lc_eds = $lc_ds . '-help';
  
  system('mkdir','-p',$bindest);
  system('rm','-rf',$lc_ds,$lc_eds); # Remove old stuff
  
  # Make sure there is nothing so weird as directories where
  # the executables need to go.
  if ( -d $lc_ds )
  {
    die("\nFATAL ERROR:\n  Why is a directory present at this location?\n  " . $lc_ds . "\n\n");
  }
  if ( -d $lc_eds )
  {
    die("\nFATAL ERROR:\n  Why is a directory present at this location?\n  " . $lc_eds . "\n\n");
  }
  
  # NOW FOR THE INSTALLATIONS
  # First the main cartovanta
  $lc_cm = 'cat cartovanta.pl > ' . &shell_quote($lc_ds);
  system($lc_cm);
  system('chmod','755',$lc_ds);
  
  # And then the help displayer
  $lc_cm = "echo '" . '#!/usr/bin/env cartovanta mdview --shebang' . "' > ";
  $lc_cm .= &shell_quote($lc_eds);
  system($lc_cm);
  $lc_cm = 'cat cartovanta-help.md >> ' . &shell_quote($lc_eds);
  system($lc_cm);
  system('chmod','755',$lc_eds);
}


sub shell_quote {
  my $lc_strg;
  ($lc_strg) = @_;
  return "''" if !defined($lc_strg) || $lc_strg eq '';
  $lc_strg =~ s/'/'"'"'/g;
  return "'$lc_strg'";
}

sub install_each {
  my $lc_ech;
  foreach $lc_ech (@_)
  {
    system('perl','subc-install-res/core-plain.pl',$lc_ech,$cartov_bin);
  }
}
&install_each('mdview');
&install_each('subc-install');
&install_each('textdeck');
&install_each('txtdeck');
&install_each('cp-w-border');





