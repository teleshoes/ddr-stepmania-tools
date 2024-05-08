package SMUtils::ScoreXML;
use strict;
use warnings;

use SMUtils::Utils;
use XML::LibXML;

sub isEmptyUploadFile($);
sub extractCaloriesByDateFromStats($);
sub extractScoreEntriesFromStats($);
sub extractScoreEntriesFromUpload($);
sub extractScoreEntriesFromScore($);
sub reduceScoreEntries(@);
sub parseScoreDetails($);
sub calculateDancePoints($);
sub getScoreEntryID($);
sub getSingleNode($$);
sub getSingleChildByTagName($$);
sub convertStepsTypeToGame($);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
  isEmptyUploadFile
  extractCaloriesByDateFromStats
  extractScoreEntriesFromStats
  extractScoreEntriesFromUpload
  extractScoreEntriesFromScore
  reduceScoreEntries
  parseScoreDetails
  calculateDancePoints
  getScoreEntryID
  getSingleNode
  getSingleChildByTagName
  convertStepsTypeToGame
);

my @SCORE_DETAILS_ATT_ARR = (
  grade               => "Grade",
  percentDP           => "PercentDP",
  surviveSeconds      => "SurviveSeconds",
  maxCombo            => "MaxCombo",
  mods                => "Modifiers",
  countW1             => "TapNoteScores/W1",
  countW2             => "TapNoteScores/W2",
  countW3             => "TapNoteScores/W3",
  countW4             => "TapNoteScores/W4",
  countW5             => "TapNoteScores/W5",
  countMiss           => "TapNoteScores/Miss",
  countAvoidMine      => "TapNoteScores/AvoidMine",
  countHitMine        => "TapNoteScores/HitMine",
  countHeld           => "HoldNoteScores/Held",
  countLetGo          => "HoldNoteScores/LetGo",
  countMissedHold     => "HoldNoteScores/MissedHold",
  radarTapsAndHolds   => "RadarValues/TapsAndHolds",
  radarJumps          => "RadarValues/Jumps",
  radarHolds          => "RadarValues/Holds",
  radarMines          => "RadarValues/Mines",
  radarHands          => "RadarValues/Hands",
  radarRolls          => "RadarValues/Rolls",
  radarLifts          => "RadarValues/Lifts",
  radarFakes          => "RadarValues/Fakes",
);
my @SCORE_DETAILS_ATT_NAMES = map {$SCORE_DETAILS_ATT_ARR[$_]}
                              grep {$_%2==0} 0..$#SCORE_DETAILS_ATT_ARR;
my %SCORE_DETAILS_ATT_PATHS_BY_NAME = @SCORE_DETAILS_ATT_ARR;

sub isEmptyUploadFile($){
  my ($uploadFile) = @_;
  my $contents = readFile($uploadFile);
  if($contents =~ /
    ^
    <\?xml.*\?>                             [\r\n]*
                                            [\r\n]*
    <Stats>                                 [\r\n]*
    <MachineGuid> [0-9a-f]+ <\/MachineGuid> [\r\n]*
    <RecentSongScores\/>                    [\r\n]*
    <\/Stats>                               [\r\n]*
    $
  /x){
    return 1;
  }else{
    return 0;
  }
}

sub extractCaloriesByDateFromStats($){
  my ($statsFile) = @_;
  my $caloriesByDate = {};
  my $dom = XML::LibXML->load_xml(location => $statsFile);
  for my $cbNode($dom->findnodes("Stats/CalorieData/CaloriesBurned")){
    my $date = $cbNode->getAttribute("Date");
    my $cal = $cbNode->findvalue(".");
    if(defined $$caloriesByDate{$date}){
      die "ERROR: duplicate <CaloriesBurned> Date value $date in $statsFile\n";
    }
    $$caloriesByDate{$date} = $cal;
  }
  return $caloriesByDate;
}

sub extractScoreEntriesFromStats($){
  my ($statsFile) = @_;
  my @scoreEntries;

  my $dom = XML::LibXML->load_xml(location => $statsFile);

  my $machineGuid = $dom->findvalue("Stats/GeneralData/Guid");
  $machineGuid = "" if not $machineGuid;

  my $errorMsg = "ERROR: error in stats file $statsFile";

  for my $songNode($dom->findnodes("/Stats/SongScores/Song")){
    my $songDir = $songNode->getAttribute("Dir");
    assertPresent("$errorMsg - missing song dir", $songDir);
    for my $stepsNode($songNode->getChildrenByTagName("Steps")){
      my $smDiff = $stepsNode->getAttribute("Difficulty");
      my $stepsType = $stepsNode->getAttribute("StepsType");
      my @scoreNodes = $stepsNode->findnodes("HighScoreList/HighScore");

      assertPresent("$errorMsg [$songDir] - missing diff/game", $songDir, $smDiff);

      my $game = convertStepsTypeToGame($stepsType);
      for my $scoreNode(@scoreNodes){
        my $dateTimeXML = $scoreNode->findvalue("./DateTime");
        assertDateTimeFmt("$errorMsg [$songDir] invalid/missing DateTime", $dateTimeXML);
        my $epoch = dtmStrToEpoch($dateTimeXML);
        my $percentDP = $scoreNode->findvalue("./PercentDP");

        push @scoreEntries, {
          xmlFile       => $statsFile,
          xmlSchemaType => "stats",

          songDir       => $songDir,
          game          => $game,
          smDiff        => $smDiff,
          machineGuid   => $machineGuid,
          playerNum     => undef,
          epoch         => $epoch,
          percentDP     => $percentDP,

          songNode      => $songNode,
          stepsNode     => $stepsNode,
          scoreNode     => $scoreNode,
        };
      }
    }
  }

  if(@scoreEntries == 0){
    print STDERR "WARNING: no score entries found in stats file $statsFile\n";
  }

  return @scoreEntries;
}

sub extractScoreEntriesFromUpload($){
  my ($uploadFile) = @_;
  my @scoreEntries;

  my $dom = XML::LibXML->load_xml(location => $uploadFile);

  my $machineGuid = $dom->findvalue("Stats/MachineGuid");
  $machineGuid = "" if not $machineGuid;

  my $errorMsg = "ERROR: error in upload file $uploadFile";

  my @uploadFileContainerNodes = $dom->findnodes(
    "/Stats/RecentSongScores/HighScoreForASongAndSteps");
  for(my $i=0; $i<@uploadFileContainerNodes; $i++){
    my $containerNode = $uploadFileContainerNodes[$i];
    my $playerNum;
    if($i == 0 and @uploadFileContainerNodes == 1){
      $playerNum = 0; #only/center player
    }elsif($i == 0 and @uploadFileContainerNodes == 2){
      $playerNum = 1; #left player
    }elsif($i == 1 and @uploadFileContainerNodes == 2){
      $playerNum = 2; #right player
    }else{
      die "ERROR: more than two player scores in recent-scores file $uploadFile\n";
    }

    my $songNode = getSingleChildByTagName($containerNode, "Song");
    my $stepsNode = getSingleChildByTagName($containerNode, "Steps");
    my $scoreNode = getSingleChildByTagName($containerNode, "HighScore");
    assertPresent("$errorMsg - missing song/steps/score node", $songNode, $stepsNode, $scoreNode);

    my $songDir = $songNode->getAttribute("Dir");
    my $smDiff = $stepsNode->getAttribute("Difficulty");
    my $stepsType = $stepsNode->getAttribute("StepsType");
    my $dateTimeXML = $scoreNode->findvalue("./DateTime");
    my $percentDP = $scoreNode->findvalue("./PercentDP");

    assertPresent("$errorMsg - missing songDir/game/diff\n", $songDir, $smDiff, $stepsType);
    assertDateTimeFmt("$errorMsg - invalid/missing DateTime\n", $dateTimeXML);

    my $game = convertStepsTypeToGame($stepsType);
    my $epoch = dtmStrToEpoch($dateTimeXML);

    push @scoreEntries, {
      xmlFile       => $uploadFile,
      xmlSchemaType => "upload",

      songDir       => $songDir,
      game          => $game,
      smDiff        => $smDiff,
      machineGuid   => $machineGuid,
      playerNum     => $playerNum,
      percentDP     => $percentDP,
      epoch         => $epoch,

      songNode      => $songNode,
      stepsNode     => $stepsNode,
      scoreNode     => $scoreNode,
    };
  }

  if(@scoreEntries == 0 and not isEmptyUploadFile($uploadFile)){
    die "ERROR: no score entries found in non-empty upload-file $uploadFile\n";
  }

  return @scoreEntries;
}

#same syntax as upload file, except one per file max
sub extractScoreEntriesFromScore($){
  my ($scoreFile) = @_;

  my @scoreEntries = extractScoreEntriesFromUpload($scoreFile);
  if(@scoreEntries != 1){
    die "ERROR: score file must contain exactly one score '$scoreFile'\n";
  }
  for my $scoreEntry(@scoreEntries){
    $$scoreEntry{xmlSchemaType} = "score";
  }

  my $playerNumFromFilename;
  if($scoreFile =~ /_p([012])_/){
    $playerNumFromFilename = $1;
  }else{
    die "ERROR: could not parse PLAYER_NUM from $scoreFile\n";
  }

  for my $scoreEntry(@scoreEntries){
    $$scoreEntry{playerNum} = $playerNumFromFilename;
  }

  return @scoreEntries;
}

sub reduceScoreEntries(@){
  my @scoreEntries = @_;
  my $scoreEntriesByEpoch = {};
  for my $scoreEntry(@scoreEntries){
    my $epoch = $$scoreEntry{epoch};
    if(not defined $$scoreEntriesByEpoch{$epoch}){
      $$scoreEntriesByEpoch{$epoch} = [];
    }
    push @{$$scoreEntriesByEpoch{$epoch}}, $scoreEntry;
  }

  my @reducedScoreEntries;
  for my $epoch(sort keys %$scoreEntriesByEpoch){
    my @entries = @{$$scoreEntriesByEpoch{$epoch}};

    my @uniqScoreEntries;
    if(@entries == 1){
      #skip de-dupe/reduce for performance
      @uniqScoreEntries = @entries;
    }else{
      #calculate unique score IDs
      for my $entry(@entries){
        parseScoreDetails($entry); #parses XML
        $$entry{id} = getScoreEntryID($entry);
      }

      #split dupes into buckets
      my @scoreIDGroups;
      while(@entries > 0){
        my $id = ${$entries[0]}{id};
        my @group = grep {$$_{id} eq $id} @entries;
        @entries = grep {$$_{id} ne $id} @entries;
        push @scoreIDGroups, [@group];
      }

      #take the first score from each group as-is
      for my $group(@scoreIDGroups){
        my $entry = shift @$group;
        push @uniqScoreEntries, $entry;
      }
    }

    if(@uniqScoreEntries > 2){
      die "ERROR: more than two unique score entries for epoch=$epoch\n";
    }

    #ensure every score at this epoch is for the same song (different difficulty is fine)
    my $songDir = ${$uniqScoreEntries[0]}{songDir};
    for my $entry(@uniqScoreEntries){
      if($$entry{songDir} ne $songDir){
        die "ERROR: different simfiles for scores with the same epoch=$epoch\n";
      }
    }

    #assign player num
    for(my $i=0; $i<@uniqScoreEntries; $i++){
      my $entry = $uniqScoreEntries[$i];
      #p0 for only score, p1 for first score, p2 for second score
      my $playerNum = @uniqScoreEntries == 1 ? 0 : $i+1;
      if(defined $$entry{playerNum} and $$entry{playerNum} != $playerNum){
        die "ERROR: score epoch=$epoch is player#$$entry{playerNum}, expected p#$playerNum\n";
      }
      $$entry{playerNum} = $playerNum;
    }

    for my $entry(@uniqScoreEntries){
      push @reducedScoreEntries, $entry;
    }
  }

  return @reducedScoreEntries;
}

sub parseScoreDetails($){
  my ($scoreEntry) = @_;

  if(defined $$scoreEntry{scoreDetails}){
    return;
  }

  my $details = {};

  for my $attName(@SCORE_DETAILS_ATT_NAMES){
    my $attPath = $SCORE_DETAILS_ATT_PATHS_BY_NAME{$attName};
    my $val = $$scoreEntry{scoreNode}->findvalue($attPath);
    $val = "" if not defined $val;
    $$details{$attName} = $val;
  }

  #fill in <MissedHold>=0 if <LetGo> is present and <MissedHold> is not
  #  some old scores predate <MissedHold>, and were updated in stats but not upload
  if($$details{countMissedHold} eq ""){
    print STDERR "WARNING: <MissedHold> missing for score with epoch=$$scoreEntry{epoch}\n";
    if($$details{countLetGo} !~ /^\d+$/){
      die "ERROR: missing <LetGo> and <MissedHold> for score epoch=$$scoreEntry{epoch}\n";
    }
    $$details{countMissedHold} = 0;
  }

  $$scoreEntry{scoreDetails} = $details;
}

sub calculateDancePoints($){
  my ($scoreEntry) = @_;
  return 0
    + $$scoreEntry{scoreDetails}{countW1}      * 3
    + $$scoreEntry{scoreDetails}{countW2}      * 2
    + $$scoreEntry{scoreDetails}{countW3}      * 1
    + $$scoreEntry{scoreDetails}{countHeld}    * 3
    + $$scoreEntry{scoreDetails}{countHitMine} * -2
  ;
}

sub getScoreEntryID($){
  my ($scoreEntry) = @_;

  my $id = "";
  $id .= "$$scoreEntry{epoch}|";
  $id .= "$$scoreEntry{game}|";
  $id .= "$$scoreEntry{smDiff}|";

  if(not defined $$scoreEntry{scoreDetails}){
    die "ERROR: cannot get score entry ID before parsing score details\n";
  }

  for my $attName(@SCORE_DETAILS_ATT_NAMES){
    my $val = $$scoreEntry{scoreDetails}{$attName};
    $id .= "$val|";
  }
  $id .= "$$scoreEntry{songDir}|";

  return $id;
}

sub getSingleNode($$){
  my ($node, $xpath) = @_;
  my $nodeList = $node->findnodes($xpath);
  if($nodeList->size() == 1){
    return $nodeList->get_node(1);
  }else{
    return undef;
  }
}

sub getSingleChildByTagName($$){
  my ($node, $tagName) = @_;
  my $nodeList = $node->getChildrenByTagName($tagName);
  if($nodeList->size() == 1){
    return $nodeList->get_node(1);
  }else{
    return undef;
  }
}

#dance-single           => singles
#StepsType_Dance_Single => singles
#dance-double           => doubles
#StepsType_Dance_Double => doubles
sub convertStepsTypeToGame($){
  my ($stepsType) = @_;
  my $game = $stepsType;
  $game =~ s/^StepsType[_\-]//i;
  $game =~ s/^dance[_\-]//i;
  $game =~ s/s$//; #singles/doubles => single/double, just in case
  if($game =~ /^single$/i){
    return "singles";
  }elsif($game =~ /^double$/i){
    return "doubles";
  }else{
    die "ERROR: unknown StepsType '$stepsType'\n";
  }
}

1;
