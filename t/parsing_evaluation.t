#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 23;
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

my $pe_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%parsing_rules,
  start_rule => 'start_expression',
});

my $result;
my $x;

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"abc middle def"})};

is ($result->{parse_succeeded},1, 'simple middle parse');

($x, $result) =
 $pe_parser->parse_and_evaluate({parse_this=>"a,bc middle de,f"});

is ($result->{parse_succeeded},1, 'two list middle parse');

($x, $result) =
 $pe_parser->parse_and_evaluate({parse_this=>"a,bc middle def"});

is ($result->{parse_succeeded},0, 'illegal middle parse');

#print STDERR "illmp ".$pe_parser->{parse_succeeded}."\n";

($x, $result) =
 $pe_parser->parse_and_evaluate({parse_this=>"a,bc,de,f"});
is ($result->{parse_succeeded},1, 'legal list div 4');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"a,bc,de,f,g"})};
is ($result->{parse_succeeded},0, 'illegal list div 4');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"odd"})};

is ($result->{parse_succeeded},1, 'odd leaf');


($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"even"})};

is ($result->{parse_succeeded},0, 'even leaf');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"theandabcdbff"})};

is ($result->{parse_succeeded},1, 'or and part');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"theandabcdbfg"})};

is ($result->{parse_succeeded},0, 'or fail and part');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"abbc"})};

is ($result->{parse_succeeded},1, 'or evaluation test');


($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"abbbc"})};

is ($result->{parse_succeeded},0, 'or fail evaluation test');


#print STDERR "dbforzero\n";

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"dbbf"})};

is ($result->{parse_succeeded},1, 'dbf or evaluation test');

#print STDERR "dbfor\n";

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"dbbbbf"})};

is ($result->{parse_succeeded},0, 'dbf or fail evaluation test');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>",,,,,"})};

is ($result->{parse_succeeded},1, 'multi comma test');

($x, $result) =
$pe_parser->parse_and_evaluate({parse_this=>",,,,"});

is ($result->{parse_succeeded},0, 'multi comma test parse succeed');

my $eval_pe_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%parsing_rules,
  start_rule => 'start_expression',
});


($x, $result) =
 $pe_parser->parse_and_evaluate({parse_this=>"a,bc middle de,f"});

my @trace;
foreach my $tr (@{$result->{parse_trace}}) {
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
          'string_value',
          0,
          'string_list',
          1,
          'string_list__XZ__1',
          1,
          'string_list__XZ__2',
          1,
          'comma',
          1,
          'string_list__XZ__2',
          2,
          'string_value',
          2,
          'string_list__XZ__2',
          4,
          'string_list__XZ__1',
          4,
          'string_list__XZ__2',
          4,
          'comma',
          4,
          'string_list__XZ__2',
          4,
          'string_list__XZ__1',
          4,
          'string_list',
          4,
          'same_sized_lists',
          4,
          'middle',
          4,
          'same_sized_lists',
          12,
          'string_list',
          12,
          'string_value',
          12,
          'string_list',
          14,
          'string_list__XZ__1',
          14,
          'string_list__XZ__2',
          14,
          'comma',
          14,
          'string_list__XZ__2',
          15,
          'string_value',
          15,
          'string_list__XZ__2',
          16,
          'string_list__XZ__1',
          16,
          'string_list__XZ__2',
          16,
          'comma',
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
          'start_expression__XZ__1',
          16,
          'start_expression',
          16
        ],
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

my $multi_test_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%multi_test_rules,
  start_rule => 'start_expression',
});

($x, $result)
 = $multi_test_parser->parse_and_evaluate({parse_this=>"a,bc middle de,f"});

#use Data::Dumper; print STDERR Dumper($result)."\n";
is ($result->{parse_succeeded}, 0, 'Always fail multiple rule');

#   $aa_parser = new Parse::Stallion({
#     rules_to_set_up_hash => {s => qr/aa/},
#     start_rule => 's',
#     end_of_parse_allowed => sub {return 1},
#   });
#   
#  my ($results, $info) = $aa_parser->parse_and_evaluate('aab'); 
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
#  $y = $aa_parser->parse_and_evaluate({parse_this => \$x});
#  is ($x, 'bb', 'change 2 aa parser');
#  is ($y, 'aa', 'change 2 y aa parser');

our $u = '';
my %qr_test_rules = (
 start_expression => A(
  qr/aa/, {y=>qr/ab/}, qr/\z/,
  E(sub {$u = $_[0]->{y}})
 ),
);

my $qr_test_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%qr_test_rules,
  start_rule => 'start_expression',
});

($x, $result)
 = $qr_test_parser->parse_and_evaluate("a,bc middle de,f");
is ($result->{parse_succeeded}, 0, 'Fail qr rule');

($x, $result)
 = $qr_test_parser->parse_and_evaluate("aaab");
is ($result->{parse_succeeded}, 1, 'Succeed qr rule');

is ($u, 'ab', 'ab matched and aliased');

my %x_test_rules = (
 start_expression => A('char', qr/.\z/)
 ,

 char => L(qr/./, E(sub {my ($leaf, $object_ref, $position) = @_; 
   pos $$object_ref = $position;
   if (!($$object_ref =~ /\GX\z/g)) {
     return (undef, 1)}
   return $leaf;})),

);

my $x_test_parser = new Parse::Stallion({
  do_evaluation_in_parsing => 1,
  rules_to_set_up_hash => \%x_test_rules,
});

($x, $result)
 = $x_test_parser->parse_and_evaluate("aX");
is ($result->{parse_succeeded}, 1, 'look ahead on x');

($x, $result)
 = $x_test_parser->parse_and_evaluate("aY");
is ($result->{parse_succeeded}, 0, 'look ahead on x not to parse');

print "\nAll done\n";


