#Copyright 2008-9 Arthur S Goldstein
#TESTING PHASE

package Parse::Stallion::EBNF;
use Carp;
use strict;
use warnings;
use Parse::Stallion;

sub ebnf {
  shift;
  my $parser = shift;

  my @queue;
  my $start_rule = $parser->{start_rule};
  push @queue, $start_rule;

  my $results;
  my %covered;
  while (my $rule = shift @queue) {
    if (!$covered{$rule}++) {
      $results .= "$rule = ";
      if ($parser->{rule}->{$rule}->{rule_type} eq 'MULTIPLE') {
        my $min = $parser->{rule}->{$rule}->{minimum_child};
        my $max = $parser->{rule}->{$rule}->{maximum_child};
        if ($min == 0 && $max == 1) {
          $results .= "[ ";
          $results .= $parser->{rule}->{$rule}->{subrule_list}->[0]->{name};
          $results .= " ]";
        }
        else {
          $results .= "{ ";
          $results .= $parser->{rule}->{$rule}->{subrule_list}->[0]->{name};
          if ($min != 0 || $max != 0) {
            $results .= "($min, $max)";
          }
          $results .= " }";
        }
      }
      elsif ($parser->{rule}->{$rule}->{rule_type} eq 'AND') {
        $results .= join (" , ",
         map {$_->{name}} @{$parser->{rule}->{$rule}->{subrule_list}});
      }
      elsif ($parser->{rule}->{$rule}->{rule_type} eq 'OR') {
        $results .= join (" | ",
         map {$_->{name}} @{$parser->{rule}->{$rule}->{subrule_list}});
      }
      elsif ($parser->{rule}->{$rule}->{rule_type} eq 'LEAF') {
        if (defined $parser->{rule}->{$rule}->{leaf_display}) {
          $results .= $parser->{rule}->{$rule}->{leaf_display};
        }
      }
      else { croak "unknown rule type ".$parser->{rule}->{$rule}->{rule_type};}
      if ($parser->{rule}->{$rule}->{subrule_list}) {
        foreach my $subrule (@{$parser->{rule}->{$rule}->{subrule_list}}) {
          push @queue, $subrule->{name};
        }
      }
      $results .= " ;\n";
    }
  }
  return $results;
}

my %ebnf_rules = (
   ebnf_rule_list => M(O('rule','failed_rule',
    A(qr/\s*\;/, 'comment', qr/\n\s*/)),
    E(sub {
        my $parse_hash = $_[3];
        my $any_errors = 0;
        $parse_hash->{errors} = [];
        if ($_[0]->{failed_rule}) {
          push @{$parse_hash->{errors}}, @{$_[0]->{failed_rule}};
          $any_errors = 1;
        }
       foreach my $rule (@{$_[0]->{rule}}) {
         if ($rule->{error}) {
           push @{$parse_hash->{errors}}, $rule->{error};
           $any_errors = 1;
         }
       }
       if ($any_errors) {croak join("\n",@{$parse_hash->{errors}})}
       return $_[0]->{rule};})),
   rule =>
    A(qr/\s*/, 'rule_name', qr/\s*\=\s*/, 'rule_def', qr /\s*\;/, 'comment',
     qr /(\z|\n\s*)/,
     E(sub {
         return {rule_name => $_[0]->{rule_name},
          rule_definition => $_[0]->{rule_def}}})),
   rule_def =>
    A('the_rule', qr/\s*/, Z('eval_subroutine'),
      E(sub {
         my $the_rule = $_[0]->{the_rule};
         my $rule_def;
         if ($_[0]->{eval_subroutine}->{error}) {
           return {'error' => "Subroutine in ".$_[0]->{rule_name}.
            " has error: ".$_[0]->{eval_subroutine}->{error}}
         }
         elsif ($_[0]->{eval_subroutine}->{sub}) {
           push @{$the_rule->{elements}}, $_[0]->{eval_subroutine}->{sub};
         }
         if ($the_rule->{rule_type} eq 'AND') {
           $rule_def = A(@{$the_rule->{elements}});
         }
         elsif ($the_rule->{rule_type} eq 'OR') {
           $rule_def = O(@{$the_rule->{elements}});
         }
         elsif ($the_rule->{rule_type} eq 'LEAF') {
           $rule_def = L(@{$the_rule->{elements}});
         }
         elsif ($the_rule->{rule_type} eq 'MULTIPLE') {
           $rule_def = M(@{$the_rule->{elements}});
         }
         elsif ($the_rule->{rule_type} eq 'OPTIONAL') {
           $rule_def = Z(@{$the_rule->{elements}});
         }
         return $rule_def})),
   the_rule => O('leaf', 'quote', 'multiple', 'optional', 'and', 'or'),
   comment => qr/[^\n]*/,
   failed_rule => L(qr /[^;]*\;\s*/, 'comment',
     qr /\n\s*/,
    E(sub {my (undef, $text, $pos) = @_;
      my ($line, $position) = LOCATION($text, $pos);
      return "Error at line $line";
     })),
   and => A( 'element' , M(A(qr/\s+/,'element')),
    E(sub {
     return {rule_type => 'AND', elements => $_[0]->{element}};})),
   element => A(Z(A({alias=>'rule_name'}, qr/\./)), 'sub_element',
    E( sub {
      if (defined $_[0]->{alias}) {
        return {$_[0]->{alias} => $_[0]->{sub_element}}
      }
      return $_[0]->{sub_element}})),
   sub_element => O('rule_name', 'sub_rule',
    'optional_sub_rule',
    'multiple_sub_rule', 'leaf_sub_rule', 'quote_sub_rule'),
   optional_sub_rule => A( qr/\[\s*/i, 'rule_def', qr/\s*\]/i,
    E(sub {
      return Z($_[0]->{rule_def});})),
   multiple_sub_rule => A( qr/\s*\{\s*/, 'rule_def', qr/\s*\}/, Z('min_max'),
    E(sub {
      my $min = 0;
      my $max = 0;
      if ($_[0]->{min_max}) {
        $min = $_[0]->{min_max}->{min};
        $max = $_[0]->{min_max}->{max};
      }
      return M($_[0]->{rule_def},$min,$max);}
     )),
   sub_rule => A( qr/\(\s*/i, 'rule_def', qr/\s*\)/i,
    E(sub { return $_[0]->{rule_def};})
   ),
   rule_name => qr/[a-zA-Z]\w*/,
   or => A( 'element' , M(A(qr/\s*\|\s*/, 'element'), 1, 0),
    E(sub {return {rule_type => 'OR', elements => $_[0]->{element}}})),
   multiple => A( qr/\s*\{\s*/, 'element', qr /\s*\}/, Z('min_max'),
    qr/\s*/ ,
    E(sub {
      my $min = 0;
      my $max = 0;
      if ($_[0]->{min_max}) {
        $min = $_[0]->{min_max}->{min};
        $max = $_[0]->{min_max}->{max};
      }
      return {rule_type => 'MULTIPLE', elements => [$_[0]->{element},$min,$max]}
     })),
   min_max => A(qr/\s*\*\s*/,{min=>qr/\d+/},qr/\s*\,\s*/,{max=>qr/\d+/}),
   optional => A( qr/\s*\[\s*/, 'element', qr/\s*\]\s*/,
    E(sub {
      return {rule_type => 'OPTIONAL', elements => [$_[0]->{element}]}
     })),
   quote_sub_rule => A( O(A(qr/q/i, qr/[^\w\s]/), qr/(\"|\')/), 'leaf_info',
    E(sub {my $li = $_[0]->{leaf_info}; substr($li, -1) = '';
      $li =~ s/(\W)/\\$1/g;
      return L(qr/$li/)})),
   quote => A( O(A(qr/q/i, qr/[^\w\s]/,), qr/(\"|\')/), 'leaf_info',
    E(sub {my $li = $_[0]->{leaf_info}; substr($li, -1) = '';
      $li =~ s/(\W)/\\$1/g;
      return {rule_type => 'LEAF', elements => [qr/$li/]}})),
   leaf_sub_rule => A( qr/qr/i, qr/[^\w\s]/, 'leaf_info',
    E(sub {my $li = $_[0]->{leaf_info}; substr($li, -1) = '';
      return L(qr/$li/)})),
   leaf => A( qr/qr/, qr/[^\w\s]/, 'leaf_info',
    Z({modifiers=>qr/\w+/}),
    E(sub {my $li = $_[0]->{leaf_info}; substr($li, -1) = '';
      if (defined $_[0]->{modifiers}) {
         $li = '(?' . $_[0]->{modifiers}. ')'.$li
      }
      return {rule_type => 'LEAF', elements => [qr/$li/]}})),
   leaf_info => L(PF(
    sub {my ($in_ref, undef, $pos) = @_;
      my $previous = substr($$in_ref, $pos-1, 1);
      pos $$in_ref = $pos;
      if ($$in_ref =~ /\G([^$previous]+$previous)/) {
        return 1, $1, $pos + length($1);
      }
      else {
        return 0;
      }
    }
   )),
   eval_subroutine => A( qr/S[^\w\s]/, 'sub_routine',
    E(sub {
      if ($_[0]->{sub_routine}->{error}) {
        return {'error' => $_[0]->{sub_routine}->{error}};
      }
      return {'sub' => SE($_[0]->{'sub_routine'}->{the_sub})}})
   ),
   sub_routine => L(PARSE_FORWARD(
    sub {my ($in_ref, undef, $pos) = @_;
      my $previous = substr($$in_ref, $pos-1, 1);
      pos $$in_ref = $pos;
      my $opposite;
      if ($previous eq '{') {$opposite = '}'};
      if ($previous eq '[') {$opposite = ']'};
      if ($previous eq '(') {$opposite = ')'};
      if ($$in_ref =~ /\G(.*?$opposite(S))/s) {
        return 1, $1, $pos + length($1);
      }
      else {
        return 0;
      }
    }),
    E(sub {
       my $subroutine = shift;
       substr($subroutine, -2) = '';
       return {the_sub => $subroutine};
#       $subroutine = 'sub {'.$subroutine.'}';
#       my $the_sub = eval $subroutine;
#       return {the_sub => $the_sub, error => $@};
     }
   ))
);

our $ebnf_parser = new Parse::Stallion(\%ebnf_rules);

use Parse::Stallion::EBNF;
my $ebnf_form = ebnf Parse::Stallion::EBNF($ebnf_parser);

sub ebnf_new {
  my $type = shift;
  my $rules_string = shift;
#print STDERR "rule string is $rules_string\n";
#  my @pt;
  my $rules_out = eval {$ebnf_parser->parse_and_evaluate(
    $rules_string
#    , {parse_trace => \@pt}
   )};
#use Data::Dumper;print STDERR "pt is ".Dumper(\@pt)."\n";
  if ($@) {croak "\nUnable to create parser due to the following:\n$@\n"};
#use Data::Dumper;print STDERR "ro is ".Dumper($rules_out)."\n";
  my %rules;
  foreach my $rule (@$rules_out) {
    my $rule_name = $rule->{rule_name};
    if ($rules{$rule_name}) {
      croak "Unable to create parse: Duplicate rule name $rule_name\n";
    }
    $rules{$rule_name} = $rule->{rule_definition};
  }
#use Data::Dumper;print STDERR "therules is ".Dumper(\%rules)."\n";
  my $new_parser = new Parse::Stallion(\%rules, {separator => '.'});
  return $new_parser;
}


1;

__END__

=head1 NAME

Parse::Stallion::EBNF - Output/Input parser in Extended Backus Naur Form.

=head1 SYNOPSIS

  #Output
  use Parse::Stallion;
  $parser = new Parse::Stallion(...);

  use Parse::Stallion::EBNF;
  $ebnf_form = ebnf Parse::Stallion::EBNF($parser);

  print $ebnf_form;

  #Input
  my $rules = '
    start = number qr/\s*\+\s*/ number
     S{return $number->[0] + $number->[1]}S;
    number = qr/\d+/;
  ';

  my $rule_parser = ebnf_new Parse::Stallion::EBNF($rules);

  my $value = $rule_parser->parse_and_evaluate('1 + 6');
  #$value should be 7

=head1 DESCRIPTION

=head2 Output

Given a parser from Parse::Stallion, creates a string that is
the parser's grammar in EBNF.

=head2 Input

Use Parse::Stallion for more complicated grammars.

Enter a string with simple grammar rules, a parser is returned.

Each rule must be terminated by a semicolon.

Each rule name must consist of word characters (\w).

Format:

   <rule_name> = <rule_def>;

Four types of rules: 'and', 'or', 'leaf', 'multiple'/'optional' 

Rule names and aliases must start with a letter or underscore though
may contain digits as well.  They are case sensitive.

=head3 AND

'and' rule, the rule_def must be rule names separated by whitespace.

=head3 OR

'or' rule, the rule_def must be rule names separated by single pipes (|).

=head3 LEAF

'leaf' rule, the rule_def can be a 'qr' or 'q'
followed by a non-space, non-word
character (\W) up to a repitition of that character.  What
is betweent the characters is treated as either a regular expression (if 'qr')
or a string (if 'q').  Additionally, if a string is within quotes or
double quotes it is treated as a string.  The following are the same:

  q/x\x/, q'x\x', 'x\x', "x\x",  qr/x\\x/, qr'x\\x'

The qr of a leaf is not the same as a perl regexp's declaration.  Notably,
one cannot escape the delimiting chars.  That is,
     qr/\//

is valid perl but not valid here, one could instead use

     qr+/+

which is also valid perl.

Modifiers are allowed and are inserted into the regexp via an extended
regex sequence:

         qr/abc/i

internally becomes

         qr/(?i)abc/

=head3 MULTIPLE/Optional

'multiple' rule, a rule name enclosed within curly braces {}.  Optionally
may have a minimum and maximum occurence by following the definition with
an asterisk min, max.
For example:

   multiple_rule = {ruleM}*5,0;

would have at least 5 occurences of ruleM.

Optional rules can be specified within square brackets.  The following
are the same:

  {rule_a}*0,1

  [rule_a]

=head3 SUBRULES

Subrules may be specified within a rule by enclosing the subrule within
parentheses.  

=head3 ALIAS

An alias may be specified by an alias name followed by a dot:
the alias then a dot.  I.e.,

    alias.rule

    alias.qr/regex/

    alias.(rule1 rule2)

    alias.(rule1 | rule2)

=head3 EVALUATION

For the evaluation phase (see Parse::Stallion) any
rule can have at the end of its definition, before the semicolon,
a subroutine that should be enclosed within S{ til }S.  Or else S[ til ]S or (S
til )S.  The 'sub ' declaration is done internally.

Internally all subrules have variables created that contain
their evaluated values.  If a subrule's name may occur more than once it is
passed in an array reference.  See Parse::Stallion for details on
parameters passed to evaluation routine.  This saves on having to
create code for reading in the parameters.

Examples:

   rule = number plus number S{subroutine}S;

will create an evaluation subroutine string and eval:

  sub {
  my $number = $_[0]->{number};
  my $plus = $_[0]->{plus};
  subroutine
  }

$number is an array ref, $plus is the returned value from subrule plus.

  number = /\d+/ S{subroutine}S;

is a leaf rule, which only gets one argument to its subroutine:

  sub {
  my $_ = $_[0];
  subroutine
  }

Evaluation is only done after parsing unlike the option of during parsing
found in Parse::Stallion.


=head3 COMMENTS

Comments may be placed on the lines after the semi-colon:

   rule = 'xxx' ; comment
   ; comment 2
   ; comment 3

head3 PRECEDENCE

If there are multiple rules within an or clause it is recommended they
be put together within parentheses:

   a = (b c) | d ;   a = b c | d will not work

The last subroutine corresponds to the whole rule:

   a = e.(c S{...s1...}S) | d S{...s2...}S ;

s1, if called, will get $c as an argument.
s2, if called will get either $e or $d as an argument and the other will be
undef.

=head1 SEE ALSO

example/calculator_ebnf.pl

t/ebnf_in.t in the test cases for examples.

Parse::Stallion
  
=cut
