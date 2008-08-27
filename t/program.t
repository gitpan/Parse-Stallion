#!/usr/bin/perl
#Copyright 2008 Arthur S Goldstein
use Test::More tests => 2;
BEGIN { use_ok('Parse::Stallion') };

my $big_output_string;
my %variables;
sub less_than_equal_sub {return $_[0] <= $_[1]};
sub less_than_sub {return $_[0] < $_[1]};
sub greater_than_equal_sub {return $_[0] >= $_[1]};
sub greater_than_sub {return $_[0] > $_[1]};
sub equality_sub {return $_[0] == $_[1]};

my %program_rules = (
 program => {
   rule_type => 'and',
   and => ['block_of_statements', {leaf=>qr/\z/}],
   evaluation => sub {my $block_of_statements = $_[0]->{block_of_statements};
       return $block_of_statements;
    }
  }
,
 ows => { #optional white space
    regex_match => qr/\s*/,
  }
,
 block_of_statements => {
   multiple => ['full_statement'],
   evaluation => sub {
      my @statements = @{$_[0]->{full_statement}};
      return sub {
        foreach $statement (@statements) {
         &$statement}
      }
    }
  }
,
  full_statement => {
   and=>['statement', 'ows', {regex_match=>qr/\;/} , 'ows'],
   evaluation => sub {return $_[0]->{statement}}
 }
,
 statement => {
   or => ['assignment', 'print', 'while']
 }
,
  assignment => {
   and => ['variable', 'ows', {regex_match=>'\='},
     'ows', 'numeric_expression'],
   evaluation => sub {
     my $variable = $_[0]->{variable};
     my $numeric_expression = $_[0]->{numeric_expression};
     return sub {
      $variables{$variable} = &$numeric_expression};
   }
 }
,
  variable => {
    regex_match=> qr/\w+/,
    regex_not_match => qr/
     while|
     print
    /
 }
,
  print => {
   and => [{regex_match=>qr/print/}, 'ows', 'numeric_expression'],
   evaluation => sub {
     my $numeric_expression = $_[0]->{numeric_expression};
     return sub {my $ne = &$numeric_expression;
       $big_output_string .= $ne;
 #      print $ne  #commented out because causes problems with make test
   }}
 }
,
  while => {
   and => [{regex_match=> qr/while/}, 'ows',
      {regex_match=> qr/\(/}, 'ows',
    'condition', 'ows',
     {regex_match=> qr/\)/}, 'ows',
     {regex_match=> qr/\{/}, 'ows',
      'block_of_statements', 'ows',
     {regex_match => qr/\}/}, 'ows'],
   evaluation => sub {
     my $condition = $_[0]->{condition};
     my $block_of_statements = $_[0]->{block_of_statements};
     return sub {
      while (&$condition) {&$block_of_statements}
    }
   }
 }
,
  condition => { and=> ['ows', 'value', 'ows', 'comparison', 'ows',
   'value', 'ows'],
   evaluation => sub {
     my $left_value = $_[0]->{value}->[0];
     my $right_value = $_[0]->{value}->[1];
     my $comparison = $_[0]->{comparison};
     return sub {
       my $left = &$left_value;
       my $right = &$right_value;
       &$comparison($left, $right);
     }
   }
 }
,
  comparison => {or=>['less_than_equal','less_than',
   'greater_than_equal', 'greater_than', 'equality']},
less_than_equal => {
  leaf => qr/\<\=/,
  evaluation => sub {return \&less_than_equal_sub},
 },
less_than => {
  leaf => qr/\</,
  evaluation => sub {return \&less_than_sub},
 },
greater_than_equal => {
  leaf => qr/\>\=/,
  evaluation => sub {return \&greater_than_equal_sub},
 },
greater_than => {
  leaf => qr/\>/,
  evaluation => sub {return \&greater_than_sub},
 },
equality => {
  leaf => qr/\=\=/,
  evaluation => sub {return \&equality_sub},
 },
 plus_or_minus => {
   leaf => qr/[\-+]/
 },
 times_or_divide => {
   leaf => qr/[*\/]/
 },
 numeric_expression => {
   rule_type => 'and',
   and => ['term', 'ows',
    {m => [{and => ['plus_or_minus', 'ows', 'term', 'ows'],}],},],
   evaluation => sub {my $terms = $_[0]->{term};
    my $plus_or_minus = $_[0]->{plus_or_minus};
    my $value = shift @$terms;
    return sub {
      my $to_return = &$value;
      for my $i (0..$#{$terms}) {
        if ($plus_or_minus->[$i] eq '+') {
          $to_return += &{$terms->[$i]};
        }
        else {
          $to_return -= &{$terms->[$i]};
        }
      }
      return $to_return;
    }
   },
  },
 term => {
   and => ['value', 
    {m => [{and => ['times_or_divide', 'value']}]}],
   evaluation => sub {
    my $values = $_[0]->{value};
    my $times_or_divide = $_[0]->{times_or_divide};
    my $first_value = shift @$values;
    return sub {
      my $to_return = &$first_value;
      for my $i (0..$#{$values}) {
        if ($times_or_divide->[$i] eq '*') {
          $to_return *= &{$values->[$i]};
        }
        else {
          $to_return /= &{$values->[$i]};
        }
      }
      return $to_return;
    }
   }
 },
 value => { or=>['xnumber','variable_value']
 },
 variable_value => {and=>['variable'],
  evaluation => sub {my $variable = $_[0]->{variable};
    return sub {return $variables{$variable}}
   }
  },
 xnumber => {
   leaf => qr/[+\-]?(\d+(\.\d*)?|\.\d+)/,
   evaluation => sub{ my $number = 0 + $_[0];
     return sub {return $number} }
 },
);

my $program_parser = new Parse::Stallion({
 rules_to_set_up_hash=>\%program_rules, start_rule=>'program'});

my $fin_result =
  $program_parser->parse_and_evaluate({
   parse_this => 'x=1; while (x < 7) {print x; x = x + 2;};',
   trace=> 0
 });

print "Generated program\n";

&$fin_result;
is($big_output_string,'135','compiled and ran program');


print "\nAll done\n";


