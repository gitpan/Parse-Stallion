#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 8;
use Carp;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => A(
   'expression', 'end_of_string',
   E(sub {return $_[0]->{expression}})
  )
,
 expression => A(
   'expression', 'plus_or_minus', 'number'
   )
,
end_of_string => L(
  qr/\z/
 ),
,
number => L(
  qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  E(sub{
   return 0 + $_[0];
  })
 ),
,
plus_or_minus => O(
  'plus', 'minus'
 ),
,
plus => L(
  qr/\s*\+\s*/
 ),
,
minus => L(
  qr/\s*\-\s*/
 ),
);

my $calculator_parser = new Parse::Stallion(
  \%calculator_rules,
  {start_rule => 'start_expression'});

eval { my $result = $calculator_parser->parse_and_evaluate("7+4"); };
like ($@, qr/^expression duplicated in parse/,'invalid grammar 1');

my %empty_rules = (
 start_expression => A(
   'expression', 'end_of_string',
   E(sub {return $_[0]->{expression}}),
  )
,
 expression => A(
   'empty', 'expression', 'number'
   )
,
end_of_string => L(
  qr/\z/
 ),
,
number => L(
  qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  E(sub{
   return 0 + $_[0];
  })
 )
,
empty => L(
  qr/^/
 )
,
);

my $empty_parser = new Parse::Stallion(
  \%empty_rules,
  {start_rule => 'start_expression'});

eval { my $result = $empty_parser->parse_and_evaluate( "7+4" ); };
like ($@, qr/^expression duplicated in parse/,'invalid grammar 2');

my %third_calculator_rules = (
 start_expression => A(
   'expression', 'end_of_string',
   E(sub {return $_[0]->{expression}}),
  )
,
 expression => O(
 A('number', 'plus_or_minus', 'expression'),
'number',
   )
,
end_of_string => L(
  qr/\z/
 )
,
number => L(
  qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  E(sub{
   return 0 + $_[0];
  })
 )
,
plus_or_minus => O(
  'plus', 'minus'
 )
,
plus => L(
  qr/\s*\+\s*/
 )
,
minus => L(
  qr/\s*\-\s*/
 )
);

my $third_calculator_parser = new Parse::Stallion(
  \%third_calculator_rules,
  {start_rule => 'start_expression'});

#print STDERR "third calc\n";

$result = {};
my $x;
$x = $third_calculator_parser->parse_and_evaluate("7", {parse_info=>$result});
is ($result->{parse_succeeded}, 1, 'third calculator number');

$result = {};
$x = $third_calculator_parser->parse_and_evaluate("7+4", {parse_info=>$result});
is ($result->{parse_succeeded}, 1, 'third calculator number plus number');

my %bad_rule_set = (
 start_expression => A(
   'expression',
   E(sub {return $_[0]->{expression}})
  )
);

my $bad_parser = eval {new Parse::Stallion(
  \%bad_rule_set,
  { start_rule => 'start_expression'
})};

like ($@, qr/^Missing rules: Rule start_expression missing /,'missing rule');

my %bad_rule_set_2 = (
 start_expression => A(
   'expression'
  ),
 expression =>
   qr/AA/
  ,
 junk_rule =>
   qr/BB/
);

my $bad_parser_2 = eval {new Parse::Stallion(
  \%bad_rule_set_2,
   { start_rule => 'start_expression' })};

like ($@, qr/^Unreachable rules: No path to rule junk_rule/,'unreachable rule');

my %bad_rule_set_3 = (
 start__XZ__expression => A(
   'expression',
   E(sub {return $_[0]->{expression}})
  )
);

$bad_parser = eval {new Parse::Stallion( \%bad_rule_set_3)};

like ($@, qr/contains separator/,'separator named rule');

print "\nAll done\n";


