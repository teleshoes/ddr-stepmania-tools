#!/usr/bin/perl
use strict;
use warnings;

use threads;
use threads::shared;

use File::Glob qw(:bsd_glob :globally :nocase);

sub ensureSimfilesCached($@);
sub handleSimfile($$$);
sub splitIntoBuckets($@);

my $MAX_THREADS = 16;
my $USAGE = "Usage:
  $0 -h | --help
    show this message

  $0 [OPTS] SONG_PACK_DIR [SONG_PACK_DIR SONG_PACK_DIR..]
    -for each SONG_PACK_DIR, find simfiles at SONG_PACK_DIR/*/*
       simfiles must end in .sm or .ssc (case insensitive)
    -group simfiles into roughly even groups, and run concurrently with threads
      (use a max of $MAX_THREADS threads)
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
    my @songPackSimfiles = grep {-f $_} glob "$songPackDir/*/*.{SM,SSC}";
    if(@songPackSimfiles == 0){
      print STDERR "WARNING: no simfiles found at $songPackDir/*/*\n";
    }
    @simfiles = (@simfiles, @songPackSimfiles);
  }

  ensureSimfilesCached($opts, @simfiles);
}

sub ensureSimfilesCached($@){
  my ($opts, @simfiles) = @_;

  my @simfileBuckets = splitIntoBuckets($MAX_THREADS, @simfiles);

  my $stateBySimfile = {};
  for my $simfile(@simfiles){
    my %simfileState;
    share(%simfileState);
    $simfileState{status} = "pending";
    $$stateBySimfile{$simfile} = \%simfileState;
  }

  my $start = time;

  my @threads;
  for my $bucket(@simfileBuckets){
    push @threads, threads->create(sub {
      my $threadNum = threads->tid();
      print STDERR "\n     thread#$threadNum: STARTED\n";
      for my $simfile(@$bucket){
        handleSimfile($$stateBySimfile{$simfile}, $opts, $simfile);
      }
      print STDERR "\n    thread#$threadNum finished\n";
    });
  }

  for my $t(@threads){
    $t->join();
  }

  my $end = time;

  print "\n";
  printf "success: %d\n", (0+grep{$$_{status} eq "success"} values %$stateBySimfile);
  printf "failure: %d\n", (0+grep{$$_{status} eq "failure"} values %$stateBySimfile);
  printf "pending: %d\n", (0+grep{$$_{status} eq "pending"} values %$stateBySimfile);
  printf "running: %d\n", (0+grep{$$_{status} eq "running"} values %$stateBySimfile);

  print "ELAPSED: " . ($end-$start) . "s\n";
}

sub handleSimfile($$$){
  my ($state, $opts, $simfile) = @_;
  $$state{status} = "running";

  system "simfile-radar", $simfile;
  if($? == 0){
    $$state{status} = "success";
  }else{
    $$state{status} = "failure";
  }
}

# split list into a fixed number of sublists of similar size
#   -at most MAX_BUCKETS sublists are returned
#   -the size of each sublist differs by at most one element
#      -size is either: ceil(ITEM_COUNT / MAX_BUCKETS) or floor(ITEM_COUNT / MAX_BUCKETS)
#   -each sublist contains at least one element
# e.g.: 3, (a b c d e)  => [(a d), (b e), (c)]
sub splitIntoBuckets($@){
  my ($maxBucketCount, @items) = @_;
  my @buckets;
  for(my $i=0; $i<@items; $i++){
    push @{$buckets[$i % $maxBucketCount]}, $items[$i];
  }
  return @buckets;
}

&main(@ARGV);
