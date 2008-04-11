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
 $calculator_parser->parse({parse_this=>"3+7*4" });
$parsed_tree = $result->{tree};
$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($result, 31, "simple plus and multiply");

my @bottom_up_names;
my @bottom_up_pvalues;
$calculator_parser->remove_non_evaluated_nodes({tree=>$parsed_tree});
foreach my $node ($parsed_tree->bottom_up_depth_first_search) {
  push @bottom_up_names, $node->values->{name};
  push @bottom_up_pvalues, $node->values->{pvalue};
}

is_deeply(\@bottom_up_names,
[qw (number term plus_or_minus number times_or_divide number term expression
 start_expression)]
, 'names in bottom up search');

is_deeply(\@bottom_up_pvalues,
[ 3, 3, '+', 7, '*', 4, '7*4', '3+7*4', '3+7*4']
, 'pvalues in bottom up search');

#print STDERR "bun ".join('.bun.', @bottom_up_names)."\n";

#print STDERR "bup ".join('.bup.', @bottom_up_pvalues)."\n";

print "\nAll done\n";


