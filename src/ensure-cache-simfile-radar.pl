#!/usr/bin/perl
use strict;
use warnings;

my $USAGE = "Usage:
  $0 -h | --help
    show this message
  OPTS
";

sub main(@){
  my $opts = {
  };
  while(@_ > 0){
    my $arg = shift @_;
    if($arg =~ /^(-h|--help)$/){
      print $USAGE;
      exit 0;
    }else{
      die "$USAGE\nERROR: unknown arg $arg\n";
    }
  }
}

&main(@ARGV);
