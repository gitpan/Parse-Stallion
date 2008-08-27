#!/usr/bin/perl
#Copyright 2007 Arthur S Goldstein
use Test::More tests => 9;
BEGIN { use_ok('Parse::Stallion') };
use Time::Local;

my %rule;
$rule{start_date} = {
  and => ['parsed_date'],
  evaluation => sub {my $seconds_since_epoch = $_[0]->{parsed_date};
    my ($seconds, $minutes, $hour, $mday, $month, $year) =
     gmtime($seconds_since_epoch);
    $month++;  #Have January be 01 instead of 00.
    if ($month < 10) { $month = '0'.$month;};
    if ($mday < 10) { $mday = '0'.$mday;};
    if ($seconds < 10) { $seconds = '0'.$seconds;};
    if ($minutes < 10) { $minutes = '0'.$minutes;};
    if ($hour < 10) { $hour = '0'.$hour;};
    return (1900+$year).$month.$mday.$hour.$minutes.$seconds;
  }
};
$rule{parsed_date} = {
  or => ['date', 'date_operation'],
};
$rule{date_operation} = {
  or => ['add_time', 'subtract_time'],
};
$rule{add_time} = {
  and => ['date', 'plus', 'time'],
  evaluation => sub {return $_[0]->{date} + $_[0]->{time}}
};
$rule{subtract_time} = {
  and => ['date', 'minus', 'time'],
  evaluation => sub {return $_[0]->{date} - $_[0]->{time}}
};
$rule{date} = {
  or => ['standard_date', 'special_date']
};
$rule{plus} = {
  regex_match => qr/\s*\+\s*/,
};
$rule{minus} = {
  regex_match => qr/\s*\-\s*/,
};
$rule{standard_date} = {
  regex_match => qr(\d+\/\d+\/\d+),
  evaluation => sub {my $date = $_[0];
    $date =~ /(\d+)\/(\d+)\/(\d+)/;
    my $month = $1 -1;
    my $mday = $2;
    my $year = $3;
    return timegm(0,0,0,$mday, $month, $year);
  },
};
$rule{special_date} = {
  regex_match => qr/now/i,
  evaluation => sub {return timegm(24,40,0,5, 7, 2007);}
};
$rule{time} = {
  or => ['just_time', 'just_time_plus_list', 'just_time_minus_list']
};
$rule{just_time_plus_list} = {
  and => ['just_time', 'plus', 'time'],
  evaluation => sub {return $_[0]->{just_time} + $_[0]->{time}}
};
$rule{just_time_minus_list} = {
  and => ['just_time', 'minus', 'time'],
  evaluation => sub {return $_[0]->{just_time} - $_[2]->{time}}
};
$rule{just_time} = {
  regex_match => qr(\d+\s*[hdms]),
  evaluation => sub {
    my $to_match = $_[0];
    $to_match =~ /(\d+)\s*([hdms])/;
    my $number = $1;
    my $unit = $2;
    if ($unit eq 'h') {
      return $1 * 60 * 60;
    }
    if ($unit eq 'd') {
      return $1 * 24 * 60 * 60;
    }
    if ($unit eq 's') {
      return $1;
    }
    if ($unit eq 'm') {
      return $1 * 60;
    }
  }
};

my $date_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%rule,
  start_rule => 'start_date'});

my $parsed_tree;
my $result =
 $date_parser->parse_and_evaluate("now");
print "Result is $result\n";
is ($result, 20070805004024, "now set up with hard coded date");

$result =
 $date_parser->parse_and_evaluate("now - 10s");
print "NResult minus 10 is $result\n";
is ($result, 20070805004014, "10 seconds before hard coded date");

$result =
 $date_parser->parse_and_evaluate("now + 70h");
print "NResult plus 70 hours is $result\n";
is ($result, 20070807224024, "70 hours after hard coded date");

$result =
 $date_parser->parse_and_evaluate("now + 70h +3s");
print "NResult plus 70 hours plus 3 sec is $result\n";
is ($result, 20070807224027, "70 hours 3 secs after hard coded date");

$result =
 $date_parser->parse_and_evaluate("3/22/2007");
print "NResult march 22 2007is $result\n";
is ($result, 20070322000000, "3/22/2007");

$result =
 $date_parser->parse_and_evaluate("3/22/2007 + 5d");
print "NResult march 22 2007 plus 5 days is $result\n";
is ($result, 20070327000000, "3/22/2007 and 5 days");

$result =
 $date_parser->parse_and_evaluate("2/22/2008 + 7d");
print "NResult feb 22 2008 plus 7 days is $result\n";
is ($result, 20080229000000, "2/22/2008 and 7 days");

$result =
 $date_parser->parse_and_evaluate("2/22/2007 + 7d");
print "NResult feb 22 2007 plus 7 days is $result\n";
is ($result, 20070301000000, "2/22/2008 and 7 days");



print "\nAll done\n";


