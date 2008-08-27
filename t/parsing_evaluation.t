#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 25;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules = (
 start_expression => {
  and => ['parse_expression', {leaf => qr/\z/}]
 },
 parse_expression => {
   or=> ['same_sized_lists','list_div_four', 'odd_leaf',
     'and_part_or_test', 'or_test', 'multi_test'],
 },
 list_div_four => {
   and => ['string_list'],
   evaluation => sub {
     if (@{$_[0]->{string_list}} % 4 != 0) {
       return (undef, 1);
     }
     return $_[0]->{string_list};
   }
 },
 same_sized_lists => {
   and => [['string_list', 'list_one'], 'middle', ['string_list','list_two']],
   evaluation => sub {
    if (scalar(@{$_[0]->{list_one}})
    != scalar(@{$_[0]->{list_two}})) {
     return (undef, 1);
     }
   }
  },
 middle => {
  leaf=>qr/\s+middle\s+/,
 },
 string_value => {leaf=> qr/\w+/},
 string_list => {
   and => ['string_value', {multiple=>{and=>['comma','string_value']}}],
   evaluation => sub {
    return $_[0]->{string_value}}
  },
 comma => {leaf=>qr/\,/},
 odd_leaf => {leaf=>qr/\w+/,e=>sub{
   $_ = shift;
   if ($_ ne 'odd') {return (0,1)} return $_}},
 and_part_or_test => {and=>['theand', 'abc','dbf']},
 or_test => {or=>['abc','dbf'],
   e=>sub {
#print STDERR "or_test\n";
#print STDERR Dumper(\@_);
   my $or_in = shift;
   ($_) = values %$or_in;
#print STDERR "looking at ".$_."\n";
   if (/bbb/) {return (0,1)} return $_}
 },
 abc => {leaf=>qr/a+b*c+/},
 dbf => {leaf=>qr/d+b*f+/},
 theand => {leaf=>qr/theand/},
 multi_test => {multiple=>'comma',minimum_child_count=>2,
  e=> sub {
#print STDERR Dumper(\@_);
    if ($#{$_[0]->{comma}} != 4) {
      return (0,1);
    }
    return (\@_,0);
  }
  },
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

is ($result->{parse_failed},0, 'simple middle parse');

($x, $result) =
 $pe_parser->parse_and_evaluate({parse_this=>"a,bc middle de,f"});

is ($result->{parse_failed},0, 'two list middle parse');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"a,bc middle def"})};

is ($result->{parse_failed},1, 'illegal middle parse');

#print STDERR "illmp ".$pe_parser->{parse_succeeded}."\n";

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"a,bc,de,f"})};
is ($result->{parse_failed},0, 'legal list div 4');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"a,bc,de,f,g"})};
is ($result->{parse_failed},1, 'illegal list div 4');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"odd"})};

is ($result->{parse_failed},0, 'odd leaf');


($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"even"})};

is ($result->{parse_failed},1, 'even leaf');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"theandabcdbff"})};

is ($result->{parse_failed},0, 'or and part');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"theandabcdbfg"})};

is ($result->{parse_failed},1, 'or fail and part');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"abbc"})};

is ($result->{parse_failed},0, 'or evaluation test');


($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"abbbc"})};

is ($result->{parse_failed},1, 'or fail evaluation test');


#print STDERR "dbforzero\n";

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"dbbf"})};

is ($result->{parse_failed},0, 'dbf or evaluation test');

#print STDERR "dbfor\n";

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>"dbbbbf"})};

is ($result->{parse_failed},1, 'dbf or fail evaluation test');

($x, $result) =
 eval{$pe_parser->parse_and_evaluate({parse_this=>",,,,,"})};

is ($result->{parse_failed},0, 'multi comma test');

($x, $result) =
$pe_parser->parse_and_evaluate({parse_this=>",,,,"});

is ($result->{parse_failed},1, 'multi comma test parse succeed');

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
#use Data::Dumper;print STDERR "trace is ".Dumper(\@trace)."\n";
is_deeply
(\@trace,
[                                  
          'start_expression',
          'a,bc middle de,f',
          'parse_expression',
          'a,bc middle de,f',
          'same_sized_lists',
          'a,bc middle de,f',
          'string_list',
          'a,bc middle de,f',
          'string_value',
          'a,bc middle de,f',
          'string_list',
          ',bc middle de,f',
          'string_list__XZ__1',
          ',bc middle de,f',
          'string_list__XZ__1__XZ__2',
          ',bc middle de,f',
          'comma',
          ',bc middle de,f',
          'string_list__XZ__1__XZ__2',
          'bc middle de,f',
          'string_value',
          'bc middle de,f',
          'string_list__XZ__1__XZ__2',
          ' middle de,f',
          'string_list__XZ__1__XZ__2',
          ' middle de,f',
          'string_list__XZ__1',
          ' middle de,f',
          'string_list__XZ__1__XZ__2',
          ' middle de,f',
          'comma',
          ' middle de,f',
          'string_list__XZ__1__XZ__2',
          ' middle de,f',
          'string_list__XZ__1__XZ__2',
          ' middle de,f',
          'string_list__XZ__1',
          ' middle de,f',
          'string_list',
          ' middle de,f',
          'string_list',
          ' middle de,f',
          'same_sized_lists',
          ' middle de,f',
          'middle',
          ' middle de,f',
          'same_sized_lists',
          'de,f',
          'string_list',
          'de,f',
          'string_value',
          'de,f',
          'string_list',
          ',f',
          'string_list__XZ__1',
          ',f',
          'string_list__XZ__1__XZ__2',
          ',f',
          'comma',
          ',f',
          'string_list__XZ__1__XZ__2',
          'f',
          'string_value',
          'f',
          'string_list__XZ__1__XZ__2',
          '',
          'string_list__XZ__1__XZ__2',
          '',
          'string_list__XZ__1',
          '',
          'string_list__XZ__1__XZ__2',
          '',
          'comma',
          '',
          'string_list__XZ__1__XZ__2',
          '',
          'string_list__XZ__1__XZ__2',
          '',
          'string_list__XZ__1',
          '',
          'string_list',
          '',
          'string_list',
          '',
          'same_sized_lists',
          '',
          'same_sized_lists',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'parse_expression',
          '',
          'start_expression',
          '',
          'start_expression__XZ__0',
          '',
          'start_expression',
          '',
          'start_expression',
          ''
        ],
'trace');

my %multi_test_rules = (
 start_expression => {
  and => ['parse_expression', 'chars', {leaf => qr/\z/}]
 },

 parse_expression => {
   multiple => 'somerepeat',
   e => sub {return (undef, 1)}
 },

 somerepeat => {
   l => qr/./s
 },

 chars => {
   l => qr/.*/s
 },

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

   $aa_parser = new Parse::Stallion({
     rules_to_set_up_hash => {s => {l => qr/aa/}},
     start_rule => 's',
     end_of_parse_allowed => sub {return 1},
   });
   
  my ($results, $info) = $aa_parser->parse_and_evaluate('aab'); 

is ($info->{unparsed}, 'b', 'aa parser b');

  $x = 'aabb';
  my $y = $aa_parser->parse_and_evaluate($x);
  is ($x, 'aabb', 'no change aa parser');
  is ($y, 'aa', 'no change y aa parser');
  $y = $aa_parser->parse_and_evaluate(\$x);
  is ($x, 'bb', 'change aa parser');
  is ($y, 'aa', 'change y aa parser');
  $x = 'aabb';
  $y = $aa_parser->parse_and_evaluate({parse_this => \$x});
  is ($x, 'bb', 'change 2 aa parser');
  is ($y, 'aa', 'change 2 y aa parser');

print "\nAll done\n";


