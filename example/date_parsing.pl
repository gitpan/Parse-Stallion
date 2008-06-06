#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Parse::Stallion;
use Time::Local;

my %rule;
$rule{start_date} = { rule_type => 'and',
  composed_of => ['parsed_date', 'end_of_string'],
  evaluation => sub {
    my $seconds_since_epoch = $_[0]->{parsed_date};
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
$rule{parsed_date} = { rule_type => 'or',
  any_one_of => ['date', 'date_operation'],
};
$rule{date_operation} = { rule_type => 'or',
  any_one_of => ['add_time', 'subtract_time'],
};
$rule{add_time} = { rule_type => 'and',
  composed_of => ['date', 'plus', 'time'],
  evaluation => sub {return $_[0]->{date} + $_[0]->{time}}
};
$rule{subtract_time} = { rule_type => 'and',
  composed_of => ['date', 'minus', 'time'],
  evaluation => sub {
   return $_[0]->{date} - $_[0]->{time}}
};
$rule{date} = { rule_type => 'or',
  any_one_of => ['standard_date', 'special_date']
};
$rule{end_of_string} = {rule_type => 'leaf',
  regex_match => qr/\z/,
};
$rule{plus} = { rule_type => 'leaf',
  regex_match => qr/\s*\+\s*/,
};
$rule{minus} = { rule_type => 'leaf',
  regex_match => qr/\s*\-\s*/,
};
$rule{standard_date} = { rule_type => 'leaf',
  regex_match => qr(\d+\/\d+\/\d+),
  evaluation => sub {my $date = $_[0];
    $date =~ /(\d+)\/(\d+)\/(\d+)/;
    my $month = $1 -1;
    my $mday = $2;
    my $year = $3;
    return timegm(0,0,0,$mday, $month, $year);
  },
};
$rule{special_date} = { rule_type => 'leaf',
  regex_match => qr/now/i,
  evaluation => sub {return time;},
};
$rule{time} = { rule_type => 'or',
  any_one_of => ['just_time', 'just_time_plus_list', 'just_time_minus_list']
};
$rule{just_time_plus_list} = { rule_type => 'and',
  composed_of => ['just_time', 'plus', 'time'],
  evaluation => sub {return $_[0]->{just_time} + $_[0]->{time}}
};
$rule{just_time_minus_list} = { rule_type => 'and',
  composed_of => ['just_time', 'minus', 'time'],
  evaluation => sub {return $_[0]->{just_time} - $_[2]->{time}}
};
$rule{just_time} = { rule_type => 'leaf',
  regex_match => qr(\d+\s*[hdms])i,
  evaluation => sub {
    my $to_match = $_[0];
    $to_match =~ /(\d+)\s*([hdms])/i;
    my $number = $1;
    my $unit = $2;
    if (lc $unit eq 'h') {
      return $1 * 60 * 60;
    }
    if (lc $unit eq 'd') {
      return $1 * 24 * 60 * 60;
    }
    if (lc $unit eq 's') {
      return $1;
    }
    if (lc $unit eq 'm') {
      return $1 * 60;
    }
  }
};

my $date_parser = new Parse::Stallion({
  rules_to_set_up_hash => \%rule,
  start_rule => 'start_date',
});

$result = $date_parser->parse_and_evaluate({parse_this=>"now"});
print "now is $result\n";

$result = $date_parser->parse_and_evaluate({parse_this=>"now - 30s"});
print "now minus 30 seconds is $result\n";

$result = $date_parser->parse_and_evaluate({parse_this=>"now + 70h"});
print "now plus 70 hours is $result\n";

$result = $date_parser->parse_and_evaluate({parse_this=>"now + 70H + 45s"});
print "now plus 70 hours and 45 seconds is $result\n";

$result = $date_parser->parse_and_evaluate(
 {parse_this=>"6/6/2008 + 2d + 3h"});
print "2 days and 3 hours after 6/6/2008 is $result\n";

print "\nAll done\n";


