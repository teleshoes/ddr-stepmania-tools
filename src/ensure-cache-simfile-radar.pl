#!/usr/bin/perl
use strict;
use warnings;

use threads;
use threads::shared;

use File::Glob qw(:bsd_glob :globally :nocase);
use IPC::Run;
use Time::HiRes qw(time);

sub ensureSimfilesCached($@);
sub handleSimfile($$$);
sub splitIntoBuckets($@);

my $DEFAULT_MAX_THREADS = 16;

my $USAGE = "Usage:
  $0 -h | --help
    show this message

  $0 [OPTS] SONG_PACK_DIR [SONG_PACK_DIR SONG_PACK_DIR..]
    -for each SONG_PACK_DIR, find simfiles at SONG_PACK_DIR/*/*
       simfiles must end in .sm or .ssc (case insensitive)
    -group simfiles into roughly even groups, and run concurrently with threads
      (use a max of $DEFAULT_MAX_THREADS, see --threads)
    -for each SIMFILE
      run: simfile-radar SIMFILE

  OPTS
    --threads=THREAD_COUNT
      use at most THREAD_COUNT worker threads instead of $DEFAULT_MAX_THREADS
      cannot be zero
";

sub main(@){
  my $opts = {
    maxThreads       => $DEFAULT_MAX_THREADS,
  };
  my @songPackDirs;
  while(@_ > 0){
    my $arg = shift @_;
    if($arg =~ /^(-h|--help)$/){
      print $USAGE;
      exit 0;
    }elsif($arg =~ /^--threads=(\d+)$/){
      $$opts{maxThreads} = $1;
    }elsif(-d $arg){
      push @songPackDirs, $arg;
    }else{
      die "$USAGE\nERROR: unknown arg $arg\n";
    }
  }

  die "ERROR: THREAD_COUNT cannot be 0\n" if $$opts{maxThreads} == 0;

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

  my @simfileBuckets = splitIntoBuckets($$opts{maxThreads}, @simfiles);

  my $stateBySimfile = {};
  for my $simfile(@simfiles){
    my %simfileState;
    share(%simfileState);
    $simfileState{stdout} = "";
    $simfileState{stderr} = "";
    $simfileState{status} = "pending";
    $$stateBySimfile{$simfile} = \%simfileState;
  }

  my $total = 0+@simfiles;

  my $isAbort;
  share($isAbort);
  $isAbort = 0;

  my $count;
  share($count);
  $count = 0;

  $SIG{'INT'} = sub {
    print STDERR "\n\ncaught SIGINT, exiting each thread after current file\n\n";
    $isAbort = 1;
  };

  my $progressChunk = int($total / 50);
  $progressChunk = 1 if $progressChunk < 1;

  my $start = time;

  my @threads;
  for my $bucket(@simfileBuckets){
    push @threads, threads->create(sub {
      my $threadNum = threads->tid();
      print STDERR "\n     thread#$threadNum: STARTED\n";
      $SIG{'INT'} = sub {
        print STDERR "\n\ncaught SIGINT, exiting each thread after current file\n\n";
        $isAbort = 1;
      };

      for my $simfile(@$bucket){
        handleSimfile($$stateBySimfile{$simfile}, $opts, $simfile);

        if($isAbort){
          print STDERR "\n    thread#$threadNum: ERROR (aborting)\n";
          return;
        }

        {
          lock($count);
          $count++;
          if($count % $progressChunk == 0){
            printf "\r%d / %d (%d%%)", $count, $total, int(100.0*$count/$total + 0.5);
          }
        }
      }

      print STDERR "\n    thread#$threadNum finished\n";
    });
  }

  for my $t(@threads){
    $t->join();
  }

  my $end = time;

  for my $simfile(sort keys %$stateBySimfile){
    my $state = $$stateBySimfile{$simfile};
    if($$state{status} eq "success" and $$state{stderr} ne ""){
      print "\n===WARNINGS $simfile\n";
      print "status=$$state{status}\n";
      print "stderr=$$state{stderr}\n";
      print "stdout=$$state{stdout}\n";
      print "===\n";
    }
  }

  for my $simfile(sort keys %$stateBySimfile){
    my $state = $$stateBySimfile{$simfile};
    if($$state{status} ne "success"){
      print "\n===ERRORS $simfile\n";
      print "status=$$state{status}\n";
      print "stderr=$$state{stderr}\n";
      print "stdout=$$state{stdout}\n";
      print "===\n";
    }
  }

  print "\n";
  printf "success: %d\n", (0+grep{$$_{status} eq "success"} values %$stateBySimfile);
  printf "failure: %d\n", (0+grep{$$_{status} eq "failure"} values %$stateBySimfile);
  printf "pending: %d\n", (0+grep{$$_{status} eq "pending"} values %$stateBySimfile);
  printf "running: %d\n", (0+grep{$$_{status} eq "running"} values %$stateBySimfile);

  printf "ELAPSED: %.3fs\n", $end-$start;
}

sub handleSimfile($$$){
  my ($state, $opts, $simfile) = @_;
  $$state{status} = "running";

  my @cmd = ("simfile-radar", $simfile);

  my ($stdout, $stderr);
  my $h = IPC::Run::harness(\@cmd, ">", \$stdout, "2>", \$stderr);
  IPC::Run::run($h);

  $$state{stdout} = $stdout;
  $$state{stderr} = $stderr;

  if($h->result == 0){
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
