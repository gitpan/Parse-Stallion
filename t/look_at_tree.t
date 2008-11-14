#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 10;
#use Data::Dumper;
BEGIN { use_ok('Parse::Stallion') };

my %calculator_rules = (
 start_expression => A(
   'expression', L(qr/\z/),
   E(sub {return $_[0]->{expression}})
  ),
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
   })
  ),
 term => A(
   'number', 
    M(A('times_or_divide', 'number')),
   E(sub {my $to_combine = $_[0]->{number};
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
   })
 ),
 number => L(
   qr/\s*[+\-]?(\d+(\.\d*)?|\.\d+)\s*/,
   E(sub{ return 0 + $_[0]; })
 ),
 plus_or_minus => L(
   qr/\s*[\-+]\s*/
 ),
 times_or_divide => L(
   qr/\s*[*\/]\s*/
 ),
);

my $calculator_parser = new Parse::Stallion({remove_white_space => 1,
  rules_to_set_up_hash => \%calculator_rules,
  start_rule => 'start_expression',});

my ($x,$result) =
 $calculator_parser->parse_and_evaluate({parse_this=>"7+4"});
#my $parsed_tree = $result->{tree};
#print STDERR "pt is ".Dumper($parsed_tree)."\n";
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($x, 11, "simple plus");

($x,$result) =
 $calculator_parser->parse_and_evaluate({parse_this=>"7*4"});
#$parsed_tree = $result->{tree};
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($x, 28, "simple multiply");

($x, $result) =
 $calculator_parser->parse_and_evaluate({parse_this=>"3+7*4" });
my $parsed_tree = $result->{tree};
#$result = $calculator_parser->do_tree_evaluation({tree=>$parsed_tree});
#print "Result is $result\n";
is ($x, 31, "simple plus and multiply");

my @bottom_up_names;
my @bottom_up_pvalues;
#$calculator_parser->remove_non_evaluated_nodes({tree=>$parsed_tree});
foreach my $node
 (Parse::Stallion::bottom_up_depth_first_search($parsed_tree)) {
  push @bottom_up_names, $node->{name};
  push @bottom_up_pvalues, $node->{parse_match};
}

#use Data::Dumper;print STDERR "bunames ".Dumper(\@bottom_up_names)."\n";
is_deeply(\@bottom_up_names,
[qw (number 
 term__XZ__1 term plus_or_minus number times_or_divide number 
 term__XZ__2 term__XZ__1 term expression__XZ__2
 expression__XZ__1 expression
 start_expression__XZ__1
 start_expression)]
, 'names in bottom up search');

#use Data::Dumper;print STDERR "buvalues ".Dumper(\@bottom_up_pvalues)."\n";
is_deeply(\@bottom_up_pvalues,
[  '3',
          undef,
          '3',
          '+',
          '7',
          '*',
          '4',
          '*4',
          '*4',
          '7*4',
          '+7*4',
          '+7*4',
          '3+7*4',
          '',
          '3+7*4'
]
, 'pvalues in bottom up search');

#print STDERR "bun ".join('.bun.', @bottom_up_names)."\n";

#print STDERR "bup ".join('.bup.', @bottom_up_pvalues)."\n";

#use Data::Dumper;print STDERR $parsed_tree->stringify({values=>['name','parse_match']});

my $pm = $parsed_tree->stringify({values=>['name','parse_match']});

my $pq = 
'start_expression|3+7*4|
 expression|3+7*4|
  term|3|
   number|3|
   term__XZ__1||
  expression__XZ__1|+7*4|
   expression__XZ__2|+7*4|
    plus_or_minus|+|
    term|7*4|
     number|7|
     term__XZ__1|*4|
      term__XZ__2|*4|
       times_or_divide|*|
       number|4|
 start_expression__XZ__1||
';

@x = split /\n/, $pm;
@y = split /\n/, $pq;
is_deeply(\@x,\@y, 'split pm pq');

is($parsed_tree->stringify({values=>['name','parse_match']}), $pq,
'stringify');

  my %no_eval_rules = (
   start_rule => A('term',
    M(A ({plus=>qr/\s*\+\s*/}, 'term'))),
   term => A({left=>'number'},
    M (A({times=>qr/\s*\*\s*/},
     {right=>'number'}))),
   number => qr/\s*\d*\s*/,
  );

  my $no_eval_parser = new Parse::Stallion({do_not_compress_eval => 0,
   rules_to_set_up_hash => \%no_eval_rules,
   });

  $result = $no_eval_parser->parse_and_evaluate({parse_this=>"7+4*8"});

  is_deeply($result,{                                  
          'plus' => [
                      '+'
                    ],
          'term' => [
                      '7',
                      {
                        'left' => '4',
                        'right' => [
                                     '8'
                                   ],
                        'times' => [
                                     '*'
                                   ]
                      }
                    ]
        },'no eval do not compress 0');

  my $dnce_no_eval_parser =
   new Parse::Stallion({do_not_compress_eval => 1,
   rules_to_set_up_hash => \%no_eval_rules,
   });

  $result = $dnce_no_eval_parser->parse_and_evaluate({parse_this=>"7+4*8"});

  is_deeply($result, {
          'plus' => [
                      '+'
                    ],
          'term' => [
                      {
                        'left' => '7'
                      },
                      {
                        'left' => '4',
                        'right' => [
                                     '8'
                                   ],
                        'times' => [
                                     '*'
                                   ]
                      }
                    ]
        }, 'no eval do not compress 1');
#use Data::Dumper; print STDERR "result is ".Dumper($result);

print "\nAll done\n";


