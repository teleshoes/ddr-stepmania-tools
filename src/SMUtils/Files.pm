package SMUtils::Files;
use strict;
use warnings;

use SMUtils::Utils;

sub getSMFileFromSongDir($$);
sub maybeGetSMFileFromSongDir($$);
sub getSongNameIdOverride($);
sub getFormattedConfigSongNameIdOverrides($$);
sub ensureSongNameIdOverrides();
sub ensureSimfileDirRenames();
sub ensureSimfileVersions();
sub parseSongNameIdOverridesFile($);
sub parseSimfileDirRenamesFile($);
sub parseSimfileVersionsFile($);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  getScoreXMLFiles
  getSMFileFromSongDir
  maybeGetSMFileFromSongDir
  getSongNameIdOverride
  getFormattedConfigSongNameIdOverrides
);

our $DIR_SONGS_PARENT = "$ENV{HOME}/.stepmania-5.0";

our $DIR_XML_CACHE_BASE = "$ENV{HOME}/.cache/stepmania-score-xml";
our $DIR_XML_CACHE_SCORES = "$DIR_XML_CACHE_BASE/scores";
our $DIR_XML_CACHE_STATS = "$DIR_XML_CACHE_BASE/stats";
our $DIR_XML_CACHE_UPLOAD = "$DIR_XML_CACHE_BASE/upload";

our $SONG_NAME_ID_OVERRIDES_FILE = "$ENV{HOME}/.config/ddrname-songlist-simfile-overrides";
our $SIMFILE_DIR_RENAMES_FILE = "$ENV{HOME}/.config/stepmania-simfile-dir-renames";
our $SIMFILE_VERSIONS_FILE = "$ENV{HOME}/.config/stepmania-simfile-versions";

#CONFIG loaded only once, and only as needed
#  song-name-id overrides to use instead of zenius
my $CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX = undef;

#CONFIG loaded only once, and only as needed
#  manual overrides of SONG_DIR, for songs that have been moved or renamed
my $CONFIG_SIMFILE_DIR_RENAMES = undef;

#CONFIG loaded only once, and only as needed
#  paths to alternate SM_FILEs within a song dir, for a specific date/time range
my $CONFIG_SIMFILE_VERSIONS_BY_SONG_DIR = undef;


sub getScoreXMLFiles(){
  my @xmlFiles = sort grep {$_ =~ /\.(xml)$/i} listDirFiles $DIR_XML_CACHE_SCORES;
  if(@xmlFiles == 0){
    die "ERROR: could not find scores $DIR_XML_CACHE_SCORES/*.xml\n";
  }
  return @xmlFiles;
}

sub getSMFileFromSongDir($$){
  my ($songDir, $epoch) = @_;
  my $result = maybeGetSMFileFromSongDir($songDir, $epoch);
  if(defined $$result{simfile}){
    return $$result{simfile};
  }else{
    my $errorMsg = "simfile not found for $songDir";
    $errorMsg = $$result{errorMsg} if defined $$result{errorMsg};
    die "ERROR: $errorMsg\n";
  }
}

sub maybeGetSMFileFromSongDir($$){
  my ($songDir, $epoch) = @_;
  my $result = {
    simfile               => undef,
    songAbsDir            => undef,
    isRenamedSongDir      => 0,
    isOlderVersionSimfile => 0,
    errorMsg              => undef,
  };

  ensureSimfileDirRenames();
  ensureSimfileVersions();

  if($songDir !~ /^Songs\/.*\/$/){
    $$result{errorMsg} = "song dir must start with 'Songs/' and end with '/' ($songDir)";
    return $result;
  }

  my $songAbsDir = "$DIR_SONGS_PARENT/$songDir";

  if(not -d $songAbsDir){
    if(defined $$CONFIG_SIMFILE_DIR_RENAMES{$songDir}){
      $$result{isRenamedSongDir} = 1;
      $songDir = $$CONFIG_SIMFILE_DIR_RENAMES{$songDir};
      $songAbsDir = "$DIR_SONGS_PARENT/$songDir";
      if(not -d "$songAbsDir"){
        $$result{errorMsg} = "renamed song dir '$songAbsDir' also does not exist";
        return $result;
      }
    }
  }

  if(-d $songAbsDir){
    $$result{songAbsDir} = $songAbsDir;
  }else{
    $$result{errorMsg} = "song dir '$songAbsDir' does not exist";
    return $result;
  }

  # use older version of simfile if version configured for date
  if(not defined $$result{simfile}){
    if(defined $$CONFIG_SIMFILE_VERSIONS_BY_SONG_DIR{$songDir}){
      my @versions = @{$$CONFIG_SIMFILE_VERSIONS_BY_SONG_DIR{$songDir}};
      for my $v(@versions){
        if($$v{startEpoch} <= $epoch && $epoch <= $$v{endEpoch}){
          $$result{isOlderVersionSimfile} = 1;
          $$result{simfile} = $$v{absSMFile};
          last;
        }
      }
    }
  }

  # find the first SM/SSC file directly underneath SONG_DIR
  if(not defined $$result{simfile}){
    my @smFiles = sort grep {$_ =~ /\.(ssc|sm)$/i} listDirFiles $songAbsDir;
    if(@smFiles > 0){
      $$result{simfile} = $smFiles[0];
    }
  }

  # fail if no simfile found
  if(not defined $$result{simfile}){
    $$result{errorMsg} = "could not find SSC or SM file in $songAbsDir";
    return $result;
  }

  return $result;
}

sub getSongNameIdOverride($){
  my ($songDir) = @_;
  ensureSongNameIdOverrides();
  for my $songDirSuffix(sort keys %$CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX){
    if($songDir =~ /(^|\/)\Q$songDirSuffix\E\/*$/){
      return $$CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX{$songDirSuffix};
    }
  }
  return undef;
}

sub getFormattedConfigSongNameIdOverrides($$){
  my ($prefix, $suffix) = @_;
  ensureSongNameIdOverrides();
  my @songNameIds = values %$CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX;
  my %uniqSongNameIds = map {$_ => 1} @songNameIds;

  my $maxLen = 100 - (length $prefix) - (length $suffix);

  my @lines;
  my $curLine = "";
  my $curLen = 0;
  for my $songNameId(sort keys %uniqSongNameIds){
    my $newLen = $curLen + length $songNameId;
    $newLen += 1 if $curLen > 0;
    if($curLen > 0 and $newLen > $maxLen){
      push @lines, $curLine;
      $curLine = "";
      $curLen = 0;
    }
    $curLine .= " " if $curLen > 0;
    $curLine .= $songNameId;
    $curLen = length $curLine;
  }
  push @lines, $curLine if length $curLen > 0;

  return join "", map {"$prefix$_$suffix"} @lines;
}

sub ensureSongNameIdOverrides(){
  if(not defined $CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX){
    $CONFIG_SONG_NAME_IDS_BY_SONG_DIR_SUFFIX =
      parseSongNameIdOverridesFile($SONG_NAME_ID_OVERRIDES_FILE);
  }
}
sub ensureSimfileDirRenames(){
  if(not defined $CONFIG_SIMFILE_DIR_RENAMES){
    $CONFIG_SIMFILE_DIR_RENAMES = parseSimfileDirRenamesFile($SIMFILE_DIR_RENAMES_FILE);
  }
}
sub ensureSimfileVersions(){
  if(not defined $CONFIG_SIMFILE_VERSIONS_BY_SONG_DIR){
    $CONFIG_SIMFILE_VERSIONS_BY_SONG_DIR = parseSimfileVersionsFile($SIMFILE_VERSIONS_FILE);
  }
}

sub parseSongNameIdOverridesFile($){
  my ($file) = @_;
  my @lines;
  if(-f $file){
    @lines = readFile($file);
  }
  my $songNameIdsBySongDirSuffix = {};
  for my $line(@lines){
    next if $line =~ /^\s*$/ or $line =~ /^\s*#/;
    if($line =~ /^([a-zA-Z0-9\-]+)\s*\|\s*(.+)$/){
      my ($songNameId, $songDirSuffix) = ($1, $2);
      $$songNameIdsBySongDirSuffix{$songDirSuffix} = $songNameId;
    }else{
      die "ERROR: malformed line in song name ID overrides\n$line";
    }
  }
  return $songNameIdsBySongDirSuffix;
}

sub parseSimfileDirRenamesFile($){
  my ($file) = @_;
  my @lines;
  if(-f $file){
    @lines = readFile($file);
  }

  my $simfileDirRenames = {};
  for my $line(@lines){
    next if $line =~ /^\s*$/ or $line =~ /^\s*#/;
    if($line =~ /^\s*(Songs\/[^:]*\/)\s*:\s*(Songs\/[^:]*\/)\s*$/){
      my ($orig, $repl) = ($1, $2);
      $$simfileDirRenames{$orig} = $repl;
    }else{
      die "ERROR: malformed song dir rename line $line\n";
    }
  }
  return $simfileDirRenames;
}

sub parseSimfileVersionsFile($){
  my ($file) = @_;
  my @lines;
  if(-f $file){
    @lines = readFile($file);
  }

  my $simfileVersionsBySongDir = {};
  for my $line(@lines){
    chomp $line;
    next if $line =~ /^\s*$/ or $line =~ /^\s*#/;
    if($line =~ /^\s*(\d+)\s*:\s*(\d+)\s*:\s*(Songs\/[^:]*\/)\s*:\s*([^:]+)$/){
      my ($startEpoch, $endEpoch, $songDir, $relSMFile) = ($1, $2, $3, $4);

      my $absDir = "$SMUtils::Files::DIR_SONGS_PARENT/$songDir";
      $absDir =~ s/\/$//;
      my $absSMFile = "$absDir/$relSMFile";
      if(not -f $absSMFile){
        die "ERROR: could not find SM_FILE version $absSMFile\n";
      }

      if(not defined $$simfileVersionsBySongDir{$songDir}){
        $$simfileVersionsBySongDir{$songDir} = [];
      }
      push @{$$simfileVersionsBySongDir{$songDir}}, {
        startEpoch => $startEpoch,
        endEpoch   => $endEpoch,
        songDir    => $songDir,
        absSMFile  => $absSMFile,
      };
    }else{
      die "ERROR: malformed versions line in $file\n$line\n";
    }
  }
  return $simfileVersionsBySongDir;
}

1;
