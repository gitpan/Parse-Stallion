#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 4;
BEGIN { use_ok('Parse::Stallion') };
use Time::Local;
#use Data::Dumper;

my %rule;
$rule{start_rule} = { rule_type => 'and',
  composed_of => ['white_space_word', 'end_of_string'],
  evaluation => sub {
    my $param = shift;
    if ($param->{white_space_word} =~ /\s/) {
      return "found white space";
    }
    else {
      return "no white space";
    }
  }
};
$rule{white_space_word} = { 
  leaf => qr/\s+\w+\s+/,
};
$rule{end_of_string} = {
  leaf => qr/\z/,
};
my ($result_1, $result_2);

my $after_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%rule,
  start_rule => 'start_rule',
});

$result_1 = $after_parser->parse_and_evaluate({parse_this=>' jj '});



my $during_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%rule,
  start_rule => 'start_rule',
});

$result_2 = $during_parser->parse_and_evaluate({parse_this=>' jj '});

is ($result_1, $result_2, "with spaces match");



my $ks_after_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%rule,
  keep_white_space => 0,
  start_rule => 'start_rule',
});

$result_1 = $ks_after_parser->parse_and_evaluate({parse_this=>' jj '});

my $ks_during_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%rule,
  keep_white_space => 0,
  start_rule => 'start_rule',
});

$result_2 = $ks_during_parser->parse_and_evaluate({parse_this=>' jj '});

is ($result_1, $result_2, "with forced keep white spaces match");


my $kws_after_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%rule,
  keep_white_space => 1,
  start_rule => 'start_rule',
});

$result_1 = $kws_after_parser->parse_and_evaluate({parse_this=>' jj '});

my $kws_during_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%rule,
  keep_white_space => 1,
  start_rule => 'start_rule',
});

$result_2 = $kws_during_parser->parse_and_evaluate({parse_this=>' jj '});

is ($result_1, $result_2, "with forced not to keep white spaces match");

