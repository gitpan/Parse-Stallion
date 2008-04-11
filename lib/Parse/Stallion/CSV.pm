#Copyright 2007-8 Arthur S Goldstein
#TESTING PHASE

package Parse::Stallion::CSV;
use Carp;
use strict;
use warnings;
use Parse::Stallion;

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

   inner_escaped =>{multiple=>{or=>['TEXTDATA','COMMA','CR','LF', 'DDQUOTE']}},

   DDQUOTE => {and=>['DQUOTE','DQUOTE']},

   non_escaped => {and=>['TEXTDATA']},

   COMMA => {leaf=>qr/\x2C/},

   CR => {leaf=>qr/\x0D/},

   DQUOTE => {leaf=>qr/\x22/},

   LF => {leaf=>qr/\x0A/},

   #CRLF => {and=>['CR','LF']},
   CRLF => {leaf=>qr/\n/},

   TEXTDATA => {leaf=>qr/[\x20-\x21\x23-\x2B\x2D-\x7E]+/,
#    on_match => sub {print STDERR $_[2]." match\n"}
   },

);

sub new {
  my $self = shift;
  my $parameters = shift;
  return  new Parse::Stallion({
    rules_to_set_up_hash=>\%with_header_csv_rules, start_rule=>'file'});
}


1;

__END__

=head1 NAME

Parse::Stallion::CSV - Comma Separated Values

=head1 SYNOPSIS

NOTE: this is still under the testing phase

  use Parse::Stallion::CSV;

  my $csv_stallion = new Parse::Stallion::CSV;

  my $result = eval {$csv_stallion->
   parse_and_evaluate({string=>$input_string})};

  if ($@) {
    if ($stallion->parse_failed) {#parse failed};
  }
  # else $result contains reference to array of arrays

=head1 DESCRIPTION

Reads a comma separated value file or string, returning a reference.
to an array of arrays (or of hashes).

=cut
