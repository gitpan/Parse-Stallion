#!/usr/bin/perl
#Copyright 2008 Arthur S Goldstein
use Test::More tests => 2;
BEGIN { use_ok('Parse::Stallion') };

my %basic_plus_grammar = (
 start_expression => {
   and => ['number', {regex_match => qr/\s*[+]\s*/},
    ['number', 'right_number'], {regex_match => qr/\z/}],
   evaluation => sub {return $_[0]->{number} + $_[0]->{right_number},
  }
 },
 number => {
   rule_type => 'leaf',
   regex_match => qr/\s*[+\-]?(\d+(\.\d*)?|\.\d+)\s*/,
   evaluation => sub{ return 0 + $_[0]; }
 }
);

my $basic_plus_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%basic_plus_grammar,
  start_rule => 'start_expression',});

my $result =
 $basic_plus_parser->parse_and_evaluate({parse_this=>"7+4"});
print "Result is $result\n";
is ($result, 11, "simple plus");

print "\nAll done\n";


