#Copyright 2007-8 Arthur S Goldstein

package Parse::Stallion::CSVFH;
our @ISA=qw(Parse::Stallion);
use Parse::Stallion;
use Carp;
use strict;
use warnings;

#Copied somewhat from rfc1480
# see for reference: http://tools.ietf.org/html/rfc4180

my $row;
my $name_count;
my $field_count;
my $row_number;

my %with_header_csv_rules = (
   file => 
     AND
      ('header',
       'CRLF',
       'record',
       MULTIPLE(AND('CRLF', 'record')),
       OPTIONAL('CRLF')
     ,
     EVALUATION(sub {
       return {header => $_[0]->{header}, records => $_[0]->{record}};
     })
    ),

   header => AND('name', MULTIPLE(AND('COMMA', 'name')),
     EVALUATION(sub {$field_count = 0; return $_[0]->{name}},
#     on_match => sub {
#      #print STDERR "reset fc\n";
#      $_[1]->{field_count} = 0}
    )),

   record => AND('field', MULTIPLE(AND('COMMA', 'field')),
     EVALUATION(sub {my $field = $_[0]->{field};
      $row_number++;
#print STDERR "fc $field_count and nc $name_count\n";
      if ($name_count != $field_count) {
         croak ( "Row $row_number has an error in field count got $field_count expected $name_count");
      }
     $field_count = 0;
     return $field;
},
#     on_match => sub {my $object = shift;
#       my $hash = shift;
#       $hash->{row_number}++;
#print STDERR "End of row NC: ".$hash->{name_count}." FC: ".$hash->{field_count}."\n";
#       if ($hash->{name_count} != $hash->{field_count}) {
#         croak ( "Row ".$hash->{row_number}." has an error in field count");
#       }
#       $hash->{field_count} = 0;
#      }
    )),

   name => AND('field',
     EVALUATION (sub {
       my $or = shift;
       my ($value) = values %$or;
       $name_count++;
       return $value}),
     UNEVALUATION(sub {croak 'Mismatch on name in heaader'}),
#     on_match => sub {my $object = shift;
#       my $hash = shift; $hash->{name_count}++},
#     on_unmatch => sub {croak 'Mismatch on name in heaader'},
   ),

   field => OR('escaped', 'non_escaped',
     EVALUATION(sub {
       $field_count++;
       my $or = shift;
       my ($value) = values %$or;
       return $value}),
     UNEVALUATION(sub {croak 'Mismatch on fields in row '.$row}),
#     on_match => sub {my $object = shift;
#       my $hash = shift;
#       #print STDERR "increment fc\n";
#       $hash->{field_count}++},
#     on_unmatch => sub {croak 'Mismatch on fields in row '.$row}
   ),

   escaped => AND('DQUOTE', 'inner_escaped', 'DQUOTE',
      EVALUATION(sub {return $_[0]->{inner_escaped}})
    ),

   inner_escaped =>MULTIPLE('ie',
     EVALUATION(sub {return join("",@{$_[0]->{ie}})})
    ),

   ie =>OR('TEXTDATA','COMMA','CR', 'LF', 'DDQUOTE'),

   DDQUOTE => AND('DQUOTE','DQUOTE'),

   non_escaped => AND('TEXTDATA'),

   COMMA => LEAF(qr/\x2C/),

   CR => LEAF(qr/\x0D/),

   DQUOTE => LEAF(qr/\x22/),

   LF => LEAF(qr/\x0A/),
#    on_match => sub {my $fh = $_[1]->{file_handle};
#print STDERR "LF match\n";
#      $_[0] = <$fh>;}

   CRLF => LEAF(qr/\n/,
#    on_match => sub {my $fh = $_[1]->{file_handle};
#print STDERR "CRLF match v: X".$_[2]."X\n";
#      $_[0] = <$fh>;
#      if (!defined $_[0]) {
#        $_[0] = '';
#      }
#print STDERR "object now ".$_[0]."\n";
#      }
    ),

   TEXTDATA => LEAF(qr/[\x20-\x21\x23-\x2B\x2D-\x7E]+/,
#    on_match => sub {print STDERR $_[2]." match\n"}
   ),

);

sub read_in_file_handle {
  my $parameters = shift;
  my $file_handle = $parameters->{file_handle};
  $name_count = 0;
  $row_number = 0;
  my $chars_read_in = 0;
  my $ps = new Parse::Stallion({
    rules_to_set_up_hash=>\%with_header_csv_rules, start_rule=>'file',
      parse_function => sub {my $cv = shift;
#print STDERR "cv is $cv\n";
#print STDERR "cfh is $file_handle\n";
        if (defined $cv && $cv ne '') {return $cv};
        my $next_line = <$file_handle>;
        if (defined $next_line) {$chars_read_in += length($next_line);
         return $next_line};
        return '';},
    increasing_value_function => sub {my $left = shift || '';
     return $chars_read_in - length($left)}
  });
  return $ps->parse_and_evaluate;
}

1;

__END__

=head1 NAME

Parse::Stallion::CSVFH - Comma Separated Values from file handle

=head1 SYNOPSIS

  This is primarily for demonstrating Parse::Stallion.

  use Parse::Stallion::CSVFH;

  my $file_handle;
  open $file_handle, "<", "csv_file";

  my $csv_stallion = new Parse::Stallion::CSVFH(file_handle => $file_handle);

  my $result = $csv_stallion->parse_and_evaluate();

  if ($stallion->parse_failed) {#parse failed};

  # else $result contains reference to array of arrays

If the file handle refers to a file containing:

 "abc sdf, sdf",add,eff
 jff,"slk,lwer,sd
 sdfkl,sdf,sdf,sdf",ke
 lkwer,fsjk,sdf

Then result will be:

 { 'header' => [ 'abc sdf, sdf', 'add', 'eff' ],
   'records' => [
     [ 'jff', "slk,lwer,sd\nsdfkl,sdf,sdf,sdf", 'ke' ],
     [ 'lkwer', 'fsjk', 'sdf' ]
    ]
 }

=head1 DESCRIPTION

Reads a comma separated value file via a given file handle,
returning a reference to a hash containing the headers and the data. 

=cut
