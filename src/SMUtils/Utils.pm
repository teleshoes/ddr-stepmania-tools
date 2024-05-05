package SMUtils::Utils;
use strict;
use warnings;

use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Time::Local qw(timelocal_posix);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  epochToYMDOrZero epochToYMD dtmStrToEpoch
);

sub epochToYMDOrZero($);
sub epochToYMD($);
sub dtmStrToEpoch($);

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

1;
