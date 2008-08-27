#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 7;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => {
   and => ['expression', 'end_of_string'],
  }
,
 expression => {
   and => ['term', 
    {multiple => [{and => ['plus_or_minus', 'term'],}],},],
 }
,
 term => {
   and => ['factor', 
    {multiple => [{and => ['times_or_divide_or_modulo', 'factor'],}],},],
  },
,
 factor => {
   and => ['fin_exp', 
    {multiple => [{and => ['power_of', 'fin_exp'],}],},],
  },
,
fin_exp => {
  or => [
    {and => ['left_parenthesis', 'expression', 'right_parenthesis'],
    },
    {and => ['number'],
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

my $calculator_parser = new Parse::Stallion({do_not_compress_eval => 1,
 rules_to_set_up_hash => \%calculator_rules,
 start_rule=> 'start_expression'});

my $result =
 $calculator_parser->parse_and_evaluate("7+4");
is_deeply ($result, 
{                            
          'end_of_string' => '',
          'expression' => {
                            'plus_or_minus' => [
                                                 {
                                                   'plus' => '+'
                                                 }
                                               ],
                            'term' => [
                                        {
                                          'factor' => [
                                                        {
                                                          'fin_exp' => [
                                                                         {
                                                                           'number' => '7'
                                                                         }
                                                                       ]
                                                        }
                                                      ]
                                        },
                                        {
                                          'factor' => [
                                                        {
                                                          'fin_exp' => [
                                                                         {
                                                                           'number' => '4'
                                                                         }
                                                                       ]
                                                        }
                                                      ]
                                        }
                                      ]
                          }
        }
, "simple plus");


my %simp_calculator_rules = (
 start_expression => {
   and => ['expression',],
  }
,
 expression => {
   and => ['number', 
    {multiple => {and => [[{regex_match=>qr/\s*\+\s*/},'plus'], 'number'],}},],
 }
,
number => {
  regex_match => qr/\d*/,
 },
,
);

#print STDERR "before sett scr are ".Dumper(\%simp_calculator_rules)."\n";
#print STDERR "setting simp\n";
my $simp_calculator_parser =
 new Parse::Stallion({do_not_compress_eval => 1,
  rules_to_set_up_hash => \%simp_calculator_rules,
  start_rule => 'start_expression'});

$result =
 $simp_calculator_parser->
  parse_and_evaluate("7+4");
#use Data::Dumper;print STDERR "1 result is ".Dumper($result)."\n";

is_deeply($result,
{                            
          'expression' => {
                            'plus' => [
                                        '+'
                                      ],
                            'number' => [
                                          '7',
                                          '4'
                                        ]
                          }
        }
,'simple calc');

#print STDERR "setting n simp\n";
my $n_simp_calculator_parser =
 new Parse::Stallion({do_not_compress_eval => 0,
  rules_to_set_up_hash => \%simp_calculator_rules,
  start_rule => 'start_expression'});

#print STDERR "after sett scr are ".Dumper(\%simp_calculator_rules)."\n";

$result =
 $n_simp_calculator_parser->
  parse_and_evaluate("7+4");
#use Data::Dumper;print STDERR "result is ".Dumper($result)."\n";

is_deeply($result,
{                            
                            'plus' => [
                                        '+'
                                      ],
                            'number' => [
                                          '7',
                                          '4'
                                        ]
        }
,'simple calc n');

#print STDERR "setting de simp\n";
my $de_simp_calculator_parser =
 new Parse::Stallion({do_not_compress_eval => 1,
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%simp_calculator_rules,
  start_rule => 'start_expression'});

$result =
 $de_simp_calculator_parser->
  parse_and_evaluate("7+4");
#use Data::Dumper;print STDERR "de 1 result is ".Dumper($result)."\n";

is_deeply($result,
{                            
          'expression' => {
                            'plus' => [
                                        '+'
                                      ],
                            'number' => [
                                          '7',
                                          '4'
                                        ]
                          }
        }
,'de simple calc');

#print STDERR "setting de n simp\n";
my $de_n_simp_calculator_parser =
 new Parse::Stallion({do_not_compress_eval => 0,
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%simp_calculator_rules,
  start_rule => 'start_expression'});

$result =
 $de_n_simp_calculator_parser->
  parse_and_evaluate("7+4");
#use Data::Dumper;print STDERR "de result is ".Dumper($result)."\n";

is_deeply($result,
{                            
                            'plus' => [
                                        '+'
                                      ],
                            'number' => [
                                          '7',
                                          '4'
                                        ]
        }
,'de simple calc n');

$result =
 $de_n_simp_calculator_parser->
  parse_and_evaluate("7+4 + 5");
#use Data::Dumper;print STDERR "de mc result is ".Dumper($result)."\n";

is_deeply($result,
{                            
                            'plus' => [
                                        '+',
                                        ' + '
                                      ],
                            'number' => [
                                          '7',
                                          '4',
                                          '5'
                                        ]
        }
,'de simple calc n more complicated');
