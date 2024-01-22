#!/usr/bin/perl
use strict;
use warnings;

my $SONG_DIR = "$ENV{HOME}/songs";

sub testMeasureVsDurationNPS();
sub readProc(@);

sub main(@){
  testSingleSimfile();
  testMeasureVsDurationNPS();
}

sub testSingleSimfile(){
  my @testSimArgs = (
    "$SONG_DIR/DDR_16_A/Life is beautiful/Life is beautiful.sm",
    "--expert", "--singles",
  );
  my @vars = qw(
        AVG_NPS_BY_1MEAS   AVG_NPS_BY_1S   AVG_NPS_BY_1S_PEAK
        MAX_NPS_BY_1MEAS   MAX_NPS_BY_1S   MAX_NPS_BY_1S_PEAK
        MAX_NPS_BY_4MEAS   MAX_NPS_BY_4S   MAX_NPS_BY_4S_PEAK
  );
  my @expectedVals = qw(
        4.973    4.968     7.187
        9.042   10.000    10.000
        8.719    8.750     9.000
  );
  my $fmt = join "###", map {"%$_"} @vars;
  my $out = readProc "simfile-radar", @testSimArgs, "--no-cache", "--format=$fmt";
  chomp $out;
  my @actualVals = split /###/, $out;
  if(@actualVals != @expectedVals){
    die "ERROR: unexpected output of simfile-radar\n$out\n";
  }
  for(my $i=0; $i<@actualVals; $i++){
    if($actualVals[$i] ne $expectedVals[$i]){
      die "ERROR: mismatched value $actualVals[$i] vs $expectedVals[$i]\n$out\n";
    }
  }
}

sub testMeasureVsDurationNPS(){
  my @tests;

  #test max nps for all songs with a BPM where
  #  1, 2, 3, or 4 measures is exactly 1, 2, 3, or 4 seconds
  for my $meas(qw(1 2 3 4)){
    for my $durS(qw(1 2 3 4)){
      my $bpm = 240*$durS/$meas;
      my $milliBPM = int($bpm*1000 + 0.5);
      if($milliBPM % 1000 == 0){
        push @tests, [$bpm, "BY_${meas}MEAS", "BY_${durS}S"];
      }
    }
  }

  for my $test(@tests){
    my ($targetBPM, $meas, $dur) = @$test;
    print "testing: $meas == $dur @ $targetBPM bpm\n";
  }

  my @smFiles = glob "$SONG_DIR/*/*/*.sm";
  for my $file(@smFiles){
    open FH, "< $file" or die "ERROR: could not read $file\n$!\n";
    my $out = join '', <FH>;
    close FH;
    my $bpm = $1 if $out =~ /\n#BPMS:((?:\n|[^;]*)*);/;
    next if not defined $bpm;
    $bpm =~ s/\n//g;
    $bpm =~ s/\s//g;
    my $stop = $1 if $out =~ /\n#STOPS:((?:\n|[^;]*)*);/;
    $stop = "" if not defined $stop;
    $stop =~ s/\n//g;
    $stop =~ s/\s//g;

    for my $test(@tests){
      my ($targetBPM, $meas, $dur) = @$test;
      if($bpm =~ /^(0|0+\.0+)=(180|180.0+)$/ and $stop eq ""){
        print "$file\n";
        my @lines = split /\n/, readProc "simfile-radar", $file, "--no-cache",
          "--format=%MAX_NPS_BY_3MEAS %MAX_NPS_BY_4S %SM_FILE";
        die "ERROR: $file failed\n" if @lines == 0;

        for my $line(@lines){
          my ($meas, $sex) = ($1, $2) if $line =~ /^(\d+|\d*\.\d+) (\d+|\d*\.\d+) /;
          if(sprintf("%.8f", $meas) ne sprintf("%.8f", $sex)){
            die "ERROR: bad line of output for $file\n$line\n";
          }else{
            print $line;
          }
        }
      }
    }
  }
}

sub readProc(@){
  my @cmd = @_;
  open my $fh, "-|", @cmd or die "ERROR: could not run @cmd\n";
  my $out = join '', <$fh>;
  close $fh;
  return $out;
}

&main(@ARGV);
