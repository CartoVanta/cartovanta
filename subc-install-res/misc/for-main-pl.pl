#!/usr/bin/env perl
# This 'cartovanta' submodule wrapping script is licensed under
# the GNU Lesser General Public License, version 3.0 or later; see
# https://github.com/CartoVanta/cartovanta/blob/main/subc-install-res/misc/lgpl-3.0.md
#
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $resdir;

$resdir = dirname(abs_path($0)) or die "\nFATAL ERROR finding 'cartovanta' resource directory.\n\n";
$resdir .= '/__THE_MODULE_NAME__-res';
exec(($resdir . '/core-plain.pl'),@ARGV);

