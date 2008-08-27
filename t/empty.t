#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 7;
use Carp;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => {
   and => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   and => ['expression', 'plus_or_minus', 'number'],
   }
,
end_of_string => {
  regex_match => qr/\z/,
 },
,
number => {
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
plus_or_minus => {
  or => ['plus', 'minus'],
 },
,
plus => {
  regex_match => qr/\s*\+\s*/,
 },
,
minus => {
  regex_match => qr/\s*\-\s*/,
 },
);

my $calculator_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%calculator_rules,
  start_rule => 'start_expression'});

eval {
my $result =
 $calculator_parser->parse_and_evaluate(
{parse_this=>"7+4", trace => 0});
};
like ($@, qr/^expression duplicated in parse/,'invalid grammar 1');

my %empty_rules = (
 start_expression => {
   and => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   and => ['empty', 'expression', 'number'],
   }
,
end_of_string => {
  regex_match => qr/\z/,
 },
,
number => {
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
empty => {
  regex_match => qr/^/,
 },
,
);

my $empty_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%empty_rules,
  start_rule => 'start_expression'});

eval {
my $result =
 $empty_parser->parse_and_evaluate(
{parse_this=>"7+4", trace => 0});
};
like ($@, qr/^expression duplicated in parse/,'invalid grammar 2');

my %third_calculator_rules = (
 start_expression => {
   and => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   or => [
 { and  => ['number', 'plus_or_minus', 'expression']},
'number',
   ]
   }
,
end_of_string => {
  regex_match => qr/\z/,
 },
,
number => {
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
plus_or_minus => {
  or => ['plus', 'minus'],
 },
,
plus => {
  regex_match => qr/\s*\+\s*/,
 },
,
minus => {
  regex_match => qr/\s*\-\s*/,
 },
);

my $third_calculator_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%third_calculator_rules,
  start_rule => 'start_expression'});

#print STDERR "third calc\n";

my $x;
($x, $result) =
 $third_calculator_parser->parse_and_evaluate(
{parse_this=>"7", trace => 0});
is ($result->{parse_succeeded}, 1, 'third calculator number');

($x, $result) =
 $third_calculator_parser->parse_and_evaluate(
{parse_this=>"7+4", trace => 0});
is ($result->{parse_succeeded}, 1, 'third calculator number plus number');

my %bad_rule_set = (
 start_expression => {
   and => ['expression'],
   evaluation => sub {return $_[0]->{expression}},
  }
);

my $bad_parser = eval {new Parse::Stallion({
  start_rule => 'start_expression',
  rules_to_set_up_hash => \%bad_rule_set
})};

like ($@, qr/^Missing rules: Rule start_expression missing /,'missing rule');

my %bad_rule_set_2 = (
 start_expression => {
   and => ['expression'],
  },
 expression => {
   leaf => qr/AA/,
  },
 junk_rule => {
   leaf => qr/BB/,
  },
);

my $bad_parser_2 = eval {new Parse::Stallion({
  start_rule => 'start_expression',
  rules_to_set_up_hash => \%bad_rule_set_2
})};

like ($@, qr/^Unreachable rules: No path to rule junk_rule/,'unreachable rule');

print "\nAll done\n";


