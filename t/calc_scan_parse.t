#!/usr/bin/perl
#Copyright 2008 Arthur S Goldstein
use Test::More tests => 4;
BEGIN { use_ok('Parse::Stallion') };

my @results_array;
my %calculator_scan_rules = (
 start_expression => {
   rule_type => 'and',
   composed_of => ['tokens', {regex_match => qr /\z/}]
  }
,
 tokens => {
   multiple => 'token'
 }
,
 token => {
   or => ['whitespace', 
    'comment',
    'less_than_equal',
    'greater_than_equal',
    'equal',
    'left_parenthesis',
    'right_parenthesis',
    'addition',
    'subtraction',
    'multiplication',
    'assignment',
    'semicolon',
    'literal',
    'identifier',
    'constant',
   ],
  },
whitespace => {
   leaf => qr/\s+/,
   evaluation => sub {}
  },
comment => {
  leaf => qr/\/\*.*?\*\//,
  evaluation => sub {}
 },
less_than_equal => {
  leaf => qr/\<\=?/,
  evaluation => sub {
    if ($_[0] eq '<') {
      push @results_array, {token=>'less than'};
    }
    else {
      push @results_array, {token=>'less than or equal'};
    }
  }
 },
greater_than_equal => {
  leaf => qr/\>\=?/,
  evaluation => sub {
    if ($_[0] eq '>') {
      push @results_array, {token=>'greater than'};
    }
    else {
      push @results_array, {token=>'greater than or equal'};
    }
  }
 },
equal => {
  leaf => qr/\=/,
  evaluation => sub {
    push @results_array, {token=>'equal'};
  }
 },
left_parenthesis => {
  leaf => qr/\(/,
  evaluation => sub {
    push @results_array, {token=>'left parenthesis'};
  }
 },
right_parenthesis => {
  leaf => qr/\)/,
  evaluation => sub {
    push @results_array, {token=>'right parenthesis'};
  }
 },
addition => {
  leaf => qr/\+/,
  evaluation => sub {
    push @results_array, {token=>'addition'};
  }
 },
subtraction => {
  leaf => qr/\-/,
  evaluation => sub {
    push @results_array, {token=>'subtraction'};
  }
 },
multiplication => {
  leaf => qr/\*/,
  evaluation => sub {
    push @results_array, {token=>'multiplication'};
  }
 },
assignment => {
  leaf => qr/\:\=/,
  evaluation => sub {
    push @results_array, {token=>'assignment'};
  }
 },
semicolon => {
  leaf => qr/\;/,
  evaluation => sub {
    push @results_array, {token=>'assignment'};
  }
 },
literal => {
  leaf => qr/\"[^"]*\"/,
  evaluation => sub {
    my $in_literal = $_[0];
    $in_literal =~ s/\"//;
    push @results_array, {token=>'literal', value => $in_literal};
  }
 },
identifier => {
  leaf => qr/[a-zA-Z]\w*/,
  evaluation => sub {
    push @results_array, {token=>'identifier', value => $_[0]};
  }
 },
constant => {
  leaf => qr/\d+/,
  evaluation => sub {
    push @results_array, {token=>'constant', value => $_[0]};
  }
 }
);

my $calculator_scan_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%calculator_scan_rules,
  start_rule => 'start_expression'});

my $result =
 $calculator_scan_parser->parse_and_evaluate({parse_this=>"7+4"});

is_deeply (\@results_array, 
 [                        
          {
            'value' => '7',
            'token' => 'constant'
          },
          {
            'token' => 'addition'
          },
          {
            'value' => '4',
            'token' => 'constant'
          }
        ]
,
 "tokenized simple plus");

@results_array = ();
$result =
 $calculator_scan_parser->parse_and_evaluate({parse_this=>"8*7+4+ (43 )"});

is_deeply (\@results_array, 
 [                        
          {
            'value' => '8',
            'token' => 'constant'
          },
          {
            'token' => 'multiplication'
          },
          {
            'value' => '7',
            'token' => 'constant'
          },
          {
            'token' => 'addition'
          },
          {
            'value' => '4',
            'token' => 'constant'
          },
          {
            'token' => 'addition'
          },
          {
            'token' => 'left parenthesis'
          },
          {
            'value' => '43',
            'token' => 'constant'
          },
          {
            'token' => 'right parenthesis'
          },
        ]
,
 "tokenized times plus plus parentheses");


my %calculator_parse_rules = (
 start_expression => {and => ['expression', 'no_more'],
   evaluation => sub {return $_[0]->{expression}}
 },
 expression => {
   or => [{and=>['term', 'addition', 'expression']}, 'term'],
   evaluation => sub {if (defined $_[0]->{expression}) {
     return $_[0]->{term} + $_[0]->{expression};
    }
   return $_[0]->{term};
  }
 }
,
 term => {
   or => [{and=>['factor', 'multiplication', 'term']}, 'factor'],
   evaluation => sub {if (defined $_[0]->{term}) {
     return $_[0]->{term} * $_[0]->{factor};
    }
   return $_[0]->{factor};
 }
 },
,
 factor => {
   or => [{and=>['left_parenthesis', 'constant', 'right_parenthesis']},
    'constant'],
   evaluation => sub {return $_[0]->{constant}}
 },
left_parenthesis => {
  scan_leaf => 'left parenthesis'
 },
right_parenthesis => {
  scan_leaf => 'right parenthesis'
 },
constant => {
  scan_leaf => 'constant',
  evaluation => sub {return $_[0]->{value}}
 },
addition => {
  scan_leaf => 'addition'
 },
multiplication => {
  scan_leaf => 'multiplication'
 },
no_more => {
  scan_leaf => ''
 }
);

my $calculator_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%calculator_parse_rules,
  scanner => 1,
  start_rule => 'start_expression'});

$result =
 $calculator_parser->parse({scan_array=>\@results_array,
  trace => 0});

$result =
 $calculator_parser->parse_and_evaluate({scan_array=>\@results_array});

is ($result, 103, 'scan and parse');

print "\nAll done\n";


