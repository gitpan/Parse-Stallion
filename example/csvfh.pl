#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Parse::Stallion::CSVFH;

my $result;

my $file_handle;
open $file_handle, "<", "csvfh.data";

$result = Parse::Stallion::CSVFH::read_in_file_handle(
 {file_handle => $file_handle}
);

print "header in ".join("..",@{$result->{header}})."\n\n";
foreach my $i (0..$#{$result->{records}}) {
  print "records $i in ".join("..",@{$result->{records}->[$i]})."\n\n";
}


print "\nAll done\n";


