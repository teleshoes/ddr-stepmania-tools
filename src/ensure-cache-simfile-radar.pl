#!/usr/bin/perl
use strict;
use warnings;

sub ensureSimfilesCached($@);
sub handleSimfile($$);

my $USAGE = "Usage:
  $0 -h | --help
    show this message

  $0 [OPTS] SONG_PACK_DIR [SONG_PACK_DIR SONG_PACK_DIR..]
    -for each SONG_PACK_DIR, find simfiles at SONG_PACK_DIR/*/*
       simfiles must end in .sm or .ssc (case insensitive)
    -for each SIMFILE
      run: simfile-radar SIMFILE

  OPTS
";

sub main(@){
  my $opts = {
  };
  my @songPackDirs;
  while(@_ > 0){
    my $arg = shift @_;
    if($arg =~ /^(-h|--help)$/){
      print $USAGE;
      exit 0;
    }elsif(-d $arg){
      push @songPackDirs, $arg;
    }else{
      die "$USAGE\nERROR: unknown arg $arg\n";
    }
  }

  die "$USAGE\nERROR: no SONG_PACK_DIRS found\n" if @songPackDirs == 0;

  my @simfiles;
  for my $songPackDir(@songPackDirs){
    my @songPackSimfiles = `find '$songPackDir' -iname *.sm -or -iname *.ssc`;
    chomp foreach @songPackSimfiles;
    if(@songPackSimfiles == 0){
      print STDERR "WARNING: no simfiles found at $songPackDir/*/*\n";
    }
    @simfiles = (@simfiles, @songPackSimfiles);
  }

  ensureSimfilesCached($opts, @simfiles);
}

sub ensureSimfilesCached($@){
  my ($opts, @simfiles) = @_;

  for my $simfile(@simfiles){
    handleSimfile($opts, $simfile);
  }
}

sub handleSimfile($$){
  my ($opts, $simfile) = @_;
  system "simfile-radar", $simfile;
}

&main(@ARGV);
