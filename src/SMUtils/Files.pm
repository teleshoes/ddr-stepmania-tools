package SMUtils::Files;
use strict;
use warnings;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw();
our @EXPORT = qw(
);

our $DIR_SONGS_PARENT = "$ENV{HOME}/.stepmania-5.0";

our $DIR_XML_CACHE_BASE = "$ENV{HOME}/.cache/stepmania-score-xml";
our $DIR_XML_CACHE_SCORES = "$DIR_XML_CACHE_BASE/scores";
our $DIR_XML_CACHE_STATS = "$DIR_XML_CACHE_BASE/stats";
our $DIR_XML_CACHE_UPLOAD = "$DIR_XML_CACHE_BASE/upload";

1;
