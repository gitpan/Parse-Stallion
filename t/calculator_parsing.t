#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 5;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => {
   and => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   and => ['term', 
    {multiple => [{and => ['plus_or_minus', 'term'],}],},],
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
,
 term => {
   and => ['factor', 
    {multiple => [{and => ['times_or_divide_or_modulo', 'factor'],}],},],
   evaluation => sub {my $to_combine = $_[0]->{factor};
    my $times_or_divide_or_modulo = $_[0]->{times_or_divide_or_modulo};
    my $value = shift @$to_combine;
    for my $i (0..$#{$to_combine}) {
      if ($times_or_divide_or_modulo->[$i] eq '*') {
        $value *= $to_combine->[$i];
      }
      elsif ($times_or_divide_or_modulo->[$i] eq '%') {
        $value = $value % $to_combine->[$i];
      }
      else {
#could check for zero
        $value /= $to_combine->[$i];
      }
    }
    return $value;
   },
  },
,
 factor => {
   and => ['fin_exp', 
    {multiple => [{and => ['power_of', 'fin_exp'],}],},],
   evaluation => sub {my $to_combine = $_[0]->{fin_exp};
    my $value = pop @$to_combine;
    while ($#{$to_combine} > -1) {
      $value = (pop @$to_combine) ** $value;
    }
    return $value;
   },
  },
,
fin_exp => {
  or => [
    {and => ['left_parenthesis', 'expression', 'right_parenthesis'],
     evaluation => sub {return $_[0]->{expression} },
     precedence => 0,
    },
    {and => ['number'],
     evaluation => sub {return $_[0]->{number} },
     precedence => 0,
    },
   ],
  },
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
left_parenthesis => {
  regex_match => qr/\s*\(\s*/,
 },
,
right_parenthesis => {
  regex_match => qr/\s*\)\s*/,
 },
,
power_of => {
  regex_match => qr/\s*\*\*\s*/,
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
,
times_or_divide_or_modulo => {
  or => ['times', 'divided_by', 'modulo'],
 },
,
modulo => {
  regex_match => qr/\s*\%\s*/,
 },
,
times => {
  regex_match => qr/\s*\*\s*/,
 },
,
divided_by => {
  regex_match => qr/\s*\/\s*/,
 },
,
);

my $calculator_parser = new Parse::Stallion({
  start_rule => 'start_expression',
  rules_to_set_up_hash => \%calculator_rules});

my $result =
 $calculator_parser->parse_and_evaluate("7+4");
print "Result is $result\n";
is ($result, 11, "simple plus");

$result =
 $calculator_parser->parse_and_evaluate("7*4");
print "Result is $result\n";
is ($result, 28, "simple multiply");

$result =
 $calculator_parser->parse_and_evaluate("3+7*4");
print "Result is $result\n";
is ($result, 31, "simple plus and multiply");

my $x;
($x, $result) =
 eval {
 $calculator_parser->parse_and_evaluate("3+-+7*4")};

is($result->{parse_failed},1,"bad parse on parse and evaluate");


print "\nAll done\n";


