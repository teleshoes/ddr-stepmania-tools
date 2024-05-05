package SMUtils::Utils;
use strict;
use warnings;

use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Digest::MD5;
use Time::Local qw(timelocal_posix);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  epochToYMDOrZero epochToYMD dtmStrToEpoch
  md5sum mtime touch
);

sub epochToYMDOrZero($);
sub epochToYMD($);
sub dtmStrToEpoch($);
sub md5sum($);
sub mtime($);
sub touch($$);

sub epochToYMDOrZero($){
  my ($epoch) = @_;
  return defined $epoch ? epochToYMD($epoch) : "0000-00-00";
}

sub epochToYMD($){
  my ($epoch) = @_;
  die "ERROR: missing epoch\n" if not defined $epoch;
  return time2str("%Y-%m-%d", $epoch);
}

sub dtmStrToEpoch($){
  my ($dtm) = @_;

  my $epoch;
  if($dtm =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/){
    #faster (elapsed time is ~60.0%) conversion for stepmania <DateTime> vars
    $epoch = timelocal_posix($6, $5, $4, $3, $2-1, $1-1900);
  }else{
    $epoch = str2time($dtm);
  }

  if(not defined $epoch or $epoch !~ /^-?\d+$/){
    die "ERROR: failed to convert $dtm to epoch\n";
  }

  return $epoch;
}

sub md5sum($){
  my ($file) = @_;
  open my $fh, "< $file" or die "ERROR: could not read $file\n$!\n";
  my $md5sum = Digest::MD5->new->addfile($fh)->hexdigest;
  close $fh;
  die "ERROR: could not get md5sum of $file\n" if $md5sum !~ /^[0-9a-f]{32}$/;
  return $md5sum;
}

sub mtime($){
  my ($file) = @_;
  my @stat = stat $file;
  return $stat[9];
}

sub touch($$){
  my ($file, $epoch) = @_;
  utime($epoch, $epoch, $file);
}

1;
