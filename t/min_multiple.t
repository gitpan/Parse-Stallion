#!/usr/bin/perl
#Copyright 2008 Arthur S Goldstein
use Test::More tests => 5;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules_with_min_first = (
 start_expression => {
  a => ['parse_expression', {l => qr/x*/}, {l => qr/\z/}],
  e => sub {return $_[0]->{parse_expression}},
 },
 parse_expression => {
   m => 'pe',
   match_min_first => 1,
   e => sub { if (!exists $_[0]->{pe}) {return ''}
    return join('',@{$_[0]->{pe}})},
 },
 pe => {
   l => qr/./,
 },
);

my %parsing_rules_without_min_first = (
 start_expression => {
  a => ['parse_expression', {l => qr/x*/}, {l => qr/\z/}],
  e => sub { return $_[0]->{parse_expression}},
 },
 parse_expression => {
   m => 'pe',
   e => sub { return join('',@{$_[0]->{pe}})},
 },
 pe => {
   l => qr/./,
 },
);

my $with_min_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%parsing_rules_with_min_first,
  start_rule => 'start_expression',
});

my $without_min_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%parsing_rules_without_min_first,
  start_rule => 'start_expression',
});

my $result;

$result = $with_min_parser->parse_and_evaluate({parse_this=>"qxxx"});

is ($result,'q', 'min parser');

$result = $without_min_parser->parse_and_evaluate({parse_this=>"qxxx"});

is ($result,'qxxx', 'without min parser');

$result = $with_min_parser->parse_and_evaluate({parse_this=>"xxx"});

is ($result,'', 'no q min parser');

$result = $without_min_parser->parse_and_evaluate({parse_this=>"xxx"});

is ($result,'xxx', 'no q without min parser');

print "\nAll done\n";


