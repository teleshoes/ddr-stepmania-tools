package SMUtils::Utils;
use strict;
use warnings;

use open qw( :std :encoding(UTF-8) );
use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Encode;
use Digest::MD5;
use Time::Local qw(timelocal_posix);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  dateFmt dateFmtYMDHMS epochToYMDOrZero epochToYMD dtmStrToEpoch
  assertPresent assertDateTimeFmt assertMd5sumMatches
  readFile writeFile appendFile readProc listDirFiles md5sum mtime touch
  wantarrayToContext
);

sub dateFmt($$);
sub dateFmtYMDHMS($);
sub epochToYMDOrZero($);
sub epochToYMD($);
sub dtmStrToEpoch($);
sub assertPresent($@);
sub assertDateTimeFmt($$);
sub assertMd5sumMatches($$);
sub readFile($);
sub writeFile($$);
sub appendFile($$);
sub readProc(@);
sub maybeDecodeFile($$);
sub listDirFiles($);
sub md5sum($);
sub mtime($);
sub touch($$);
sub wantarrayToContext($);

my $WANTARRAY_CONTEXT_VOID = "void";
my $WANTARRAY_CONTEXT_LIST = "list";
my $WANTARRAY_CONTEXT_SCALAR = "scalar";

sub dateFmt($$){
  my ($fmtSpec, $epoch) = @_;
  die "ERROR: missing epoch\n" if not defined $epoch;
  die "ERROR: invalid epoch $epoch\n" if $epoch !~ /^-?\d+$/;
  return time2str($fmtSpec, $epoch);
}

sub dateFmtYMDHMS($){
  my ($epoch) = @_;
  return dateFmt("%Y-%m-%d_%H:%M:%S", $epoch);
}

sub epochToYMDOrZero($){
  my ($epoch) = @_;
  return defined $epoch ? epochToYMD($epoch) : "0000-00-00";
}

sub epochToYMD($){
  my ($epoch) = @_;
  return dateFmt("%Y-%m-%d", $epoch);
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

sub assertPresent($@){
  my ($msg, @elems) = @_;
  for my $elem(@elems){
    die $msg if not defined $elem or $elem eq "";
  }
}

sub assertDateTimeFmt($$){
  my ($msg, $dtm) = @_;
  if($dtm !~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/){
    die $msg;
  }
}

sub assertMd5sumMatches($$){
  my ($f1, $f2) = @_;
  my $csum1 = md5sum $f1;
  my $csum2 = md5sum $f2;
  if(not defined $csum1 or not defined $csum2 or $csum1 ne $csum2){
    die "ERROR: checksum mismatch '$f1' vs '$f2'\n";
  }
}

sub readFile($){
  my ($file) = @_;
  open my $fh, "< $file" or die "ERROR: could not read $file\n$!\n";
  my @lines = <$fh>;
  close $fh;

  my $wantarrayContext = wantarrayToContext(wantarray);
  if($wantarrayContext eq $WANTARRAY_CONTEXT_SCALAR){
    return join '', @lines;
  }elsif($wantarrayContext eq $WANTARRAY_CONTEXT_LIST){
    return @lines;
  }elsif($wantarrayContext eq $WANTARRAY_CONTEXT_VOID){
    return;
  }
}

sub writeFile($$){
  my ($file, $contents) = @_;
  open FH, "> $file" or die "ERROR: could not write $file\n$!\n";
  print FH $contents;
  close FH;
}

sub appendFile($$){
  my ($file, $contents) = @_;
  open FH, ">> $file" or die "ERROR: could not append $file\n$!\n";
  print FH $contents;
  close FH;
}

sub readProc(@){
  open CMD, "-|", @_ or die "ERROR: could not run \"@_\"\n$!\n";
  my @lines = <CMD>;
  close CMD;

  my $wantarrayContext = wantarrayToContext(wantarray);
  if($wantarrayContext eq $WANTARRAY_CONTEXT_SCALAR){
    return join '', @lines;
  }elsif($wantarrayContext eq $WANTARRAY_CONTEXT_LIST){
    return @lines;
  }elsif($wantarrayContext eq $WANTARRAY_CONTEXT_VOID){
    return;
  }
}

sub maybeDecodeFile($$){
  my ($dir, $file) = @_;
  if(not -e "$dir/$file"){
    my $decodedFile = eval { Encode::decode("utf8", $_); };
    if(defined $decodedFile and length $decodedFile > 0 and -e "$dir/$decodedFile"){
      return $decodedFile;
    }
  }
  return $file;
}

sub listDirFiles($){
  my ($dir) = @_;
  opendir(my $dh, $dir) or die "ERROR: could not read dir $dir\n$!\n";
  my @files = readdir($dh);
  closedir($dh);
  @files = map {maybeDecodeFile($dir, $_)} @files;
  $dir =~ s/\/?$//;
  @files = map {"$dir/$_"} @files;
  @files = grep {-f $_} @files;
  return @files;
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

sub wantarrayToContext($){
  my ($wantarrayValue) = @_;
  if(not defined $wantarrayValue){
    return $WANTARRAY_CONTEXT_VOID;
  }elsif($wantarrayValue){
    return $WANTARRAY_CONTEXT_LIST;
  }else{
    return $WANTARRAY_CONTEXT_SCALAR;
  }
}

1;
