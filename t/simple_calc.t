#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 11;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_rule => {
   rule_type => 'and',
   and => ['expression',],
   e => sub {
#print STDERR "final expression is ".$_[0]->{expression}."\n";
return $_[0]->{expression}},
  },
 expression => {
   rule_type => 'and',
   and => ['term', 
    {m => [{and => ['plus_or_minus', 'term'],}],},],
   e => sub {my $to_combine = $_[0]->{term};
#use Data::Dumper;
#print STDERR "p and e params are ".Dumper(\@_);
    my $plus_or_minus = $_[0]->{plus_or_minus};
    my $value = shift @$to_combine;
    for my $i (0..$#{$to_combine}) {
      if ($plus_or_minus->[$i] eq '+') {
        $value += $to_combine->[$i];
      }
      else {
        $value -= $to_combine->[$i];
      }
    }
    return $value;
   },
  },
 term => {
   and => ['number', 
    {m => [{and => ['times_or_divide', 'number']}]}],
   e => sub {my $to_combine = $_[0]->{number};
    my $times_or_divide = $_[0]->{times_or_divide};
    my $value = shift @$to_combine;
    for my $i (0..$#{$to_combine}) {
      if ($times_or_divide->[$i] eq '*') {
        $value *= $to_combine->[$i];
      }
      else {
        $value /= $to_combine->[$i]; #does not check for zero
      }
    }
    return $value;
   }
 },
 number => {
   rule_type => 'leaf',
   regex_match => qr/\s*[+\-]?(\d+(\.\d*)?|\.\d+)\s*/,
   e => sub{ return 0 + $_[0]; }
 },
 plus_or_minus => {
   rule_type => 'leaf',
   regex_match => qr/\s*[\-+]\s*/,
 },
 times_or_divide => {
   rule_type => 'leaf',
   regex_match => qr/\s*[*\/]\s*/
 },
);

my $calculator_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%calculator_rules,
  });

my $result =
 $calculator_parser->parse_and_evaluate({parse_this=>"7+4"});
#my $parsed_tree = $result->{tree};
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 11, "simple plus");

$result =
 $calculator_parser->parse_and_evaluate({parse_this=>"7*4"});
#$parsed_tree = $result->{tree};
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 28, "simple multiply");

$result =
 $calculator_parser->parse_and_evaluate({parse_this=>"3+7*4"});
#$parsed_tree = $result->{tree};
#print STDERR "3+7*4 pe ".$result->{parsing_evaluation}."\n";
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 31, "simple plus and multiply");

my $array_p = $calculator_parser->which_parameters_are_arrays({
  rule_name => 'term'});

is_deeply({number => 'Array', times_or_divide => 'Array'},
 $array_p, 'Which parameters are arrays arrays');

$array_p = $calculator_parser->which_parameters_are_arrays({
  rule_name => 'start_rule'});

is_deeply({expression => 'Single Value'},
 $array_p, 'Which parameters are arrays single values');

my $short_calculator_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  end_of_parse_allowed => sub {return 1},
  rules_to_set_up_hash => \%calculator_rules,
  });

$result =
 $short_calculator_parser->parse_and_evaluate({parse_this=>"7+4 x"});
is ($result, 11, "simple plus x on short calculator");

$result =
 $calculator_parser->parse_and_evaluate({parse_this=>"7+4 x"});
is ($result, undef, "simple plus x on calculator");

my ($new_result, $details) =
 $short_calculator_parser->parse_and_evaluate({parse_this=>"7+4 x"});
is ($details->{unparsed}, 'x', "unparsed of simple plus x on short calculator");

my $q = '7 + 4 x';

$short_calculator_parser->parse_and_evaluate(\$q);

is ($q, 'x', "var in unparsed of simple plus x on short calculator");

$q = '7 + 4 x';

$short_calculator_parser->parse_and_evaluate({parse_this=>\$q});

is ($q, 'x', "var in as hash unparsed of simple plus x on short calculator");

print "\nAll done\n";
