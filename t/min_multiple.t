#!/usr/bin/perl
#Copyright 2008 Arthur S Goldstein
use Test::More tests => 5;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules_with_min_first = (
 start_expression => A(
  'parse_expression', L(qr/x*/), L(qr/\z/),
  E(sub {
#use Data::Dumper;print STDERR "in se is ".Dumper(\@_);
    return $_[0]->{parse_expression}})
 ),
 parse_expression => M(
   'pe', 'match_min_first', USE_PARSE_MATCH()
 ),
 pe => L(
   qr/./
 ),
);

my %parsing_rules_without_min_first = (
 start_expression =>
  A('parse_expression', L(qr/x*/), L(qr/\z/),
  E(sub { return $_[0]->{parse_expression}})
 ),
 parse_expression => M(
   'pe', USE_PARSE_MATCH
 ),
 pe => L(
   qr/./
 )
);

my $with_min_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%parsing_rules_with_min_first,
  start_rule => 'start_expression',
});

my $without_min_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%parsing_rules_without_min_first,
  start_rule => 'start_expression',
});

#my $result;

my ($result, $other) = $with_min_parser->parse_and_evaluate({parse_this=>"qxxx"});

#use Data::Dumper;print STDERR "parse trace is ".Dumper($other->{parse_trace})."\n";
is ($result,'q', 'min parser');

$result = $without_min_parser->parse_and_evaluate({parse_this=>"qxxx"});

is ($result,'qxxx', 'without min parser');

$result = $with_min_parser->parse_and_evaluate({parse_this=>"xxx"});

is ($result,'', 'no q min parser');

$result = $without_min_parser->parse_and_evaluate({parse_this=>"xxx"});

is ($result,'xxx', 'no q without min parser');

print "\nAll done\n";


