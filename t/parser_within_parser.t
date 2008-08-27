#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 6;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %middle_parsing_rules = (
 start_expression => {
  and => ['ows', 'the_middle', 'ows', {leaf => qr/\z/}],
  e => sub {return $_[0]->{the_middle}},
 },

 ows => {
   l => qr/\s*/,
 },

 the_middle => {
  l => qr/middle|muddle/,
  e => sub {
    my $mid = shift;
    my $k = reverse $mid;
    return $k;
  },
 }

);

my $middle_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%middle_parsing_rules,
  start_rule => 'start_expression',
});

my %parsing_rules = (
 start_expression => {
  and => ['parse_expression', {leaf => qr/\z/}],
  e => sub {return $_[0]->{parse_expression}},
 },
 parse_expression => {
   or=> ['same_sized_lists',],
 },
 same_sized_lists => {
   and => [['string_list', 'list_one'], 'middle', ['string_list','list_two']],
   evaluation => sub {
    if (scalar(@{$_[0]->{list_one}})
    != scalar(@{$_[0]->{list_two}})) {
     return (undef, 1);
     }
     return $_[0]->{middle};
   }
  },
 middle => {
  leaf=>qr/\s+\w+\s+/,
  e => sub {
    my $middle = shift;
    my $j = $middle_parser->parse_and_evaluate({parse_this=>$middle});
    if ($j) {return $j};
    return (undef, 1);
  }
 },
 string_value => {leaf=> qr/\w+/},
 string_list => {
   and => ['string_value', {multiple=>[{and=>['comma','string_value']}]}],
   evaluation => sub {
#print STDERR "sl\n";
    return $_[0]->{string_value}}
  },
 comma => {leaf=>qr/\,/},
);

my $pe_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%parsing_rules,
  start_rule => 'start_expression',
});

my $result;
my $x;

($x, $result) = $pe_parser->parse_and_evaluate({parse_this=>"abc middle def"});

is ($result->{parse_failed},0, 'simple middle parse');

is ($x,'elddim', 'simple middle parse');

($x, $result) = $pe_parser->parse_and_evaluate({parse_this=>"abc muddle def"});

is ($result->{parse_failed},0, 'simple middle parse');

is ($x,'elddum', 'simple middle parse');

($x, $result) = $pe_parser->parse_and_evaluate({parse_this=>"abc maddle def"});

is ($result->{parse_failed},1, 'simple middle parse');


print "\nAll done\n";


