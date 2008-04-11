#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 6;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression', {regex_match => qr/\z/}],
   evaluation => sub {return $_[0]->{expression}},
  },
 expression => {
   rule_type => 'and',
   composed_of => ['term', 
    {repeating => {composed_of => ['plus_or_minus', 'term'],},},],
   evaluation => sub {my $to_combine = $_[0]->{term};
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
   composed_of => ['number', 
    {repeating => {composed_of => ['times_or_divide', 'number']}}],
   evaluation => sub {my $to_combine = $_[0]->{number};
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
   evaluation => sub{ return 0 + $_[0]; }
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

my $calculator_parser = new Parse::Stallion();
$calculator_parser->set_up_full_rule_set({
  rules_to_set_up_hash => \%calculator_rules,
  start_rule => 'start_expression',});

my $result =
 $calculator_parser->parse({parse_this=>"7+4"});
my $parsed_tree = $result->{tree};
$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 11, "simple plus");

$result =
 $calculator_parser->parse({parse_this=>"7*4"});
$parsed_tree = $result->{tree};
$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 28, "simple multiply");

$result =
 $calculator_parser->parse({parse_this=>"3+7*4"});
$parsed_tree = $result->{tree};
$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 31, "simple plus and multiply");

my $array_p = $calculator_parser->which_parameters_are_arrays({
  rule_name => 'term'});

is_deeply({number => 'Array', times_or_divide => 'Array'},
 $array_p, 'Which parameters are arrays arrays');

$array_p = $calculator_parser->which_parameters_are_arrays({
  rule_name => 'start_expression'});

is_deeply({expression => 'Single Value'},
 $array_p, 'Which parameters are arrays single values');

print "\nAll done\n";


