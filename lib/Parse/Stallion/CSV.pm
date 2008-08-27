#Copyright 2007-8 Arthur S Goldstein
#TESTING PHASE

package Parse::Stallion::CSV;
use Carp;
use strict;
use warnings;
use Parse::Stallion;
#use Data::Dumper;

#Copied somewhat from rfc1480
# see for reference: http://tools.ietf.org/html/rfc4180

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
     evaluation => sub {return $_[0]->{name}}
    },

   record => {and=>['field', {multiple=>{and=>['COMMA', 'field']}}],
     evaluation => sub {return $_[0]->{field}}
    },

   name => {and=>['field']},

   field => {or => ['escaped', 'non_escaped']},

   escaped => {and => ['DQUOTE', 'inner_escaped', 'DQUOTE'],
      evaluation => sub {return $_[0]->{inner_escaped}}
    },

   inner_escaped =>{
     multiple=>{or=>['TEXTDATA','COMMA','CRLF','DDQUOTE'],
      rule_name => 'ie_choices'
      },
      evaluation => sub {
        my $param = shift;
#print "ie params are ".Dumper($param)."\n";
        return join('', @{$param->{'ie_choices'}});
        }
    },

   DDQUOTE => {and=>['DQUOTE','DQUOTE'],
      evaluation => sub {return '"'},
   },

   non_escaped => {and=>['TEXTDATA']},

   COMMA => {leaf=>qr/\x2C/},

#   CR => {leaf=>qr/\x0D/},

   DQUOTE => {leaf=>qr/\x22/},

#   LF => {leaf=>qr/\x0A/},

   #CRLF => {and=>['CR','LF']},
   CRLF => {leaf=>qr/\n/,
#    evaluation =>
#     sub {
#      my $param = shift;
##      print STDERR "Parsm to crlf are ".Dumper($param)."\n";
#      return "\n";
#    }
   },

   TEXTDATA => {leaf=>qr/[\x20-\x21\x23-\x2B\x2D-\x7E]+/,
   },

);

sub new {
  my $self = shift;
  my $parameters = shift;
  return  new Parse::Stallion({
    keep_white_space => 1,
    backtrack_can_change_value => 1,
    rules_to_set_up_hash=>\%with_header_csv_rules, start_rule=>'file'});
}


1;

__END__

=head1 NAME

Parse::Stallion::CSV - Comma Separated Values

=head1 SYNOPSIS

  This is primarily for demonstrating Parse::Stallion.

  use Parse::Stallion::CSV;

  my $csv_stallion = new Parse::Stallion::CSV;

  my $input_string = 'header1,header2,header3'."\n";
  $input_string .= 'field_1_1,field_1_2,field_1_3'."\n";
  $input_string .=
   '"field_2_1 3 words",field_2_2 3 words,\"field3_2 x\"'."\n";

  my $result = eval {$csv_stallion->
   parse_and_evaluate({parse_this=>$input_string})};

  if ($@) {
    if ($csv_stallion->parse_failed) {#parse failed};
  }
  # $result should contain reference to a hase same as
   {'header' => [ 'header1', 'header2', 'header3' ],
    'records' => [
     [ 'field_1_1', 'field_1_2', 'field_1_3' ],
     [ 'field_2_1 3 words', 'field_2_2 3 words', '"field3_2 x"' ]
    ]
   };

=head1 DESCRIPTION

Reads a comma separated value string, returning a reference
to a hash containing the headers and the data.

The source of the grammar from the RFC and the implementation follow to
demonstrate how one can use Parse::Stallion.

=head2 GRAMMAR SOURCE

The grammar used here is based on RFC 4180, see for
example http://tools.ietf.org/html/rfc41801.
The grammar represented by an ABNF grammar:

   file = [header CRLF] record *(CRLF record) [CRLF]

   header = name *(COMMA name)

   record = field *(COMMA field)

   name = field

   field = (escaped / non-escaped)

   escaped = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE

   non-escaped = *TEXTDATA

   COMMA = %x2C

   CR = %x0D

   DQUOTE =  %x22

   LF = %x0A

   CRLF = CR LF

   TEXTDATA =  %x20-21 / %x23-2B / %x2D-7E

=head2 GRAMMAR IMPLEMENTATION

The following is the code used for handling the grammar

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
     evaluation => sub {return $_[0]->{name}}
    },

   record => {and=>['field', {multiple=>{and=>['COMMA', 'field']}}],
     evaluation => sub {return $_[0]->{field}}
    },

   name => {and=>['field']},

   field => {or => ['escaped', 'non_escaped']},

   escaped => {and => ['DQUOTE', 'inner_escaped', 'DQUOTE'],
      evaluation => sub {return $_[0]->{inner_escaped}}
    },

   inner_escaped =>{
     multiple=>{or=>['TEXTDATA','COMMA','CR','LF','DDQUOTE'],
      rule_name => 'ie_choices'
      },
      evaluation => sub {
        my $param = shift;
        return join('', @{$param->{'ie_choices'}});
        }
    },

   DDQUOTE => {and=>['DQUOTE','DQUOTE'],
      evaluation => sub {return '"'},
   },

   non_escaped => {and=>['TEXTDATA']},

   COMMA => {leaf=>qr/\x2C/},

   CR => {leaf=>qr/\x0D/},

   DQUOTE => {leaf=>qr/\x22/},

   LF => {leaf=>qr/\x0A/},

   CRLF => {leaf=>qr/\n/},

   TEXTDATA => {leaf=>qr/[\x20-\x21\x23-\x2B\x2D-\x7E]+/,

  );

  sub new {
    my $self = shift;
    my $parameters = shift;
    return  new Parse::Stallion({
      rules_to_set_up_hash=>\%with_header_csv_rules,
      start_rule=>'file'});
  }

=cut
