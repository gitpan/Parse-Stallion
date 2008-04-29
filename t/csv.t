#!/usr/bin/perl
#Copyright 2007-8 Arthur S Goldstein
use Test::More tests => 6;
BEGIN { use_ok('Parse::Stallion::CSV') };
BEGIN { use_ok('Parse::Stallion::CSVFH') };

my $csv_stallion = new Parse::Stallion::CSV;
my $result;

my $file =<<EOL;
abc,add,eff
jff,slk,lwer
lkwer,fsjk,sdf
EOL

$result = $csv_stallion->parse_and_evaluate({parse_this=>$file});

is_deeply($result,
{
header => ['abc','add','eff'],
records =>
 [
          [
            'jff',
            'slk',
            'lwer'
          ],
          [
            'lkwer',
            'fsjk',
            'sdf'
          ]
        ]
}
, 'parse and evaluate csv');

$result = $csv_stallion->parse_and_evaluate({parse_this=>$file});
$file =<<EOL;
"abc sdf, sdf",add,eff
jff,"slk,lwer,sd
sdfkl,sdf,sdf,sdf",ke
lkwer,fsjk,sdf
EOL


#print STDERR "FH time\n";

my $h_csv_stallion = new Parse::Stallion::CSVFH;

my $file_handle;
#open $file_handle, "<", "/Users/arthurgoldstein/perl/talon/release/Parse-Stallion/t/bbb";
open $file_handle, "<", "t/csv.t_1";
$result = $h_csv_stallion->parse_and_evaluate({parse_this=>$file_handle});
is_deeply($result,
{
 'records' => [
                         [
                           'jff',
                           'slk,lwer,sd
sdfkl,sdf,sdf,sdf',
                           'ke'
                         ],
                         [
                           'lkwer',
                           'fsjk',
                           'sdf'
                         ]
                       ],
          'header' => [
                        'abc sdf, sdf',
                        'add',
                        'eff'
                      ]
}
, 'from a file');
close $file_handle;
open $file_handle, "<", "t/csv.t_2";
eval {$result = $h_csv_stallion->parse_and_evaluate(
  {parse_this=>$file_handle})};
like ($@, qr /Row 1 has an error in field count/,'bad field count');

  my $input_string = 'header1,header2,header3'."\n";
  $input_string .= 'field_1_1,field_1_2,field_1_3'."\n";
   $input_string .= 
   '"field_2_1 3 words",field_2_2 3 words,"""field3_2 x"""'."\n";


  $result = eval {$csv_stallion->
   parse_and_evaluate({parse_this=>$input_string})};

  is_deeply($result,
{
          'records' => [
                         [
                           'field_1_1',
                           'field_1_2',
                           'field_1_3'
                         ],
                         [
                           'field_2_1 3 words',
                           'field_2_2 3 words',
                           '"field3_2 x"'
                         ]
                       ],
          'header' => [
                        'header1',
                        'header2',
                        'header3'
                      ]
        },
    'with double quotes');

print "\nAll done\n";


