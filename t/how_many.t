#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 6;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules = (
 start_expression => {
  and => ['two_statements', {leaf => qr/\z/}],
  evaluation => sub {return $_[0]->{'two_statements'}},
 },
 two_statements => {
   and=> ['list_statement','truth_statement'],
   evaluation => sub {
     if ($_[0]->{list_statement} != $_[0]->{truth_statement}) {
       return (undef, 1);
     }
     return 1;
   }
 },
 list_statement => {
   and => ['count_statement', 'list'],
   evaluation => sub {
#print STDERR "input is now ".Dumper(\@_);
     if ($_[0]->{count_statement} == scalar(@{$_[0]->{list}})) {
       return 1;
     }
     return 0;
   }
 },
 count_statement => {
   and => [{leaf=>qr/there are /i},'number',{l=>qr/ elements in /}],
   evaluation => sub {
     return $_[0]->{number};
   }
  },
 number => {
  leaf=>qr/\d+/,
   evaluation => sub { return 0 + shift; }
 },
 list => {and => ['number', {multiple=>{and=>[{l=>qr/\,/}, 'number']}}],
  evaluation => sub {return $_[0]->{number}}
 },
 truth_statement => {
   or => [{l=>qr/\. that is the truth\./, alias=>'t'},
    {l=>qr/\. that is not the truth\./, alias=>'t'}],
   evaluation => sub {
     #use Data::Dumper;
     #print STDERR "input is ".Dumper(\@_)."\n";
     if ($_[0]->{t} =~ /not/) {
       return 0;
     }
     return 1;
   }
 },
);

my $how_many_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1
 });
$how_many_parser->set_up_full_rule_set({
  rules_to_set_up_hash => \%parsing_rules,
  start_rule => 'start_expression',
});

my $result;

$result = $how_many_parser->parse_and_evaluate({
  parse_this=>"there are 5 elements in 5,4,3,2,1. that is the truth."});

#print STDERR "result is $result\n";

is ($result, 1, 'true statement');

$result = $how_many_parser->parse_and_evaluate({
  parse_this=>"there are 4 elements in 5,4,3,1. that is the truth."});

#print STDERR "result is $result\n";

is ($result, 1, 'another true statement');

$result = $how_many_parser->parse_and_evaluate({
  parse_this=>"there are 5 elements in 5,4,3,1. that is not the truth."});

#print STDERR "result is $result\n";

is ($result, 1, 'true but trickier statement');

$result = $how_many_parser->parse_and_evaluate({
  parse_this=>"there are 5 elements in 5,4,3,1. that is the truth."});

#print STDERR "result is $result\n";

is ($result, undef, 'not true statement');

$result = $how_many_parser->parse_and_evaluate({
  parse_this=>"there are 4 elements in 5,4,3,1. that is not the truth."});

#print STDERR "result is $result\n";

is ($result, undef, 'another not true statement');
