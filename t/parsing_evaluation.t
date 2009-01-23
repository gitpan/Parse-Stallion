#!/usr/bin/perl
#Copyright 2007-9 Arthur S Goldstein
use Test::More tests => 32;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules = (
 start_expression => A(
  'parse_expression', L(qr/\z/)
 ),
 parse_expression => O(
   'same_sized_lists','list_div_four', 'odd_leaf',
     'and_part_or_test', 'or_test', 'multi_test'),
 list_div_four => A(
   'string_list',
   E(sub {
     if (@{$_[0]->{string_list}} % 4 != 0) {
       return (undef, 1);
     }
     return $_[0]->{string_list};
   })
 ),
 same_sized_lists => A(
   {list_one=>'string_list'}, 'middle', {list_two=>'string_list'},
   E(sub {
    if (scalar(@{$_[0]->{list_one}})
    != scalar(@{$_[0]->{list_two}})) {
     return (undef, 1);
     }
   })
  ),
 middle => L(
  qr/\s+middle\s+/
 ),
 string_value => L(qr/\w+/),
 string_list => A(
   'string_value', M(A('comma','string_value')),
   E(sub {
    return $_[0]->{string_value}})
  ),
 comma => L(qr/\,/),
 odd_leaf => L(qr/\w+/,E(sub{
   $_ = shift;
   if ($_ ne 'odd') {return (0,1)} return $_})),
 and_part_or_test => A('theand', 'abc','dbf'),
 or_test => O('abc','dbf',
   E(sub {
#print STDERR "or_test\n";
#print STDERR Dumper(\@_);
   my $or_in = shift;
   ($_) = values %$or_in;
#print STDERR "looking at ".$_."\n";
   if (/bbb/) {return (0,1)} return $_})
 ),
 abc => L(qr/a+b*c+/),
 dbf => L(qr/d+b*f+/),
 theand => L(qr/theand/),
 multi_test => M('comma',2,0,
  E(sub {
#use Data::Dumper;print STDERR "mt has ".Dumper(\@_);
    if ($#{$_[0]->{comma}} != 4) {
      return (0,1);
    }
    return (\@_,0);
  })
  ),
);

my $pe_parser = new Parse::Stallion(
  \%parsing_rules,
  {
  do_evaluation_in_parsing => 1,
  start_rule => 'start_expression',
});

my $result;
my $x;

$x =
 eval{$pe_parser->parse_and_evaluate("abc middle def", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'simple middle parse');

$x =
 $pe_parser->parse_and_evaluate("a,bc middle de,f", {parse_info=>$result={}});

is ($result->{parse_succeeded},1, 'two list middle parse');

$x =
 $pe_parser->parse_and_evaluate("a,bc middle def", {parse_info=>$result={}});

is ($result->{parse_succeeded},0, 'illegal middle parse');

#print STDERR "illmp ".$pe_parser->{parse_succeeded}."\n";

$x =
 $pe_parser->parse_and_evaluate("a,bc,de,f", {parse_info=>$result={}});
is ($result->{parse_succeeded},1, 'legal list div 4');

$x =
 eval{$pe_parser->parse_and_evaluate("a,bc,de,f,g", {parse_info=>$result={}})};
is ($result->{parse_succeeded},0, 'illegal list div 4');

$x = eval{$pe_parser->parse_and_evaluate("odd", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'odd leaf');


$x = eval{$pe_parser->parse_and_evaluate("even", {parse_info=>$result={}})};

is ($result->{parse_succeeded},0, 'even leaf');

$x = eval{$pe_parser->parse_and_evaluate("theandabcdbff", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'or and part');

$x = eval{$pe_parser->parse_and_evaluate("theandabcdbfg", {parse_info=>$result={}})};

is ($result->{parse_succeeded},0, 'or fail and part');

$x = eval{$pe_parser->parse_and_evaluate("abbc", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'or evaluation test');


$x = eval{$pe_parser->parse_and_evaluate("abbbc", {parse_info=>$result={}})};

is ($result->{parse_succeeded},0, 'or fail evaluation test');


#print STDERR "dbforzero\n";

$x = eval{$pe_parser->parse_and_evaluate("dbbf", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'dbf or evaluation test');

#print STDERR "dbfor\n";

$x = eval{$pe_parser->parse_and_evaluate("dbbbbf", {parse_info=>$result={}})};

is ($result->{parse_succeeded},0, 'dbf or fail evaluation test');

$x = eval{$pe_parser->parse_and_evaluate(",,,,,", {parse_info=>$result={}})};

is ($result->{parse_succeeded},1, 'multi comma test');

$x = $pe_parser->parse_and_evaluate(",,,,", {parse_info=>$result={}});

is ($result->{parse_succeeded},0, 'multi comma test parse succeed');

my $eval_pe_parser = new Parse::Stallion(
  \%parsing_rules,
  {
  do_evaluation_in_parsing => 1,
  start_rule => 'start_expression',
});


my @pt;
$x = $pe_parser->parse_and_evaluate("a,bc middle de,f", {parse_info=>$result={},
 parse_trace => \@pt});

my @trace;
foreach my $tr (@pt) {
  push @trace, $tr->{rule_name}, $tr->{value};
}
#use Data::Dumper;print STDERR "pt is ".Dumper($result->{parse_trace})."\n";
#use Data::Dumper;print STDERR "trace is ".Dumper(\@trace)."\n";
is_deeply
(\@trace,
[                  
          'start_expression',
          0,
          'parse_expression',
          0,
          'same_sized_lists',
          0,
          'string_list',
          0,
          'string_list',
          1,
          'string_list__XZ__1',
          1,
          'string_list__XZ__2',
          1,
          'string_list__XZ__2',
          2,
          'string_list__XZ__2',
          4,
          'string_list__XZ__1',
          4,
          'string_list__XZ__2',
          4,
          'string_list__XZ__2',
          4,
          'string_list__XZ__1',
          4,
          'string_list',
          4,
          'same_sized_lists',
          4,
          'same_sized_lists',
          12,
          'string_list',
          12,
          'string_list',
          14,
          'string_list__XZ__1',
          14,
          'string_list__XZ__2',
          14,
          'string_list__XZ__2',
          15,
          'string_list__XZ__2',
          16,
          'string_list__XZ__1',
          16,
          'string_list__XZ__2',
          16,
          'string_list__XZ__2',
          16,
          'string_list__XZ__1',
          16,
          'string_list',
          16,
          'same_sized_lists',
          16,
          'parse_expression',
          16,
          'start_expression',
          16,
          'start_expression',
          16
        ]
,'trace test');

my %multi_test_rules = (
 start_expression => A(
  'parse_expression', 'chars', L(qr/\z/))
 ,

 parse_expression => M(
   'somerepeat',
   E(sub {return (undef, 1)})
 ),

 somerepeat => L(
   qr/./s
 ),

 chars => L(
   qr/.*/s
 ),

);

my $multi_test_parser = new Parse::Stallion(
  \%multi_test_rules,
  {
  do_evaluation_in_parsing => 1,
  start_rule => 'start_expression',
});

$x = $multi_test_parser->parse_and_evaluate("a,bc middle de,f", {parse_info=>$result={}});

#use Data::Dumper; print STDERR Dumper($result)."\n";
is ($result->{parse_succeeded}, 0, 'Always fail multiple rule');

#   $aa_parser = new Parse::Stallion({
#     rules_to_set_up_hash => {s => qr/aa/},
#     start_rule => 's',
#     end_of_parse_allowed => sub {return 1},
#   });
#   
#  my ($results, $info) = $aa_parser->parse_and_evaluate('aab', {parse_info=>$result={}}); 
#
#is ($info->{unparsed}, 'b', 'aa parser b');
#
#  $x = 'aabb';
#  my $y = $aa_parser->parse_and_evaluate($x);
#  is ($x, 'aabb', 'no change aa parser');
#  is ($y, 'aa', 'no change y aa parser');
#  $y = $aa_parser->parse_and_evaluate(\$x);
#  is ($x, 'bb', 'change aa parser');
#  is ($y, 'aa', 'change y aa parser');
#  $x = 'aabb';
#  $y = $aa_parser->parse_and_evaluate(\$x);
#  is ($x, 'bb', 'change 2 aa parser');
#  is ($y, 'aa', 'change 2 y aa parser');

our $u = '';
my %qr_test_rules = (
 start_expression => A(
  qr/aa/, {y=>qr/ab/}, qr/\z/,
  E(sub {$u = $_[0]->{y}})
 ),
);

my $qr_test_parser = new Parse::Stallion(
  \%qr_test_rules,
  { start_rule => 'start_expression',
});

$x
 = $qr_test_parser->parse_and_evaluate("a,bc middle de,f", {parse_info=>$result={}});
is ($result->{parse_succeeded}, 0, 'Fail qr rule');

$x
 = $qr_test_parser->parse_and_evaluate("aaab", {parse_info=>$result={}});
is ($result->{parse_succeeded}, 1, 'Succeed qr rule');

is ($u, 'ab', 'ab matched and aliased');

my %x_test_rules = (
 start_expression => A('char', qr/.\z/)
 ,

 char => L(qr/./, E(sub {my ($leaf, $parameters) = @_;
   my $object_ref = $parameters->{parse_this_ref};
   my $position = $parameters->{current_value};
   pos $$object_ref = $position;
   if (!($$object_ref =~ /\GX\z/g)) {
     return (undef, 1)}
   return $leaf;})),

);

my $x_test_parser = new Parse::Stallion(
  \%x_test_rules,
  {
  do_evaluation_in_parsing => 1
});

$x
 = $x_test_parser->parse_and_evaluate("aX", {parse_info=>$result={}});
is ($result->{parse_succeeded}, 1, 'look ahead on x');

$x
 = $x_test_parser->parse_and_evaluate("aY", {parse_info=>$result={}});
is ($result->{parse_succeeded}, 0, 'look ahead on x not to parse');

my %bad_and = (
  start => AND(qr/a/, PF(sub {return (1, undef, $_[0]->{current_value})}))
);

eval {my $bad_and_parser = new Parse::Stallion(\%bad_and);};
like ($@, qr/Parse forward in rule/, 'parse forward not in leaf');

my %two_pf_and = (
  start => AND(qr/a/,
    L(PF(sub {my $parameters = shift;
     my $node_hash = $parameters->{node_hash};
     my $current_value = $parameters->{current_value};
     $node_hash->{x} = 2;
     return 1, undef, $current_value;
    })),
    {f => L(PF(sub {my $parameters = shift;
     my $node_hash = $parameters->{node_hash};
     my $current_value = $parameters->{current_value};
     return 1, $node_hash->{x}+1, $current_value;
    }))},
    E(sub {return $_[0]->{f}}),
    ),
);

my $two_pf_and_parser = new Parse::Stallion(\%two_pf_and);

$result = $two_pf_and_parser->parse_and_evaluate('a');

is ($result, 3, 'Two pf and');

our $latest_node_hash;
our $latest_parse_hash;
sub increment_hashes {
#use Data::Dumper;print STDERR "ihp ".Dumper(\@_)."\n";
  my $parameters = shift;
  my $current_value = $parameters->{current_value};
  my $node_hash = $parameters->{node_hash};
  my $parse_hash = $parameters->{parse_hash};
  $latest_node_hash = ++$node_hash->{x};
  $latest_parse_hash = ++$parse_hash->{x};
  return 1, undef, $current_value;
}

my %check_hashes = (
  start => A('other', 'deeper', qr/a/, L(PF(\&increment_hashes)),
   L(PF(\&increment_hashes))),
  other => L(PF(\&increment_hashes)),
  deeper => A('other')
);

my $check_hashes_parser = new Parse::Stallion(\%check_hashes);

$result = $check_hashes_parser->parse_and_evaluate('a');

is ($latest_node_hash, 3, 'check hashes node');
is ($latest_parse_hash, 4, 'check hashes parse');

my %bad_leaf = (
  start => L(qr/a/, PF(sub {return (1, undef, $_[0]->{current_value})}),
   PF(sub {return 1}))
);

eval {my $bad_leaf_parser = new Parse::Stallion(\%bad_leaf);};
like ($@, qr/Rule start has more than one/, '2 parse forwards in leaf');

our $stored_parameters;
my %eval_arg_rules = (
  start => A(qr/./, qr/./, E(
   sub {
      $stored_parameters = \@_;
#use Data::Dumper;print STDERR Dumper(\@_)."\n";
    }
   ))
);

my $eval_arg_parser = new Parse::Stallion(\%eval_arg_rules);

$result = $eval_arg_parser->parse_and_evaluate('ab');

is_deeply($stored_parameters,
[                           
          {
            '' => [
                    'a',
                    'b'
                  ]
          },
          {
            'parameters' => {'' => ['a','b']},
            'node_parse_match' => 'ab',
            'current_value' => 0,
            'node_hash' => {},
            'parse_this_ref' => \'ab',
            'parse_hash' => {}
          }
        ]
, 'params to eval');

my %evals_arg_rules = (
  start => A(qr/./, qr/./, E(
   sub {
      $stored_parameters = \@_;
#use Data::Dumper;print STDERR Dumper(\@_)."\n";
    }
   ), USE_PARSE_MATCH)
);

my $evals_arg_parser = new Parse::Stallion(\%evals_arg_rules);

$result = $evals_arg_parser->parse_and_evaluate('ab');

is_deeply(
$stored_parameters,
[
          'ab',
          {
            'parameters' => {
                              '' => [
                                      'a',
                                      'b'
                                    ]
                            },
            'node_parse_match' => 'ab',
            'current_value' => 0,
            'node_hash' => {},
            'parse_this_ref' => \'ab',
            'parse_hash' => {}
          }
        ]
, 'params to evals');

our $pb_stored_parameters;
our $pf_stored_parameters;
my %pf_arg_rules = (
  start => A(qr/./,
   L(PF(
   sub {
      $_[0]->{node_hash}->{xx} = 1;
      return (1, 'nn', $_[0]->{current_value});
    }
   )),
   L(PF(
   sub {
#use Data::Dumper;print STDERR Dumper(\@_)." pf \n";
      return (1, 'mmm', $_[0]->{current_value});
    }
   ),
   PB(
   sub {
#use Data::Dumper;print STDERR Dumper(\@_)." pb \n";
      return;
    }
   )),
   L(PF(
   sub {
#use Data::Dumper;print STDERR Dumper(\@_)." pf2 \n";
      return (1, ['www'], $_[0]->{current_value});
    }
   ),
   PB(
   sub {
#use Data::Dumper;print STDERR Dumper(\@_)." pb2 \n";
      return;
    }
   )),
   L(PF(
   sub {
      $pf_stored_parameters = \@_;
#use Data::Dumper;print STDERR Dumper(\@_)." pf3 \n";
is_deeply($pf_stored_parameters,
[
          {
            'parameters' => {
                              '' => [
                                      'a',
                                      'nn',
                                      'mmm',
                                      [
                                        'www'
                                      ]
                                    ]
                            },
            'leaf_rule_info' => {},
            'node_parse_match' => 'annmmm',
            'current_value' => 1,
            'node_hash' => {
                             'xx' => 1
                           },
            'parse_this_ref' => \'ab',
            'parse_hash' => {}
          }
        ]
, 'parse forward parameters with eval');
      return (1, 'uuu', $_[0]->{current_value});
    }
   ),
   PB(
   sub {
      $pb_stored_parameters = \@_;
#use Data::Dumper;print STDERR Dumper(\@_)." pb3 \n";
is_deeply($pb_stored_parameters,
[
          {
            'node_hash' => {
                             'xx' => 1
                           },
            'match' => 'uuu',
            'parse_this_ref' => \'ab',
            'parse_hash' => {},
            'parameters' => {
                              '' => [
                                      'a',
                                      'nn',
                                      'mmm',
                                      [
                                        'www'
                                      ]
                                    ]
                            },
            'leaf_rule_info' => undef,
            'node_parse_match' => 'annmmm',
            'current_value' => 1,
            'value_when_entered' => 1
          }
        ]
, 'parse backtrack parameters with eval');
      return;
    }
   )),
    qr/x/)
);

my $pf_arg_parser = new Parse::Stallion(\%pf_arg_rules,
 {do_evaluation_in_parsing => 1});

$result = $pf_arg_parser->parse_and_evaluate('ab');



#5 pf with eval in parsing (vs without #5b)

print "\nAll done\n";


