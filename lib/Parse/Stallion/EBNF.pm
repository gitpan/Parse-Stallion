#Copyright 2008 Arthur S Goldstein
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
            $results .= " ? Min: $min Max: $max ? ";
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
        $results .= $parser->{rule}->{$rule}->{leaf_info}->{regex_match};
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


1;

__END__

=head1 NAME

Parse::Stallion::EBNF - Output parser in Extended Backus Normal Form.

=head1 SYNOPSIS

  use Parse::Stallion;
  $parser = new Parse::Stallion(...);

  use Parse::Stallion::EBNF;
  $ebnf_form = ebnf Parse::Stallion::EBNF($parser);

  print $ebnf_form;

=head1 DESCRIPTION

  Given a parser from Parse::Stallion, creates a string that is
  the parser's grammar in EBNF.

=cut
