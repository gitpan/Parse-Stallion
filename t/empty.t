#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 9;
use Carp;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   rule_type => 'and',
   composed_of => ['expression', 'plus_or_minus', 'number'],
   }
,
end_of_string => {
  rule_type => 'leaf',
  regex_match => qr/\z/,
 },
,
number => {
  rule_type => 'leaf',
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
plus_or_minus => {
  rule_type => 'or',
  any_one_of => ['plus', 'minus'],
 },
,
plus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\+\s*/,
 },
,
minus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\-\s*/,
 },
);

my $calculator_parser = new Parse::Stallion();
foreach my $rule_name (keys %calculator_rules) {
  $calculator_parser->add_rule({rule_name => $rule_name,
 %{$calculator_rules{$rule_name}}});
}
$calculator_parser->generate_evaluate_subroutines;

eval {
my $result =
 $calculator_parser->parse(
{initial_node => 'start_expression', parse_this=>"7+4", trace => 0});
};
like ($@, qr/^expression duplicated in parse/,'invalid grammar 1');

my %empty_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   rule_type => 'and',
   composed_of => ['empty', 'expression', 'number'],
   }
,
end_of_string => {
  rule_type => 'leaf',
  regex_match => qr/\z/,
 },
,
number => {
  rule_type => 'leaf',
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
empty => {
  rule_type => 'leaf',
  regex_match => qr/^/,
 },
,
);

my $empty_parser = new Parse::Stallion();
foreach my $rule_name (keys %empty_rules) {
  $empty_parser->add_rule({rule_name => $rule_name,
 %{$empty_rules{$rule_name}}});
}
$empty_parser->generate_evaluate_subroutines;

eval {
my $result =
 $empty_parser->parse(
{initial_node => 'start_expression', parse_this=>"7+4", trace => 0});
};
like ($@, qr/^expression duplicated in parse/,'invalid grammar 2');

my %second_calculator_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   or => ['number', {
    and  => ['expression', 'plus_or_minus', 'number']},
   ]
   }
,
end_of_string => {
  rule_type => 'leaf',
  regex_match => qr/\z/,
 },
,
number => {
  rule_type => 'leaf',
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
plus_or_minus => {
  rule_type => 'or',
  any_one_of => ['plus', 'minus'],
 },
,
plus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\+\s*/,
 },
,
minus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\-\s*/,
 },
);

my $second_calculator_parser = new Parse::Stallion();
foreach my $rule_name (keys %second_calculator_rules) {
  $second_calculator_parser->add_rule({rule_name => $rule_name,
 %{$second_calculator_rules{$rule_name}}});
}
$second_calculator_parser->generate_evaluate_subroutines;

$result =
 $second_calculator_parser->parse(
{initial_node => 'start_expression', parse_this=>"7", trace => 0});
is ($result->{parse_succeeded}, 1, 'second calculator number');

$result =
 $second_calculator_parser->parse(
{initial_node => 'start_expression', parse_this=>"7+4", trace => 0});
is ($result->{parse_failed}, 1, 'second calculator number plus number');

my %third_calculator_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression', 'end_of_string'],
   evaluation => sub {return $_[0]->{expression}},
  }
,
 expression => {
   or => [
 { and  => ['number', 'plus_or_minus', 'expression']},
'number',
   ]
   }
,
end_of_string => {
  rule_type => 'leaf',
  regex_match => qr/\z/,
 },
,
number => {
  rule_type => 'leaf',
  regex_match => qr/\s*[+-]?(\d+(\.\d*)?|\.\d+)\s*/,
  evaluation => sub{
   return 0 + $_[0];
  },
 },
,
plus_or_minus => {
  rule_type => 'or',
  any_one_of => ['plus', 'minus'],
 },
,
plus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\+\s*/,
 },
,
minus => {
  rule_type => 'leaf',
  regex_match => qr/\s*\-\s*/,
 },
);

my $third_calculator_parser = new Parse::Stallion();
foreach my $rule_name (keys %third_calculator_rules) {
  $third_calculator_parser->add_rule({rule_name => $rule_name,
 %{$third_calculator_rules{$rule_name}}});
}
$third_calculator_parser->generate_evaluate_subroutines;

$result =
 $third_calculator_parser->parse(
{initial_node => 'start_expression', parse_this=>"7", trace => 0});
is ($result->{parse_succeeded}, 1, 'third calculator number');

$result =
 $third_calculator_parser->parse(
{initial_node => 'start_expression', parse_this=>"7+4", trace => 0});
is ($result->{parse_succeeded}, 1, 'third calculator number plus number');

my %bad_rule_set = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression'],
   evaluation => sub {return $_[0]->{expression}},
  }
);

my $bad_parser = eval {new Parse::Stallion({
  start_rule => 'start_expression',
  rules_to_set_up_hash => \%bad_rule_set
})};

like ($@, qr/^Missing rules: Rule start_expression missing composition expression/,'missing rule');

my %bad_rule_set_2 = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['expression'],
  },
 expression => {
   leaf => qr/AA/,
  },
 junk_rule => {
   leaf => qr/BB/,
  },
);

my $bad_parser_2 = eval {new Parse::Stallion({
  start_rule => 'start_expression',
  rules_to_set_up_hash => \%bad_rule_set_2
})};

like ($@, qr/^Unreachable rules: No path to rule junk_rule/,'unreachable rule');

print "\nAll done\n";


