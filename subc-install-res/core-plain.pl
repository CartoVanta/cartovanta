#!/usr/bin/env perl
# cartovanta subc-install -- Installs cartovanta subcommands
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

my $resdir;
my $destdir;
my $modnom;
my $trysource; # Each main-script source being tried:
my $destexe;

# FIRST OF ALL: Find this command's resource directory.
if ( $resdir = dirname(abs_path($0)) ) { } else {
  die("\nFATAL ERROR: cartovanta subc-install :\n"
    . "  Could not resolve its own resource directory.\n\n"
  );
}
($modnom,$destdir) = @ARGV;
$destexe = $destdir . '/' . $modnom . '-exe';

system('mkdir','-p',$destdir);

sub shlq {
  my $lc_strg;
  ($lc_strg) = @_;
  return "''" if !defined($lc_strg) || $lc_strg eq '';
  $lc_strg =~ s/'/'"'"'/g;
  return "'$lc_strg'";
}

sub install_the_res {
  my $lc_tmp;
  my $lc_ressrc;
  my $lc_final;
  
  $lc_tmp = $destdir . '/tmp';
  $lc_ressrc = $modnom . '-res';
  $lc_final = $destdir . '/' . $lc_ressrc;
  
  system('rm','-rf',$lc_tmp);
  if ( -d $lc_tmp ) { die "\nFailed to clear:\n  $lc_tmp :\n\n"; }
  if ( -f $lc_tmp ) { die "\nThere's a file at:\n  $lc_tmp :\n\n"; }
  system('mkdir',$lc_tmp);
  if ( !( -d $lc_tmp ) ) { die "\nCould not create:\n  $lc_tmp :\n\n"; }
  
  if ( system('cp','-r',$lc_ressrc,($lc_tmp . '/.')) != 0 )
  {
    die "\nFailed to copy resource directory: $lc_ressrc :\n\n";
  }
  
  system('rm','-rf',$lc_final);
  if ( -d $lc_final ) { die "\nFailed to clear:\n  $lc_final :\n\n"; }
  if ( -f $lc_final ) { die "\nThere's a file at:\n  $lc_final :\n\n"; }
  system('mv',($lc_tmp . '/' . $lc_ressrc),($destdir . '/.'));
  
  system('rm','-rf',$lc_tmp);
  if ( -d $lc_tmp ) { die "\nFailed to clear:\n  $lc_tmp :\n\n"; }
  if ( -f $lc_tmp ) { die "\nThere's a file at:\n  $lc_tmp :\n\n"; }
}


sub open_the_tak {
  my $lc_cm;
  system('rm','-rf',$destexe);
  $lc_cm = "| cat > " . &shlq($destexe);
  open TAK, $lc_cm;
  print TAK "#!/usr/bin/env perl\n";
}

sub shut_the_tak {
  close TAK;
  system('chmod','755',$destexe);
}

$trysource = $modnom . '-res/core-plain.pl';
if ( -f $trysource )
{
  &open_the_tak();
  print TAK 'use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $resdir;

$resdir = dirname(abs_path($0)) or die "\nFATAL ERROR finding \'cartovanta\' resource directory.\n\n";
$resdir .= \'/';
  print TAK $modnom;
  print TAK '-res\';
exec(\'perl\',($resdir . \'/core-plain.pl\'),@ARGV);

';
  &shut_the_tak();
  &install_the_res();
  exit(0);
}

$trysource = $modnom . '-res/core-plain.swift';
if ( -f $trysource )
{
  &open_the_tak();
  print TAK 'use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $resdir;

$resdir = dirname(abs_path($0)) or die "\nFATAL ERROR finding \'cartovanta\' resource directory.\n\n";
$resdir .= \'/';
  print TAK $modnom;
  print TAK '-res\';
exec(\'swift\',($resdir . \'/core-plain.swift\'),@ARGV);

';
  &shut_the_tak();
  &install_the_res();
  exit(0);
}

die("\nCould not install 'cartovanta' subcommand: " . $modnom .
 " :\nNo script source found.\n\n"
);



