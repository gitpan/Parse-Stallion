#!/usr/bin/perl
#Copyright 2008-9 Arthur S Goldstein
use Test::More tests => 48;
BEGIN { use_ok('Parse::Stallion') };
#use Data::Dumper;

my %parsing_rules_with_min_first = (
 start_expression => A(
  'parse_expression', L(qr/x*/), L(qr/\z/),
  E(sub {
#use Data::Dumper;print STDERR "in se is ".Dumper(\@_);
    return $_[0]->{parse_expression}})
 ),
 parse_expression => M(
   'pe', 'match_min_first', USE_STRING_MATCH()
 ),
 pe => L(
   qr/./
 ),
);

my %parsing_rules_without_min_first = (
 start_expression =>
  A('parse_expression', L(qr/x*/), L(qr/\z/),
  E(sub { return $_[0]->{parse_expression}})
 ),
 parse_expression => M(
   'pe', USE_STRING_MATCH
 ),
 pe => L(
   qr/./
 )
);

my $with_min_parser = new Parse::Stallion(
  \%parsing_rules_with_min_first,
  { start_rule => 'start_expression',
});

my $without_min_parser = new Parse::Stallion(
  \%parsing_rules_without_min_first,
  { start_rule => 'start_expression',
});

#my $result;

my ($result, $other) = $with_min_parser->parse_and_evaluate("qxxx");

#use Data::Dumper;print STDERR "parse trace is ".Dumper($other->{parse_trace})."\n";
is ($result,'q', 'min parser');

$result = $without_min_parser->parse_and_evaluate("qxxx");

is ($result,'qxxx', 'without min parser');

$result = $with_min_parser->parse_and_evaluate("xxx");

is ($result,'', 'no q min parser');

$result = $without_min_parser->parse_and_evaluate("xxx");

is ($result,'xxx', 'no q without min parser');

my %parsing_rules_with_match_once = (
 start_expression => A(M({f => qr/x/}, MATCH_ONCE()), {g => qr/x/})
);

my %parsing_rules_without_match_once = (
 start_expression => A(M({f => qr/x/}), {g => qr/x/})
);

my $with_match_parser = new Parse::Stallion(\%parsing_rules_with_match_once);
$result = $with_match_parser->parse_and_evaluate('xxx');
is ($result, undef, 'with match');

my $without_match_parser =
 new Parse::Stallion(\%parsing_rules_without_match_once);

$result = $without_match_parser->parse_and_evaluate('xxx');
is_deeply ($result, {f=> ['x','x'] , g=> 'x'}, 'without match');

my %another = (
 start_expression => A(M({f => qr/x/}, MATCH_ONCE(),
   'match_min_first', 3,5), {g => qr/y/})
);
my %anotherm = (
 start_expression => A(M({f => qr/x/},
   'match_min_first', 3,5), {g => qr/y/})
);


my $another_parser = new Parse::Stallion(\%another);
my $anotherm_parser = new Parse::Stallion(\%anotherm);

$result = $another_parser->parse_and_evaluate('xxxy');
is_deeply ($result, {f=> ['x','x','x'] , g=> 'y'}, 'another');
$result = $anotherm_parser->parse_and_evaluate('xxxy');
is_deeply ($result, {f=> ['x','x','x'] , g=> 'y'}, 'anotherm');

$result = $another_parser->parse_and_evaluate('xxxxy');
is ($result, undef, 'another 4 x');
$result = $anotherm_parser->parse_and_evaluate('xxxxy');
is_deeply ($result, {f=> ['x','x','x','x'] , g=> 'y'}, 'anotherm 4 x');

my %and_match = (
 start_expression => A(
     A({e=>qr/f/}, M({f => qr/x/}), MATCH_ONCE()),
    {k=>qr/x/})
);
my %and_no_match = (
 start_expression => A(A({e => qr/f/}, M({f => qr/x/})),{k =>qr/x/})
);

my $and_parser = new Parse::Stallion(\%and_match);
my $and_no_parser = new Parse::Stallion(\%and_no_match);
$result = $and_parser->parse_and_evaluate('fxxx');
is_deeply($result, undef, 'match once on and');
$result = $and_no_parser->parse_and_evaluate('fxxx');
is_deeply($result, {e=>'f',f=>['x','x'],k=>'x'}, 'no match once on and');

my %or_match = (
 start => A(O('case1', 'case2', MATCH_ONCE()), qr/x/),

 case1 => qr/xx/,

 case2 => qr/x/
);

my %or_no_match = (
 start => A(O('case1', 'case2'), qr/x/),

 case1 => qr/xx/,

 case2 => qr/x/
);

my $or_parser = new Parse::Stallion(\%or_match);
my $or_no_parser = new Parse::Stallion(\%or_no_match);

$result = $or_parser->parse_and_evaluate('xx');
is_deeply($result, undef, 'match once on or');
$result = $or_no_parser->parse_and_evaluate('xx');
is_deeply($result, {''=>'x', 'case2'=>'x'}, 'no match once on or');

my $mo_parser_1 = new Parse::Stallion(
   {rule1 => A(M(qr/t/), M(qr/t/), qr/u/)});

  my $mo_parser_2 = new Parse::Stallion(
   {rule2 => A(M(qr/t/, MATCH_ONCE()), M(qr/t/, MATCH_ONCE()), qr/u/)});

  my $mo_parser_3 = new Parse::Stallion(
   {rule2 => A(M(qr/t/, MATCH_ONCE()), M(qr/t/, MATCH_ONCE()),
    L(qr/u/, PB(sub {return 0})), MATCH_ONCE())});

my $pi = {};

$result = $mo_parser_1->parse_and_evaluate('ttttt',{parse_info => $pi});

is ($pi->{number_of_steps}, 157, 'match once steps');
#print "parse info steps 1 ".$pi->{number_of_steps}."\n";

$result = $mo_parser_2->parse_and_evaluate('ttttt',{parse_info => $pi});

#print "parse info steps 2 ".$pi->{number_of_steps}."\n";
is ($pi->{number_of_steps}, 15, 'match once steps');

$result = $mo_parser_3->parse_and_evaluate('ttttt',{parse_info => $pi});

#print "parse info steps 3 ".$pi->{number_of_steps}."\n";
is ($pi->{number_of_steps}, 27, 'match once steps');

my $g = {no_double_x => O(qr/x/, qr/xx/, qr/yy/, MATCH_ONCE())};
my $h = new Parse::Stallion($g);

$result = $h->parse_and_evaluate('xx');
is_deeply($result, undef, 'no double x on double x');
use Data::Dumper; print Dumper($result);
$result = $h->parse_and_evaluate('x');
is_deeply($result, 'x', 'no double x on single x');
use Data::Dumper; print Dumper($result);
$result = $h->parse_and_evaluate('yy');
is_deeply($result, 'yy', 'no double x on double y');

  my $parser = new Parse::Stallion({number => L(qr/(\d+)\;/,E(sub{$_[0]+1}))},
   {need_not_match_whole_string => 1});
  $input = '342;234;532;444;3;23;';
  $pi = {final_position => 0};
  while ($pi->{final_position} != length($input)) {
    push @results, $parser->parse_and_evaluate($input,
     {parse_info=> $pi, start_position => $pi->{final_position}});
  }
  # @results should contain (343, 235, 533, 445, 4, 24)
is_deeply(\@results, [343, 235, 533, 445, 4, 24]);

my @xresults;

$posinput = pos $input;
print "pre posinput $posinput\n";
pos $input = 0;
  while (my $result = $parser->parse_and_evaluate($input)) {
    push @xresults, $result;
  }
  # @xresults should contain (343, 235, 533, 445, 4, 24)
is_deeply(\@xresults, [343, 235, 533, 445, 4, 24]);

$posinput = pos $input;
print "posinput $posinput\n";


my $count;
my $mog;
my $mogrammar = {
  start => A('abc', qr/d/),
  abc => A(qr/a/, L(qr/b/,PB(sub{$count++;return;})), qr/c/,
   MATCH_ONCE(sub {return $mog}))
};
my $moparser = new Parse::Stallion($mogrammar);

$count = 0;
$mog = 0;

$moparser->parse_and_evaluate('abce');
is($count, 1, 'parsed fast but through pb');

$count = 0;
$mog = 1;
$moparser->parse_and_evaluate('abce');
is($count, 0, 'parsed fast skipping pb');

my $measure_grammar = {
  start => A('bb', 'cc', 'dd'),
  bb => qr/bb/,
  cc => qr/cc/,
  dd => qr/dd/,
};
my $measure_parser = new Parse::Stallion($measure_grammar);
$measure_parser->parse_and_evaluate('bbccee', {parse_info=>$pi});
is ($pi->{parse_succeeded}, 0, 'measured success');
is ($pi->{maximum_position}, 4, 'measured maximum position');
is ($pi->{maximum_position_rule}, 'cc', 'measured maximum position rule');
is ($pi->{final_position}, 0, 'measured final position');
is ($pi->{final_position_rule}, 'start', 'measured final position');

my $measure_pb_grammar = {
  start => A('bb', 'cc', qr/\n/, 'dd', 'ee'),
  bb => qr/bb/,
  cc => L(qr/cc/, PB(sub {return 1})),
  dd => qr/dd/,
  ee => qr/ee/,
};
my $ptt = [];
my $measure_pb_parser = new Parse::Stallion($measure_pb_grammar);
$measure_pb_parser->parse_and_evaluate("bbcc\nddff", {parse_info=>$pi,
 parse_trace => $ptt});
my ($max_line, $max_line_position) = LOCATION(\"bbcc\nddff",
 $pi->{maximum_position});
is ($pi->{parse_succeeded}, 0, 'measured pb success');
is ($pi->{maximum_position}, 7, 'measured pb maximum position');
is ($pi->{maximum_position_rule}, 'dd', 'measured pb maximum position rule');
is ($max_line, 2, 'measured pb maximum line rule');
is ($max_line_position, 3, 'measured pb maximum line position rule');
is ($pi->{final_position}, 2, 'measured pb final position');
is ($pi->{final_position_rule}, 'cc', 'measured pb final position');

my $pt = [];
$pi = {};
eval {$measure_pb_parser->parse_and_evaluate("bbcc\nddee", {parse_info=>$pi,
 parse_trace => $pt,
 max_steps =>4})};
is ($pi->{parse_succeeded}, undef, 'measured mspb success');
is ($pi->{maximum_position}, 7, 'measured mspb maximum position');
is ($pi->{maximum_position_rule}, 'dd', 'measured mspb maximum position rule');
is ($pi->{final_position}, 7, 'measured mspb final position');
is ($pi->{final_position_rule}, 'start', 'measured mspb final position');
#use Data::Dumper;print "pt is ".Dumper($pt)."\n";

my $line;
my $tab;
my $loc_grammar = {
  start =>
   A(qr/....../s,
    L(qr//, E(sub {
   ($line, $tab) = LOCATION($_[1]->{parse_this_ref},
    $_[1]->{current_node}->{position_when_entered})})),
    qr/.*/s)
};
my $loc_parser = new Parse::Stallion($loc_grammar);
$loc_parser->parse_and_evaluate('abcdefghi');
is ($line, 1, 'line loc 1');
is ($tab, 7, 'line tab 1');

$loc_parser->parse_and_evaluate("ab\nd\nfghi");
is ($line, 3, 'line loc 2');
is ($tab, 2, 'line tab 2');

  our %keywords = ('key1'=> 1, 'key2' => 1);
  my %grammar = (
   start => A('leaf', qr/\;/),
   leaf => L(
     qr/\w+/,
     E(sub {if ($keywords{$_[0]}) {return (undef, 1)} return $_[0]}),
   )
  );
  my $keyparser = new Parse::Stallion(\%grammar, {do_evaluation_in_parsing=>1});
  is ($keyparser->parse_and_evaluate('key1;'), undef, 'do eval key 1');
  is_deeply ($keyparser->parse_and_evaluate('key3;'), {''=>';',leaf=>'key3'},
   'do eval key 3');

print "\nAll done\n";


