#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Parse::Stallion;

my %calculator_rules = (
 start_expression => A(
   'expression', 'end_of_string',
   E(sub {return $_[0]->{expression}})),
,
 expression => A(
   'term', 
    M(A('plus_or_minus', 'term')),
   E(sub {my $to_combine = $_[0]->{term};
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
  )),
,
 term => A
   ('factor', 
    M(A('times_or_divide_or_modulo', 'factor')),
    E(sub {my $to_combine = $_[0]->{factor};
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
  )),
,
 factor =>
   AND('fin_exp', 
    M(A('power_of', 'fin_exp')),
   E(sub {
#use Data::Dumper;print STDERR "params f are ".Dumper(\@_)."\n";
    my $to_combine = $_[0]->{fin_exp};
    my $value = pop @$to_combine;
    while ($#{$to_combine} > -1) {
      $value = (pop @$to_combine) ** $value;
    }
    return $value;
   },
  )),
,
fin_exp => OR(
    AND('left_parenthesis', 'expression', 'right_parenthesis',
     EVALUATION(sub {
       #use Data::Dumper;print STDERR "Params are ".Dumper(\@_);
       return $_[0]->{expression} }),
    ),
    (AND('number',
     EVALUATION(sub {
       #use Data::Dumper;print STDERR "params are ".Dumper(\@_);
        return $_[0]->{number} }),
    ),
   ),
  ),
,
end_of_string => LEAF({
  nsl_regex_match => qr/\z/,
 }),
,
number => LEAF({
  nsl_regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
 },
EVALUATION(
  sub{
   return 0 + $_[0];
  })),
left_parenthesis => LEAF({
  nsl_regex_match => qr/\s*\(\s*/,
 }),
,
right_parenthesis => LEAF({
  nsl_regex_match => qr/\s*\)\s*/,
 }),
,
power_of => LEAF({
  nsl_regex_match => qr/\s*\*\*\s*/,
 }),
,
plus_or_minus => OR(
  'plus', 'minus',
 ),
,
plus => LEAF({
  nsl_regex_match => qr/\s*\+\s*/,
 }),
,
minus => LEAF({
  nsl_regex_match => qr/\s*\-\s*/,
 }),
,
times_or_divide_or_modulo => OR(
  'times', 'divided_by', 'modulo'
 ),
,
modulo => LEAF({
  nsl_regex_match => qr/\s*\%\s*/,
 }),
,
times => LEAF({
  nsl_regex_match => qr/\s*\*\s*/,
 }),
,
divided_by => LEAF({
  nsl_regex_match => qr/\s*\/\s*/,
 }),
,
);

my $pf_count = 0;
my $pb_count = 0;
my $calculator_stallion = new Parse::Stallion(
  \%calculator_rules,
  {start_rule => 'start_expression',
  parse_forward =>
   sub {
    my $input_string_ref = shift;
    my $rule_definition = shift;
    my $current_value = shift;
    $pf_count=1;
    my $match_rule = $rule_definition->{nsl_regex_match} ||
     $rule_definition->{leaf} ||
     $rule_definition->{l};
    if ($$input_string_ref =~ /\A($match_rule)/) {
      my $matched = $1;
      my $not_match_rule = $rule_definition->{regex_not_match};
      if ($not_match_rule) {
        if (!($$input_string_ref =~ /\A$not_match_rule/)) {
          return (0, undef);
        }
      }
      $$input_string_ref = substr($$input_string_ref, length($matched));
      return (1, $matched);
    }
    return 0;
   },
  parse_backtrack =>
   sub {
    my $input_string_ref = shift;
    my $rule_definition = shift;
    my $current_value = shift;
    my $stored_value = shift;
    $pb_count=1;
    if (defined $stored_value) {
      $$input_string_ref = $stored_value.$$input_string_ref;
    }
   },
  increasing_value_function => sub {
    my $string = shift;
    return 0 - length($string);
  }
});


my $result =
 $calculator_stallion->parse_and_evaluate("7+4");
print "Result is $result should be 11\n";

$result =
 $calculator_stallion->parse_and_evaluate("7*4");
print "Result is $result should be 28\n";

$result =
 $calculator_stallion->parse_and_evaluate("3+7*4");
print "Result is $result should be 31\n";

$result = {};
my $x;
$x = 
 $calculator_stallion->parse_and_evaluate("3+-+7*4", {parse_info=>$result,
  trace => 1});

print "Result is $x should be undef\n";
print "Parse succeded is ".$result->{parse_succeeded}." should be 0\n";

print "\nAll done\n";


