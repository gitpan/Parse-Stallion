#Copyright 2007-8 Arthur S Goldstein
#TESTING PHASE

package Parse::Stallion::CSVFH;
use Carp;
use strict;
use warnings;
use Parse::Stallion;

#Copied somewhat from rfc1480
# see for reference: http://tools.ietf.org/html/rfc4180

my $row;
my $name_count;
my $field_count;

my %with_header_csv_rules = (
   file => {
     and=>
      ['header',
       'CRLF',
       'record',
       {multiple => {and => ['CRLF', 'record']}},
       {optional=> 'CRLF'}
     ],
     evaluation => sub {
       return {header => $_[0]->{header}, records => $_[0]->{record}};
     }
    },

   header => {and=>['name', {multiple=>{and=>['COMMA', 'name']}}],
     evaluation => sub {return $_[0]->{name}},
     on_match => sub {
      #print STDERR "reset fc\n";
      $_[1]->{field_count} = 0}
    },

   record => {and=>['field', {multiple=>{and=>['COMMA', 'field']}}],
     evaluation => sub {return $_[0]->{field}},
     on_match => sub {my $object = shift;
       my $hash = shift;
       $hash->{row_number}++;
#print STDERR "End of row NC: ".$hash->{name_count}." FC: ".$hash->{field_count}."\n";
       if ($hash->{name_count} != $hash->{field_count}) {
         croak ( "Row ".$hash->{row_number}." has an error in field count");
       }
       $hash->{field_count} = 0;
      }
    },

   name => {and=>['field'],
     on_match => sub {my $object = shift;
       my $hash = shift; $hash->{name_count}++},
     on_unmatch => sub {croak 'Mismatch on name in heaader'}
   },

   field => {or => ['escaped', 'non_escaped'],
     on_match => sub {my $object = shift;
       my $hash = shift;
       #print STDERR "increment fc\n";
       $hash->{field_count}++},
     on_unmatch => sub {croak 'Mismatch on fields in row '.$row}
   },

   escaped => {and => ['DQUOTE', 'inner_escaped', 'DQUOTE'],
      evaluation => sub {return $_[0]->{inner_escaped}}
    },

   inner_escaped =>{multiple=>'ie',
     evaluation => sub {return join("",@{$_[0]->{ie}})}
    },

   ie =>{or=>['TEXTDATA','COMMA','CR', 'LF', 'DDQUOTE']},


   DDQUOTE => {and=>['DQUOTE','DQUOTE']},

   non_escaped => {and=>['TEXTDATA']},

   COMMA => {leaf=>qr/\x2C/},

   CR => {leaf=>qr/\x0D/},

   DQUOTE => {leaf=>qr/\x22/},

   LF => {leaf=>qr/\x0A/,
    on_match => sub {my $fh = $_[1]->{file_handle};
#print STDERR "LF match\n";
      $_[0] = <$fh>;}
   },

   CRLF => {leaf=>qr/\n/,
    on_match => sub {my $fh = $_[1]->{file_handle};
#print STDERR "CRLF match v: X".$_[2]."X\n";
      $_[0] = <$fh>;
      if (!defined $_[0]) {
        $_[0] = '';
      }
#print STDERR "object now ".$_[0]."\n";
      }
    },

   TEXTDATA => {leaf=>qr/[\x20-\x21\x23-\x2B\x2D-\x7E]+/,
#    on_match => sub {print STDERR $_[2]." match\n"}
   },

);

sub new {
  my $self = shift;
  my $parameters = shift;
  my $to_return = new Parse::Stallion({
    rules_to_set_up_hash=>\%with_header_csv_rules, start_rule=>'file',
     keep_white_space => 1,
     on_start => sub {
       my $object = $_[0];
       my $hash = $_[1];
       my $fh = $hash->{file_handle} = $object;
       $_[0] = <$fh>;
      }
    });
  my $ivf = 0;
  $to_return->set_handle_object({
    increasing_value_function => sub {return $ivf++}
  });
  return $to_return;
}


1;

__END__

=head1 NAME

Parse::Stallion::CSVFH - Comma Separated Values from file handle

=head1 SYNOPSIS

  This is primarily for demonstrating Parse::Stallion.

  use Parse::Stallion::CSVFH;

  my $csv_stallion = new Parse::Stallion::CSVFH;

  my $file_handle;
  open $file_handle, "<", "csv_file";

  my $result = eval {$csv_stallion->
   parse_and_evaluate({string=>$file_handle})};

  if ($@) {
    if ($stallion->parse_failed) {#parse failed};
  }
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
