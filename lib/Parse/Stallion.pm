#Copyright 2007-8 Arthur S Goldstein

package Parse::Stallion::Talon;
use Carp;
use strict;
use warnings;
use 5.006;
our $VERSION = '0.70';

sub stringify {
  my $self = shift;
  my $parameters = shift;
  my $values = $parameters->{values} || ['steps','name','parse_match'];
  my $spaces = $parameters->{spaces} || '';
  my $value_separator = '|';
  if (defined $parameters->{value_separator}) {
    $value_separator = $parameters->{value_separator};
  }
  my $line = $spaces;

  foreach my $value (@$values) {
    if (defined $self->{$value}) {
      $line .= $self->{$value}.$value_separator;
    }
    else {
      $line .= $value_separator;
    }
  }

  $line .= "\n";
  foreach my $child (@{$self->{children}}) {
    $parameters->{spaces} = $spaces.' ';
    $line .= stringify($child,$parameters);
  }

  return $line;
}

package Parse::Stallion::Parser;
use Carp;
use strict;
use warnings;

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $parameters = shift;
  my $parsing_info = {%$parameters};
  return bless $parsing_info, $class;
}

sub parse {
  my $parsing_info = shift;
  my $parameters = shift;
  my $object_being_parsed = $parameters->{parse_this};
  my $start_node = $parsing_info->{start_rule};
  my $parse_trace = $parameters->{parse_trace};
  my $parse_hash = $parameters->{parse_hash};
  my $max_steps = $parameters->{max_steps} || $parsing_info->{max_steps};
  my $no_max_steps = 0;
  if ($max_steps < 0) {
    $no_max_steps = 1;
    $max_steps = 1000000;
  }
  my $rule = $parsing_info->{rule};
  my @bottom_up_left_to_right;

  my $first_alias = 'b'.$parsing_info->{separator}.$parsing_info->{separator};
  my $object_length = length($object_being_parsed);

  my $current_value = 0;
  if ($parsing_info->{initial_value}) {
    $current_value = $parsing_info->{initial_value}(\$object_being_parsed,
     $parse_hash);
  }

  my $any_minimize_children = $parsing_info->{any_minimize_children} || 0;
  my $any_parse_forward = $parsing_info->{any_parse_forward} || 0;
  my $any_parse_backtrack = $parsing_info->{any_parse_backtrack} || 0;

  my $tree = {
    name => $start_node,
    steps => 0,
    alias => $first_alias,
    value_when_entered => $current_value,
    node_hash => {},
    children => [],
    child_count => 0
  };
  bless($tree, 'Parse::Stallion::Talon');

  my $current_node = $tree;
  my $moving_forward = 1;
  my $moving_down = 1;
  my $steps = 0;
  my %active_rules_values;
  my $message = 'Start of Parse';
  my ($new_rule_name, $new_alias);
  my $do_evaluation_in_parsing = $parsing_info->{do_evaluation_in_parsing};

  my $node_completed = 0;
  my $create_child = 0;
  my $move_back_to_child = 0;
  my $remove_node = 0;
  my %blocked;
  my $new_rule;

  while (($steps < $max_steps) && $current_node) {
    while ($current_node && (++$steps < $max_steps)) {
      my $current_node_name = $current_node->{name};
      my $current_rule = $rule->{$current_node_name};

      if ($parse_trace) {
        my $parent_step = 0;
        if ($current_node->{parent}) {
          $parent_step = $current_node->{parent}->{steps};
        }
        push @$parse_trace, {
         rule_name => $current_node_name,
         moving_forward => $moving_forward,
         moving_down => $moving_down,
         value => $current_value,
         node_creation_step => $current_node->{steps},
         parent_node_creation_step => $parent_step,
         message => $message,
         tree => $tree->stringify,
        };
        $message = '';
      }
      if ($moving_forward) {
        if ($current_rule->{or_rule}) {
          if ($moving_down) {
            $new_rule = $current_rule->{subrule_list}->[0];
            $new_rule_name = $new_rule->{name};
            $new_alias = $new_rule->{alias};
            $current_node->{or_child_number} = 0;
            $create_child = 1;
          }
          else {
            $node_completed = 1;
          }
        }
        elsif ($current_rule->{and_rule}) {
          if ($current_node->{child_count} ==
           $current_rule->{subrule_list_count}) {
            $node_completed = 1;
          }
          else {
            $new_rule = $current_rule->{subrule_list}->[
             $current_node->{child_count}];
            $new_rule_name = $new_rule->{name};
            $new_alias = $new_rule->{alias};
            $create_child = 1;
          }
        }
        elsif ($any_minimize_children && $current_rule->{minimize_children} &&
         $current_rule->{minimum_child} <= $current_node->{child_count}) {
          $node_completed = 1;
        }
        elsif ($current_rule->{maximum_child} &&
         $current_rule->{maximum_child} == $current_node->{child_count}) {
          $node_completed = 1;
        }
        else {
          $new_rule_name = $current_rule->{sub_rule_name};
          $new_alias = $current_rule->{sub_alias};
          $create_child = 1;
        }
      }
      else { # !$moving_forward
        if ($current_rule->{leaf_rule}) {
          if ($any_parse_backtrack && $current_rule->{parse_backtrack}) {
            my $parent_node = $current_node->{parent};
            my $end_parse_now =
             &{$current_rule->{parse_backtrack}}
             ({parse_this_ref => \$object_being_parsed,
              current_value => $current_value,
              value_when_entered => $current_node->{value_when_entered},
              parameters => $parent_node->{parameters},
              parse_hash => $parse_hash,
              node_hash => $parent_node->{node_hash},
              node_parse_match => $parent_node->{parse_match},
              match => $current_node->{parse_match},
              leaf_rule_info => $new_rule->{leaf_rule_info},
              });
            if ($end_parse_now) {
              $current_node = undef;
              $moving_forward = 0;
              last;
            }
          }
          $current_value = $current_node->{value_when_entered};
          $remove_node = 1;
        }
        elsif ($current_rule->{or_rule}) {
          if ($moving_down) {
            $move_back_to_child = 1;
          }
          else {
            if (++$current_node->{or_child_number} <
             $current_rule->{subrule_list_count}) {
              $new_rule = $current_rule->{subrule_list}->[
               $current_node->{or_child_number}];
              $new_rule_name = $new_rule->{name};
              $new_alias = $new_rule->{alias};
              $create_child = 1;
            }
            else {
              $remove_node = 1;
            }
          }
        }
        elsif ($current_rule->{and_rule}) {
          if ($current_node->{child_count} == 0) {
            $remove_node = 1;
          }
          else {
            $move_back_to_child = 1;
          }
        }
        elsif (((!$any_minimize_children ||
         !$current_rule->{minimize_children}) && !$moving_down) &&
         (!$current_rule->{minimum_child} ||
         ($current_rule->{minimum_child} <= $current_node->{child_count}))) {
          $node_completed = 1;
        }
        elsif (($any_minimize_children &&
         $current_rule->{minimize_children} && $moving_down) &&
         (!$current_rule->{maximum_child} ||
         ($current_rule->{maximum_child} > $current_node->{child_count}))) {
          $new_rule_name = $current_rule->{sub_rule_name};
          $new_alias = $current_rule->{sub_alias};
          $create_child = 1;
        }
        elsif ($current_node->{child_count}) {
          $move_back_to_child = 1;
        }
        else {
          $remove_node = 1;
        }
      }

      if ($create_child) {
        $create_child = 0;
        my $new_rule = $rule->{$new_rule_name};
        if ($blocked{$new_rule_name}{$current_value}) {
          $message =
           "Rule $new_rule_name blocked before on value $current_value"
           if $parse_trace;
          $moving_forward = 0;
          $moving_down = 0;
        }
        elsif ($new_rule->{leaf_rule}) {
          my $previous_value = $current_value;
          my ($continue_forward, $match, $re_match);
          if ($any_parse_forward && $new_rule->{parse_forward}) {
            ($continue_forward, $match, $current_value) =
             &{$new_rule->{parse_forward}}
             ({parse_this_ref => \$object_being_parsed,
              current_value => $current_value,
              parameters => $current_node->{parameters},
              parse_hash => $parse_hash,
              node_hash => $current_node->{node_hash},
              node_parse_match => $current_node->{parse_match},
              leaf_rule_info => $new_rule->{leaf_rule_info},
              });
            if (!$continue_forward) {
              $current_value = $previous_value;
            }
            if (!defined $current_value) {
              croak("Current_value not set, parse forward of $new_rule_name");
            }
            if ($previous_value > $current_value) {
              croak ("Moving forward on $current_node_name resulted in 
               backwards progress ($previous_value, $current_value)");
            }
          }
          else {
            my $x = $new_rule->{regex_match};
            pos $object_being_parsed = $current_value;
            if ($object_being_parsed =~ /$x/cg) {
              $match = $1;
              $re_match = $2;
              if (!defined $match) {$match = ''};
              $continue_forward = 1;
              $current_value = pos $object_being_parsed;
            }
            else {
              $continue_forward = 0;
            }
          }
          if (!$continue_forward) {
            $moving_forward = 0;
            $moving_down = 0;
            $message .= 'Leaf not matched' if $parse_trace;
          }
          else {
            my $new_node = {
              name => $new_rule_name,
              alias => $new_alias,
              steps => $steps,
              parent => $current_node,
              value_when_entered => $previous_value,
              children => [],
              child_count => 0,
              parse_match => $match,
              re_parse_match => $re_match,
            };
            push @{$current_node->{children}}, $new_node;
            $current_node->{child_count}++;
            $message .= 'Leaf matched' if $parse_trace;
            $current_node = $new_node;
            $node_completed = 1;
          }
        }
        elsif ($active_rules_values{$new_rule_name}{$current_value}++) {
           croak ("$new_rule_name duplicated in parse on same string");
        }
        else {
          $message = "Creating child $new_rule_name for node created on step "
           .$current_node->{steps} if $parse_trace;
          my $new_node = {
            name => $new_rule_name,
            alias => $new_alias,
            steps => $steps,
            parent => $current_node,
            value_when_entered => $current_value,
            node_hash => {},
            children => [],
            child_count => 0,
          };
          push @{$current_node->{children}}, $new_node;
          $current_node->{child_count}++;
          $moving_forward = 1;
          $moving_down = 1;
          $current_node = $new_node;
        }
      }

      if ($node_completed) {
        $node_completed = 0;
        if ($current_node->{ventured}->{$current_value}++) {
          $message .= " Already ventured beyond this node at value"
           if $parse_trace;
          $moving_forward = 0;
          $moving_down = 1;
        }
        else {
          my $reject;
          if ($do_evaluation_in_parsing) {
            (undef, $reject) = $parsing_info->{self}->new_evaluate_tree_node(
             {nodes => [$current_node],
              object => $object_being_parsed,
              current_value => $current_value,
              parse_hash => $parse_hash
            });
          }
          if (defined $reject && $reject) {
            $moving_forward = 0;
            $moving_down = 1;
            $message .= " Node rejected" if $parse_trace;
          }
          else {
            push @bottom_up_left_to_right, $current_node;
            $current_node->{'beyond'} = 1;
            $message .= " Completed node created on step ".
             $current_node->{steps} if $parse_trace;
            $moving_down = 0;
            $moving_forward = 1;
            $current_node = $current_node->{parent};
          }
        }
      }
      elsif ($move_back_to_child) {
        $move_back_to_child = 0;
        $message .= " Backtracking to child" if $parse_trace;
        $moving_down = 1;
        $moving_forward = 0;
        pop @bottom_up_left_to_right;
        $current_node =
         $current_node->{children}->[$current_node->{child_count}-1];
        if ($do_evaluation_in_parsing) {
          $parsing_info->{self}->new_unevaluate_tree_node(
           {node => $current_node,
            object => $object_being_parsed});
        }
      }
      elsif ($remove_node) {
        $remove_node = 0;
        $moving_forward = 0;
        $moving_down = 0;
        if (!$current_node->{'beyond'}) {
          $blocked{$current_node_name}{$current_value} = 1;
        }
        delete $active_rules_values{$current_node_name}{$current_value};
        $message .= " Removed node created on step ".$current_node->{steps}
         if $parse_trace;
        $current_node = $current_node->{parent};
        if (defined $current_node) {
          pop @{$current_node->{children}};
          $current_node->{child_count}--;
        }
      }
    }
    if (!$current_node && $moving_forward &&
     (($parsing_info->{final_value} &&
     (&{$parsing_info->{final_value}}(\$object_being_parsed, $current_value,
      $parse_hash) != $current_value))
     ||
      (!($parsing_info->{final_value}) &&
       (length($object_being_parsed) != $current_value)))) {
       $moving_forward = 0;
       $moving_down = 1;
       $current_node = $tree;
       $message .= ' . At top of tree but did not parse entire object'
        if $parse_trace;
       pop @bottom_up_left_to_right;
    }
    if ($no_max_steps && ($steps == $max_steps)) {
      $max_steps += 1000000;
    }
  }
  if ($steps >= $max_steps) {
    croak ("Not enough steps to do parse, max set at $max_steps");
  }
  my $results = $parameters->{parse_info};
  $results->{start_rule} = $parsing_info->{start_rule};
  $results->{number_of_steps} = $steps;
  $results->{tree} = $tree;
  $results->{bottom_up_left_to_right} = \@bottom_up_left_to_right;
  if ($moving_forward) {
    $results->{parse_succeeded} = 1;
    if ($do_evaluation_in_parsing) {
      $results->{parsing_evaluation} = $tree->{computed_value};
    }
  }
  else {
    $results->{parse_succeeded} = 0;
  }
  return $results;
}

package Parse::Stallion;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT =
 qw(A AND O OR LEAF L M MULTIPLE OPTIONAL ZERO_OR_ONE Z
    E EVALUATION U UNEVALUATION PF PARSE_FORWARD PB PARSE_BACKTRACK
    LEAF_DISPLAY USE_PARSE_MATCH LOCATION SE STRING_EVALUATION);
use strict;
use warnings;
use Carp;
use File::Spec;

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $rules_to_set_up_hash = shift;
  my $parameters = shift;
  my $self = {};

  bless $self, $class;
  $self->{separator} = '__XZ__';
  $self->{max_steps} = $parameters->{max_steps} || 100000;
  $self->{self} = $self;
  $self->{do_evaluation_in_parsing} = $parameters->{do_evaluation_in_parsing}
   || 0;
  $self->{do_not_compress_eval} = $parameters->{do_not_compress_eval} || 0;
  $self->{separator} = $parameters->{separator} || $self->{separator};
  if (defined $parameters->{parse_forward}) {
    $self->{leaf_parse_forward} = $parameters->{parse_forward};
    $self->{any_parse_forward} = 1;
  }
  if (defined $parameters->{parse_backtrack}) {
    $self->{leaf_parse_backtrack} = $parameters->{parse_backtrack};
    $self->{any_parse_backtrack} = 1;
  }
  $self->{initial_value} = $parameters->{initial_value};
  $self->{final_value} = $parameters->{final_value};
  $self->set_up_full_rule_set($rules_to_set_up_hash, $parameters->{start_rule});
  return $self;
}

sub parse_and_evaluate {
  my $self = shift;
  my $parse_this = shift;
  my $parameters = shift || {};
  $parameters->{parse_this} = $parse_this;
  my $parser = new Parse::Stallion::Parser($self);
  $parameters->{parse_info} = $parameters->{parse_info} || {};
  $parameters->{parse_hash} = {};
  my $parser_results = eval {$parser->parse($parameters)};
  if ($@) {croak ($@)};
  my $to_return;
  if (!($parser_results->{parse_succeeded})) {
    $to_return = undef;
  }
  elsif ($self->{do_evaluation_in_parsing}) {
    $to_return = $parser_results->{parsing_evaluation};
  }
  else {
    $self->new_evaluate_tree_node(
     {nodes=>$parser_results->{bottom_up_left_to_right},
      parse_hash => $parameters->{parse_hash},
      object=> $parse_this});
    $to_return = $parser_results->{tree}->{computed_value};
  }
  return $to_return;
}

#package rules
sub eval_sub {
  return ['EVAL', @_];
}

sub E {eval_sub(@_)}
sub EVALUATION {eval_sub(@_)}

sub string_eval_sub {
  return ['SEVAL', @_];
}

sub SE {string_eval_sub(@_)}
sub STRING_EVALUATION {string_eval_sub(@_)}

sub uneval_sub {
  return ['UNEVAL', @_];
}

sub U {uneval_sub(@_)}
sub UNEVALUATION {uneval_sub(@_)}

sub parse_forward_sub {
  return ['PARSE_FORWARD', @_];
}

sub PF {parse_forward_sub(@_)}
sub PARSE_FORWARD {parse_forward_sub(@_)}

sub parse_backtrack_sub {
  return ['PARSE_BACKTRACK', @_];
}

sub PB {parse_backtrack_sub(@_)}
sub PARSE_BACKTRACK {parse_backtrack_sub(@_)}

sub use_parse_match {
  return ['USE_PARSE_MATCH'];
}

sub USE_PARSE_MATCH {use_parse_match(@_)}

sub and_sub {
  return ['AND', @_];
}

sub AND {and_sub(@_)}
sub A {and_sub(@_)}

sub or_sub {
  return ['OR', @_];
}

sub OR {or_sub(@_)}
sub O {or_sub(@_)}

sub LEAF_DISPLAY {
  return ['LEAF_DISPLAY', $_[0]];
}

sub leaf {
  my @p;
  my @q;
  foreach my $parm (@_) {
    if (ref $parm eq 'ARRAY') {
      push @q, $parm;
    }
    else {
      push @p, $parm;
    }
  }
  if (ref $p[0] eq 'Regexp') {
    return ['LEAF', {regex_match => qr/\G($p[0])/}, LEAF_DISPLAY($p[0]), @q];
  }
  else {
    return ['LEAF', @p, @q];
  }
}

sub LEAF {leaf(@_)}
sub L {leaf(@_)}

sub multiple {
  my @p;
  my @q;
  foreach my $parm (@_) {
    if ((ref $parm eq 'ARRAY') &&
     ($parm->[0] eq 'EVAL' || $parm->[0] eq 'UNEVAL' || $parm->[0] eq 'SEVAL'
      || $parm->[0] eq 'USE_PARSE_MATCH')) {
      push @q, $parm;
    }
    elsif ($parm eq 'match_min_first') {
      push @q, ['MATCH_MIN_FIRST'];
    }
    else {
      push @p, $parm;
    }
  }
  if ($#p == 0) {
    return ['MULTIPLE', 0, 0, $_[0], @q];
  }
  elsif ($#p == 2) {
    return ['MULTIPLE', $_[1], $_[2], $_[0], @q];
  }
use Data::Dumper; print STDERR Dumper(\@_);
  croak "Malformed MULTIPLE";
}

sub MULTIPLE {multiple(@_)}
sub M {multiple(@_)}

sub optional {
  if ($#_ == 0) {
    return ['MULTIPLE', 0, 1, $_[0]];
  }
  croak "Malformed OPTIONAL";
}
sub OPTIONAL {optional(@_)}
sub ZERO_OR_ONE {optional(@_)}
sub Z {optional(@_)}

sub update_count {
  my $rule_type = shift;
  my $rule_counts = shift;
  my $subrule_name = shift;
  my $subrule_count = shift || 0;
  if ($subrule_count > 1) {
    $rule_counts->{rule_count}->{$subrule_name} = 2;
  }
  elsif ($rule_type eq 'AND') {
    $rule_counts->{rule_count}->{$subrule_name} += $subrule_count;
  }
  elsif ($rule_type eq 'MULTIPLE' && ($rule_counts->{maximum_child} != 1 ||
   $subrule_count > 1)) {
    $rule_counts->{rule_count}->{$subrule_name} = 2;
  }
  elsif ($rule_type eq 'MULTIPLE') {
    $rule_counts->{rule_count}->{$subrule_name} =
     $rule_counts->{rule_count}->{$subrule_name} || 1;
  }
  elsif ($rule_type eq 'OR' &&
   (!defined $rule_counts->{rule_count}->{$subrule_name} ||
    ($subrule_count > $rule_counts->{rule_count}->{$subrule_name}))) {
    $rule_counts->{rule_count}->{$subrule_name} = $subrule_count;
  }
}

sub default_unevaluation_routine { #empty
}

sub add_rule {
  my $self = shift;
  my $parameters = shift;
  my $rule_name = $parameters->{rule_name} || croak ("Empty rule name");
  my $rule = $parameters->{rule_definition};
  if ($self->{rule}->{$rule_name}) {
    croak ("Rule $rule_name already exists\n");
  }
  if (ref $rule eq 'Regexp') {
    $rule = LEAF($rule);
  }
  elsif (ref $rule eq '') {
    $rule = AND($rule);
  }

  if (ref $rule ne 'ARRAY') {
    croak ("Bad format of rule $rule_name, cannot create.");
  }

  my $separator = $self->{separator};
  my $base_rule = $rule_name;
  if (defined $parameters->{generated_name}) {
    $self->{rule}->{$rule_name}->{generated} = 1;
    $base_rule = $parameters->{generated_name};
  }
  elsif (index($rule_name, $separator) != -1) {
    croak ("rule name $rule_name contains separator $separator");
  }
  my $default_alias = '';
  my @copy_of_rule; #to prevent changing input
  my $rule_type = $self->{rule}->{$rule_name}->{rule_type} = $rule->[0];
  foreach my $sub_rule (@$rule) {
    if (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'EVAL') {
      my $what_to_eval = $sub_rule->[1];
      if ($self->{rule}->{$rule_name}->{parsing_evaluation}) {
        croak ("Rule $rule_name has more than one evaluation routine");
      }
      if (ref $sub_rule->[1] eq 'CODE') {
        $self->{rule}->{$rule_name}->{parsing_evaluation} = $what_to_eval;
      }
      elsif (ref $sub_rule->[1] eq 'Regexp') {
        $self->{rule}->{$rule_name}->{parsing_evaluation} = sub {
           $_[0] =~ $what_to_eval;
           return $1;
         };
        $self->{rule}->{$rule_name}->{use_parse_match} = 1;
      }
      else {
        $self->{rule}->{$rule_name}->{parsing_evaluation} = sub {
           return $what_to_eval;
         };
      }
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'SEVAL') {
      $self->{rule}->{$rule_name}->{string_evaluation} = $sub_rule->[1];
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'UNEVAL') {
      if ($self->{rule}->{$rule_name}->{parsing_unevaluation}) {
        croak ("Rule $rule_name has more than one unevaluation routine");
      }
      $self->{rule}->{$rule_name}->{parsing_unevaluation} = $sub_rule->[1]
       || $self->{rule}->{$rule_name}->{parsing_unevaluation};
      $self->{do_evaluation_in_parsing} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'MATCH_MIN_FIRST') {
      if ($rule_type ne 'MULTIPLE') {
        croak ("Only multiple rules can have MATCH_MIN_FIRST");
      }
      $self->{rule}->{$rule_name}->{minimize_children} = 1;
      $self->{any_minimize_children} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'LEAF_DISPLAY') {
      if ($self->{rule}->{$rule_name}->{leaf_display}) {
        croak ("Rule $rule_name has more than one leaf_display");
      }
      if ($rule_type ne 'LEAF') {
        croak ("Only leaf rules can have LEAF_DISPLAY");
      }
      $self->{rule}->{$rule_name}->{leaf_display} = $sub_rule->[1];
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'USE_PARSE_MATCH') {
      $self->{rule}->{$rule_name}->{use_parse_match} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'PARSE_FORWARD') {
      if ($rule_type eq 'LEAF') {
        if ($self->{rule}->{$rule_name}->{parse_forward}) {
          croak ("Rule $rule_name has more than one parse_forward");
        }
        $self->{rule}->{$rule_name}->{parse_forward} = $sub_rule->[1]
         || croak ("Rule $rule_name Illegal parse_forward routine");
        $self->{any_parse_forward} = 1;
      }
      else {
        croak ("Parse forward in rule $rule_name of $rule_type (not leaf)");
      }
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'PARSE_BACKTRACK') {
      if ($rule_type eq 'LEAF') {
        if ($self->{rule}->{$rule_name}->{parse_backtrack}) {
          croak ("Rule $rule_name has more than one parse_backtrack");
        }
        $self->{rule}->{$rule_name}->{parse_backtrack} = $sub_rule->[1]
         || croak ("Rule $rule_name Illegal parse_backtrack routine");
        $self->{any_parse_backtrack} = 1;
      }
      else {
        croak ("Parse backtrack in rule $rule_name of $rule_type (not leaf)");
      }
    }
    else {
      push @copy_of_rule, $sub_rule;
    }
  }
  shift @copy_of_rule; #Remove rule type
  $self->{rule}->{$rule_name}->{leaf_rule} = 0;
  $self->{rule}->{$rule_name}->{or_rule} = 0;
  $self->{rule}->{$rule_name}->{and_rule} = 0;
  if ($rule_type eq 'LEAF') {
    $self->{rule}->{$rule_name}->{leaf_rule_info} = shift @copy_of_rule;
      $self->{rule}->{$rule_name}->{regex_match} =
       $self->{rule}->{$rule_name}->{leaf_rule_info}->{regex_match};
    $self->{rule}->{$rule_name}->{parse_forward} =
     $self->{rule}->{$rule_name}->{parse_forward} ||
     $self->{leaf_parse_forward};
    $self->{rule}->{$rule_name}->{parse_backtrack} =
     $self->{rule}->{$rule_name}->{parse_backtrack} ||
     $self->{leaf_parse_backtrack};
    $self->{rule}->{$rule_name}->{use_parse_match} = 1;
    $self->{rule}->{$rule_name}->{leaf_rule} = 1;
  }
  else {
    if ($rule_type eq 'AND') {
      $self->{rule}->{$rule_name}->{and_rule} = 1;
    }
    elsif ($rule_type eq 'OR') {
      $self->{rule}->{$rule_name}->{or_rule} = 1;
    }
    elsif ($rule_type eq 'MULTIPLE') {
      my $min =
       $self->{rule}->{$rule_name}->{minimum_child} = shift @copy_of_rule;
      my $max =
      $self->{rule}->{$rule_name}->{maximum_child} = shift @copy_of_rule;
      if (($max && ($min > $max)) || ($min < 0) || $min != int($min)
       || $max != int($max)) {
        croak("Illegal bound(s) $min and $max on $rule_name");
      }
    }
    else {
      croak "Bad rule type $rule_type on rule $rule_name\n";
    }
    foreach my $current_rule (@copy_of_rule) {
      my ($alias, $name);
      if (ref $current_rule eq 'HASH') {
        my @hash_info = keys (%{$current_rule});
        if ($#hash_info != 0) {
          croak ("Too many keys in rule $rule_name");
        }
        $alias = $hash_info[0];
        $current_rule = $current_rule->{$alias};
      }
      if (ref $current_rule eq '') {
        if (!defined $alias) {
          $alias = $current_rule;
        }
        $name = $current_rule;
      }
      elsif (ref $current_rule eq 'Regexp') {
        if (!defined $alias) {
          $alias = $default_alias;
        }
        $name = $base_rule.$separator.
          ++$self->{unique_name_counter}->{$base_rule};
        $self->add_rule({
         rule_name => $name, rule_definition => LEAF($current_rule),
         generated_name => $base_rule});
      }
      elsif (ref $current_rule eq 'ARRAY') {
        $name = $base_rule.$separator.
          ++$self->{unique_name_counter}->{$base_rule};
        $self->add_rule({
         rule_name => $name, rule_definition => $current_rule,
         generated_name => $base_rule});
        if (!defined $alias) {
          if (defined $self->{rule}->{$name}->{parsing_evaluation} ||
           $self->{rule}->{$name}->{rule_type} eq 'LEAF') {
            $alias = $default_alias;
          }
        }
      }
      push @{$self->{rule}->{$rule_name}->{subrule_list}},
       {alias => $alias, name => $name};
    }
    $self->{rule}->{$rule_name}->{subrule_list_count} =
     scalar(@{$self->{rule}->{$rule_name}->{subrule_list}});
    foreach my $subrule (@{$self->{rule}->{$rule_name}->{subrule_list}}) {
      if (defined $subrule->{alias}) {
           update_count($rule_type,
            $self->{rule}->{$rule_name},$subrule->{alias}, 1);
      }
      else {
        foreach my $sub_alias (keys 
         %{$self->{rule}->{$subrule->{name}}->{rule_count}}) {
           update_count($rule_type,
            $self->{rule}->{$rule_name}, $sub_alias,
            $self->{rule}->{$subrule->{name}}->{rule_count}->{$sub_alias});
        }
      }
    }
    if (defined $self->{rule}->{$rule_name}->{string_evaluation}) {
      if ($self->{rule}->{$rule_name}->{parsing_evaluation}) {
        croak ("Rule $rule_name has multiple evaluation routines");
      }
      my $params = which_parameters_are_arrays($self, $rule_name);
      my @params = keys %$params;
      my $sub = "sub {\n";
      if ($self->{rule}->{$rule_name}->{use_parse_match}) {
        $sub .= "\$_ = \$_[0];\n";
      }
      else {
        foreach my $param (@params) {
          if ($param =~ /\w+/ && ($param ne '_')) {
            $sub .= "my \$$param = \$_[0]->{$param};\n";
          }
          elsif ($param eq '') {
            $sub .= "\$_ = \$_[0]->{''};\n";
          }
          else {
            croak "String Evaluation of rule $rule_name cannot handle ".
             "parameter with name $param";
          }
        }
      }
      $sub .= $self->{rule}->{$rule_name}->{string_evaluation}."}";
      $self->{rule}->{$rule_name}->{parsing_evaluation} = eval $sub;
      if ($@) {croak "Rule $rule_name error on subroutine evaluation $@"};
    }
    $self->{rule}->{$rule_name}->{sub_rule_name} =
     $self->{rule}->{$rule_name}->{subrule_list}->[0]->{name};
    $self->{rule}->{$rule_name}->{sub_alias} =
     $self->{rule}->{$rule_name}->{subrule_list}->[0]->{alias};
  }
  $self->{rule}->{$rule_name}->{parsing_unevaluation} =
   $self->{rule}->{$rule_name}->{parsing_unevaluation} ||
   \&default_unevaluation_routine;
}

sub make_sure_all_rules_reachable {
  my $self = shift;
  my $parameters = shift;
  my $start_rule = $parameters->{start_rule};
  my @rules_to_check = ($start_rule);
  my %rules_checked;
  $rules_checked{$start_rule} = 1;
  while (my $rule_to_check = shift @rules_to_check) {
    if ($self->{rule}->{$rule_to_check}->{subrule_list}) {
      foreach my $rule_name_alias
       (@{$self->{rule}->{$rule_to_check}->{subrule_list}}) {
        my $rule_name = $rule_name_alias->{name};
        if (!($rules_checked{$rule_name}++)) {
          push @rules_to_check, $rule_name;
        }
      }
    }
  }
  my @unreachable;
  foreach my $rule (keys %{$self->{rule}}) {
    if (!$rules_checked{$rule}) {
      push @unreachable, "No path to rule $rule start rule $start_rule";
    }
  }
  return @unreachable;
}

sub make_sure_all_names_covered {
  my $self = shift;
  my $parameters = shift;
  my $return_list = $parameters->{return_list};
  my @list;
  foreach my $rule (keys %{$self->{rule}}) {
    if ($self->{rule}->{$rule}->{subrule_list}) {
      foreach my $rule_name_alias (@{$self->{rule}->{$rule}->{subrule_list}}) {
        my $rule_name = $rule_name_alias->{name};
        if (!$self->{rule}->{$rule_name}) {
          if ($return_list) {
            push @list, "Rule $rule missing subrule $rule_name";
          }
          else {
            croak ("Rule $rule has undefined subrule of $rule_name");
          }
        }
      }
    }
  }
  return @list;
}

sub which_parameters_are_arrays {
  my $self = shift;
  my $rule_name = shift;
  my $rules_details = $self->{rule};
  my %to_return;
  foreach my $child_rule_name (sort keys
   %{$rules_details->{$rule_name}->{rule_count}}) {
    if ($rules_details->{$rule_name}->{rule_count}->{$child_rule_name} > 1) {
      $to_return{$child_rule_name} = 1;
    }
    else {
      $to_return{$child_rule_name} = 0;
    }
  }
  return \%to_return;
}

sub set_up_full_rule_set {
  my $self = shift;
  my $rules_to_set_up_hash = shift;
  my $start_rule = shift;

  foreach my $hash_rule_name (sort keys %$rules_to_set_up_hash) {
    $self->add_rule({rule_name => $hash_rule_name,
     rule_definition => $rules_to_set_up_hash->{$hash_rule_name}});
  }

  if (!defined $start_rule) {
    my %covered_rule;
    foreach my $rule_name (keys %{$self->{rule}}) {
      foreach my $subrule
       (@{$self->{rule}->{$rule_name}->{subrule_list}}) {
        $covered_rule{$subrule->{name}}++;
      }
    }
    START: foreach my $rule_name (keys %{$self->{rule}}) {
      if (!$covered_rule{$rule_name}) {
        $start_rule = $rule_name;
        last START;
      }
    }
    if (!defined $start_rule) {croak "No valid start rule"};
  }

  my @missing_rules = $self->make_sure_all_names_covered({return_list=>1});
  if ($#missing_rules > -1) {
    croak "Missing rules: ".join("\n",@missing_rules)."\n";
  }
 
  my @unreachable_rules = $self->make_sure_all_rules_reachable({
   start_rule=>$start_rule});
  if ($#unreachable_rules > -1) {
    croak "Unreachable rules: ".join("\n",@unreachable_rules)."\n";
  }

  my $rule_count = scalar keys %{$self->{rule}};
  if ($rule_count == 1) {
    $self->add_rule({
         rule_name => $start_rule.'x',
         rule_definition => AND($start_rule, E(
           sub {my ($v) = values %{$_[0]}; return $v}))
    });
    $start_rule .= 'x';
  }

  $self->{start_rule} = $start_rule;
}

sub new_unevaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $node = $parameters->{node};
  my $object = $parameters->{object};
  my $parse_hash = $parameters->{parse_hash};
  my $rules_details = $self->{rule};
  my $rule_name = $node->{name};
  my $subroutine_to_run = $rules_details->{$rule_name}->{parsing_unevaluation};

  &$subroutine_to_run($node->{parameters}, \$object, $parse_hash);

  if (my $parent = $node->{parent}) {
    if (defined $node->{parse_match} &&
     (ref $node->{parse_match} eq '')) {
      substr($parent->{parse_match}
       , 0 - length($node->{parse_match})) = '';
    }

    foreach my $param (keys %{$node->{passed_params}}) {
      if (my $count = $node->{passed_params}->{$param}) {
        if ($count > scalar(@{$parent->{parameters}->{$param}})) {
          croak("Unevaluation parameter miscount; routine in rule $rule_name");
        }
        splice(@{$parent->{parameters}->{$param}}, - $count);
      }
      else {
        delete $parent->{parameters}->{$param};
      }
    }
    delete $node->{passed_params};
  }
}

sub new_evaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $nodes = $parameters->{nodes};
  my $object = $parameters->{object};
  my $current_value = $parameters->{current_value};
  my $parse_hash = $parameters->{parse_hash};
  my $set_current_value = 0;
  if (!(defined $current_value)) {
    $set_current_value = 1;
  }
  my $rules_details = $self->{rule};
  my @results;

  foreach my $node (@$nodes) {
    my $rule_name = $node->{name};
    my $params_to_eval = $node->{parameters};
    if ($set_current_value) {
      $current_value = $node->{value_when_entered};
    }
    my $rule = $rules_details->{$rule_name};
    my $subroutine_to_run = $rule->{parsing_evaluation};

    if ($rule->{use_parse_match}) {
      if (defined $node->{re_parse_match}) {
        $params_to_eval = $node->{re_parse_match};
      }
      else {
        $params_to_eval = $node->{parse_match};
      }
    }
    my $alias = $node->{alias};

    my $cv;
    if ($subroutine_to_run) {
      @results = &$subroutine_to_run($params_to_eval,
       {parse_this_ref => \$object, current_value => $current_value,
        parameters => $node->{parameters},
        parse_hash => $parse_hash, node_hash => $node->{node_hash},
        node_parse_match => $node->{parse_match}
        }
       );
      $cv = $results[0];
    }
    else {
      if ($rule->{generated} || $self->{do_not_compress_eval}) {
        $cv = $params_to_eval;
      }
      elsif ((ref $params_to_eval eq 'HASH') && (keys %$params_to_eval == 1)) {
        ($cv) = values %$params_to_eval;
      }
      elsif (defined $params_to_eval) {
        $cv = $params_to_eval;
      }
      else {
        $cv = '';
      }
    }
    $node->{computed_value} = $cv;

    if (my $parent = $node->{parent}) {
      my $parent_name = $parent->{name};
      if (defined $node->{parse_match} &&
       (ref $node->{parse_match} eq '')) {
        $parent->{parse_match} .= $node->{parse_match};
      }
    
      if (defined $alias) {
        if ($rules_details->{$parent_name}->{rule_count}->{$alias} > 1) {
          push @{$parent->{parameters}->{$alias}}, $cv;
          $node->{passed_params}->{$alias} = 1;
        }
        else {
          $parent->{parameters}->{$alias} = $cv;
          $node->{passed_params}->{$alias} = 0;
        }
      }
      else { # !defined alias
        foreach my $key (keys %$cv) {
          if ($rules_details->{$rule_name}->{rule_count}->{$key} > 1) {
            if (scalar(@{$cv->{$key}})) {
              push @{$parent->{parameters}->{$key}}, @{$cv->{$key}};
              $node->{passed_params}->{$key} = scalar(@{$cv->{$key}});
            }
          }
          elsif ($rules_details->{$parent_name}->{rule_count}->{$key} > 1) {
            push @{$parent->{parameters}->{$key}}, $cv->{$key};
            $node->{passed_params}->{$key} = 1;
          }
          else {
            $parent->{parameters}->{$key} = $cv->{$key};
            $node->{passed_params}->{$key} = 0;
          }
        }
      }
    }
  }

  return @results;
}

sub LOCATION {
  my ($text_ref, $value) = @_;
  my $substring = substr($$text_ref,0,$value+1);
  my $line_number = 1 + ($substring =~ tr/\n//);
  $substring =~ /([^\n]*)$/;
  my $line_position = length($1);
  return ($line_number, $line_position);
}

1;

__END__

=head1 NAME

Parse::Stallion - EBNF based regexp backtracking parser and tree evaluator.

=head1 SYNOPSIS

  use Parse::Stallion;

  my %rules = (rule_name_1 => ..rule_definition.. ,
   rule_name_2 => ..rule_definition.. ,
   ...);

  my $stallion = new Parse::Stallion(
    \%rules,
     # the following parameters are optional
   {start_rule => 'rule_name_1', #default the rule which is not a subrule
    do_evaluation_in_parsing => 0, #default 0
    max_steps => 200000, #default 1000000;
    do_not_compress_eval => 0, #default 0
    separator => '__XZ__', #default '__XZ__'
    parse_forward => sub {...}, #default no sub
    parse_backtrack => sub {...}, #default no sub
  });

  my $parse_info_hash = {}; # optional, little impact on performance
  my $parse_trace = []; # optional, some impact on performance
  my $result = $stallion->parse_and_evaluate($given_string,
    # usually omit the following
   {max_steps => 30000, #default from parser
    parse_info => $parse_info_hash, #if provided, parse info returned
    trace => $parse_trace # if provided, trace returned
   });
  # returns undef if unable to parse


Rule Definitions (may be abbreviated to first letter):

  AND('subrule_1', 'subrule_2', ..., EVALUATION(sub{...}))

  OR('subrule_1', 'subrule_2', ..., EVALUATION(sub{...}))

  MULTIPLE('subrule_1', EVALUATION(sub{...}))

  LEAF(qr/regex/, EVALUATION(sub{...}))

=head1 DESCRIPTION

Stallion parses and evaluates a string using entered grammar rules.
The parsing is done top-down via an initial start rule, in a depth first
search forming a parse tree.
When a rule does not match the parser backtracks to a node that has another
option.

For evaluating a tree node, the evaluation subroutine is given a reference
to a hash representing the returned values of the child nodes.
The evaluation may be done while creating the parse tree and reject a
match affecting which strings parse.
This allows complex grammars.

If the evaluation is not done while parsing, on a successful parse,
the tree is evaluated in bottom up, left to right order.

The grammars recognized are context free and are similar to those expressed in
Extended Backus-Naur Form (EBNF).

The object being parsed does not need to be a string.  Except for
the section on non-strings, the documentation assumes strings are being parsed.

=head2 COMPLETE EXAMPLES

The following examples read in two unsigned integers and adds them.

  use Parse::Stallion;

   my %basic_grammar = (
    expression =>
     AND('number',
      qr/\s*\+\s*/,
      'number',
      EVALUATION(
       sub {return $_[0]->{number}->[0] + $_[0]->{number}->[1]})
    ),
    number => LEAF(qr/\d+/,
      E(sub{return 0 + $_[0];}))
     #0 + $_[0] converts the matched string into a number
   );

   my $parser = new Parse::Stallion(\%basic_grammar);

   my $result = $parser->parse_and_evaluate('7+4');
   #$result should contain 11

   my %grammar_2 = (
    expression =>
     A('number',
      qr/\s*\+\s*/,
      {right_number => 'number'},
      E(sub {return $_[0]->{number} + $_[0]->{right_number}})
    ),
    number => L(qr/\d+/,
      EVALUATION(sub{return 0 + $_[0];}))
   );

   my $parser_2 = new Parse::Stallion(
    \%grammar_2, {start_rule => 'expression'});

   my $result_2 = $parser_2->parse_and_evaluate('8 + 5');
   #$result_2 should contain 13

   use Parse::Stallion::EBNF; #see documenation on Parse::Stallion::EBNF

   my $grammar_3 = 'start = (left.number qr/\s*\+\s*/ right.number)
      S{return $_[0]->{left} + $_[0]->{right}}S;
     number = qr/\d+/;';

   my $parser_3 = ebnf_new Parse::Stallion::EBNF($grammar_3);

   my $result_3 = $parser_3->parse_and_evaluate('1 + 6');
   #$result_3 should contain 7

=head2 RULES

There are 4 rule types: B<'LEAF'>, B<'AND'>, B<'OR'>, and B<'MULTIPLE'>.

Parsing begins from the start rule, if the 'start_rule' parameter
is omitted, the rule which is not a subrule is used as the start rule.
The start rule can be of any type, though if the start rule is a B<'LEAF'>,
the grammar is essentially just a regular expression.

After a successful parse, the external nodes correspond to the substrings
that the B<'LEAF'> rules matched; the other rule types correspond to the
internal nodes.

=head3 LEAF

A B<'LEAF'> rule contains a regexp that must match the beginning part of the
remaining input string, internally B<\A> is prepended to the regexp.
During parsing, when a B<'LEAF'> matches, the matched substring is
removed from the input string, though reattached if backtracking occurs.
The text LEAF is optional, regexp's are assumed to be leaves,  but then there
can be no EVALUATION routine for that leaf.

If the regexp matches but is empty, the matched value is set to an empty
string as opposed to an undefined value.

Examples (equivalent):

  LEAF(qr/xx\w+/)

  L(qr/xx\w+/)

  qr/xx\w+/

would match any perl word (\w+) starting with "xx".

See the section B<'LEAF DETAILS'> for other ways to handle leaves.

=head3 AND

An B<'AND'> rule contains a list of subrules that must be completely matched,
from left to right, for the 'and' rule to match.

Examples (equivalent):

  AND('rule_1', 'rule_2', 'rule_3')

  A('rule_1', 'rule_2', 'rule_3')

=head3 OR

An B<'OR'> rule contains a list of subrules, one of which must be matched
for the B<'OR'> rule to match.

During parsing, the subrules are attempted to be matched left to right.
If a subrule matches and then is subsequently backtracked, the parser
will try to match the next subrule.

Examples (equivalent):

  OR('rule_1', 'rule_2', 'rule_3')

  O('rule_1', 'rule_2', 'rule_3')

=head3 MULTIPLE (and OPTIONAL)

A B<'MULTIPLE'> rule matches if its subrule matches repeatedly between
a minimum and maximum number of times.
The first parameter to 'MULTIPLE' is the subrule, the next 2 optional parameters
are the minium and maximum repititions allowed.
The default minimum is 0 and the default maximum is "infinite", though
this is represented by setting the maximum to 0.

For there to be another repetition, the input string must have been
shortened, else it would be considered an illegal form of "left recursion".

By default the maximal number of possible matches of the repeating
rule are tried and then if backtracking occurs, the number of matches is
decremented.
If the parameter 'match_min_first' is passed in, the minimal number of matches
is tried first and the number of matches increases when backtracking.

Examples (equivalent):

  MULTIPLE('rule_1')

  M('rule_1')

  M('rule_1', 0, 0)

One can label a rule with the value B<'OPTIONAL'> that maps
to a B<'MULTIPLE'> rule with minimum 0 and maximum 1.

Examples (equivalent):

  OPTIONAL('rule_1')

  ZERO_OR_ONE('rule_1')

  Z('rule_1')

  MULTIPLE('rule_1', 0, 1)

to get one or more:

  MULTIPLE('rule_2', 1, 0)

=head3 SIMILARITY BETWEEN RULE TYPES.

The following rules all parse tree-wise equivalently and evaluate
equivalently since a B<MULTIPLE> rule that has at most 1 child does
not return an array ref.

  AND('subrule')

  O('subrule')

  MULTIPLE('subrule', 1, 1)

  M('subrule', 1, 1, 'match_min_first')

=head3 NESTED RULES

Rules can be nested inside of other rules.  See the section
B<EVALUATION> for how nested rules affect tree evaluations.

Example:

  sum => AND('number', MULTIPLE(AND('plus', 'number')));

is equivalent, parsing wise, to

  sum => A('number', 'plus_numbers');
  plus_numbers = M('plus_number');
  plus_number => A('plus', 'number');

=head3 ALIASES

One can also use an alias for a rule by a hash reference with a single
key/value pair.  This sets the name to the key when evaluating
the parsed expression and parsing the subrule specified by the value.

  adding =  A(
   'number', L(qr/\s*[+]\s*/),
     {right_number => 'number'},
   E(sub {return $_[0]->{number} + $_[0]->{right_number}})
  );

=head3 RULE NAMES

Rule names cannot contain the 'separator' substring '__XZ__', to avoid
confliciting with internally generated rule names.  This can be changed by
using the 'separator' parameter.

=head3 ENSURING RULES FORM COMPLETE GRAMMAR

Stallion ensures that a grammar is complete and croaks if the given grammar
has any rules not reachable from the start rule or if within any rule a
subrule does not exist.

=head2 PARSE_AND_EVALUATE

After setting up a Parse::Stallion parser, strings are parsed and evaluated
via parse_and_evaluate.  In scalar context, the returned value is the
returned value of the root node's evaluation routine.

=head3 RETURNED VALUES

To get details on the parsing from parse_and_evaluate, a parameter
parse_info should be passed an empty hash that will be filled in.
Unless an evaluation can return an 'undef' value, not true in the
examples provided, one can check if
the returned value is 'undef' to determine if an evaluation failed.

  my $parse_info = {};
  my $parse_trace = [];
  my $value =
   $stallion->parse_and_evaluate($given_string, {parse_info=>$parse_info,
    parse_trace => $parse_trace});

  $parse_info->{parse_succeeded}; # is 1 if the string parses, else 0.
  $parse_info->{number_of_steps}; # number of steps parsing took
  $parse_info->{start_rule};

  # $parse_trace contains one hash per step, the hash keys are
  #  1) rule_name
  #  2) moving_forward (value 0 if backtracking),
  #  3) moving_down (value 0 if moving up parse tree)
  #  4) value (position in string or value returned from parse_forward)
  #  5) node_creation_step, uniquely identifies node in parse tree
  #  6) parent_node_creation_step, parent in parse tree
  #  7) informative message of most recent parse step
  #  8) nodes of the current parse tree

  $parse_info->{tree}; # the parse tree if the string parses.

The tree is an Parse::Stallion object having a function, that converts a
tree into a string, each node consisting of one line:

  $parse_info->{tree}->stringify({values=>['name','parse_match']});

Internally generated node names, from rules generated by breaking up
the entered rules into subrules, will show up. The module
Parse::Stallion::EBNF shows the grammar with these generated subrules.

=head3 NUMBER OF PARSE STEPS

If the parsing reaches the maximum number of steps without completing a
parse tree, the parse fails (croak).  Each step is listed in the parse_trace.

A step is an action on a node, roughly speaking matching a
regex for a B<'leaf'> node, or moving forward or backtracking from a node.

The maximum number of steps can be changed, default 100,000.  If max_steps
is set to a negative number, then there is no limit on the number of steps.

  $stallion->parse_and_evaluate($string, {max_steps=>200000});

=head3 "LEFT RECURSION"

Parse::Stallion may encounter "left recursiveness"
during parsing in which case the parsing stops and a message is 'croak'ed.

"Left recursion" occurs during parsing when the same non-B<'leaf'> rule shows
up a second time on the parse tree with the at the same position
in the input string.

Illegal Case 1:

     expression => AND('expression', 'plus', 'term')

Illegal Case 2:

     rule_with_empty => AND('empty', 'rule_with_empty', 'other_rule')
     empty => qr//

Illegal Case 3:

     rule_with_optional => AND('nothing', 'optional_rule', 'nothing')
     nothing => AND('empty')
     empty => L(qr//)
     optional_rule => OPTIONAL('some_other_rule')
     some_other_rule => qr/x/

The 3rd case will detect left recursiveness if optional_rule does not
match and modify the input.

=head2 EVALUATION

Evaluation can occur during or after parsing.

Each rule may have an evaluation subroutine tied to it, if when defining
a rule there is no subroutine, a default "do nothing" subroutine is provided.
Subrules may have a subroutine tied to them though by default they have none.

When setting up a rule, one can specify the EVALUATION subroutine
by the parameter 'EVALUATION' or 'E'.
If the parameter is given a subroutine, that is used.
If the parameter is given a regexp, that is applied to the matched string
of the text and the first parenthized match is returned as the value.
Otherise the parameter within the EVALUATION is returned.

Each node has a computed value that is the result of calling its
evaluation routine.  The returned value of the parse is the
computed value of the root node.

There are two parameters to a node's evaluation routine.

The first parameter to the evaluation routine is either a
hash or a string:

If the node is a leaf regexp that has a parenthesized match inside,
what is matched by the first parenthesized match is the parameter.
Else if the node is a leaf then what is matched by the leaf is
the first parameter.
Else if 'USE_PARSE_MATCH()' has been set for the node's rule, a join
of all the matched strings of the nodes descendents is the parameter.

For other internal nodes, the first parameter is a hash.
The hash's keys are the named subrules of the node's rule, the values
are the computed value of the corresponding child node.  If a key could
repeat, the value is an array reference.

The second parameter to an evaluation routine is a hash to
several parameters.  These are:

   parse_this_ref # The object being parsed
   current_value # The current value if evaluation during parsing
   parameters # Same as first parameter if hash
   node_parse_match # Same as first parameter if USE_PARSE_MATCH
   parse_hash # Writeable hash used for parse (can store global variables)
   node_hash # Writeable hash used for node (combine with parse_forward)

By nesting a rule with an alias, the alias is used for the name of the
hash parameter instead of the rule name.

Examples:

   LEAF( qr/\w+/, E(sub {...})) # subroutine is called with word

   L( qr/(d)\w+/, E(sub {...})) # subroutine is called with 'd'

   L( qr/\s*\w+\s*/, E(qr/\s*(\w+)\s*/) # white space trimmed

   L( qr/\s*(\w+)\s*/) # white space trimmed

   qr/\s*(\w+)\s*/ # white space trimmed

   L( qr/\s*\w+\s*/, E('x')) # evaluates to value x

   L( qr/\s*\w+\s*/, E(['x','ss','t'])) # evaluates to array reference

   A( qr/a/, qr/b/, E(sub {...})) #params: $_[0]->{''}->['a','b']

   A( qr/a/, qr/b/, E(sub {...}),
    USE_PARSE_MATCH()) #params: $_[0] eq 'ab'

   A( {f=>qr/a/}, {f=>qr/b/},
    E(sub {...})) #params: $_[0]->{'f'}->['a','b']

A function, LOCATION is provided that takes a string reference and a position
in the string and computes the line number and tab value of the given position.
This can be used in evaluation functions if one passes in the object being
parsed (second argument) and the current value (third argument).
This is used in Parse::Stallion::EBNF to show where within the input grammar
an error occurs, see for example test case t/ebnf_in.t.

=head3 EVALUATION AFTER PARSING

If after parsing, Stallion will evaluate the parse tree in a bottom up
left to right traversal.

=head3 EVALUATION (AND UNEVALUATION) DURING PARSING

If the do_evaluation_in_parsing is set when a Parse::Stallion object is
created the evaluation occurs during the parsing instead of afterwards.
Alternatively, if there exists any UNEVALUATION routine, the evaluation
is done during parsing.

Every time a node is matched, its evaluation routine is called with a
hash as it would be during evaluation after parsing.
A second parameter is also passed in which corresponds to the current
object being parsed.  This allows look ahead.

The evaluation routine may return a second parameter that tells
Parse::Stallion to reject or not reject the match.  This allows more
control over what can be parsed.

The same node may be evaluated several times due to backtracking.
One must be careful either to not change the references/objects passed
in to the evaluation routine or to undo changes in an unevaluation routine.
An unevaluation routine is called when backtracking reverts
back to a node, the parameters are the same as for the evaluation routine.
UNEVALUATION (alternatively U) are used to set the subroutine.

The following example shows a B<'leaf'> rule that matches all words except
for those marked in the hash %keywords:

  our %keywords = (...);
  my %grammar = (...
   leaf => L(
     qr/\w+/,
     E(sub {if ($keywords{$_[0]}) {return (undef, 1)} return $_[0]}),
     U(), #forces do_evaluation_in_parsing
   ),
  ...
  );

=head4 EVALUATION DURING PARSING EXAMPLE

In this example, the first statement tells a truth about the number of
elements in a list, the second tells whether or not the first statement is
true.  If the second statement is true, the string parses.

  my %parsing_rules = (
   start_expression =>
    AND('two_statements', qr/\z/,
     E(sub {return $_[0]->{'two_statements'}})
   ),
   two_statements =>
     A('list_statement','truth_statement',
      EVALUATION(sub {
       if ($_[0]->{list_statement} != $_[0]->{truth_statement}) {
         return (undef, 1);
       }
       return 1;
     })
   ),
   list_statement =>
     A('count_statement', 'list',
      E(sub {
       if ($_[0]->{count_statement} == scalar(@{$_[0]->{list}})) {
         return 1;
       }
       return 0;
     })
   ),
   count_statement =>
     A(qr/there are /i,'number',L(qr/ elements in /),
      E(sub { return $_[0]->{number}; })
    ),
   number =>
    L(qr/\d+/,
     E(sub { return 0 + shift; })
   ),
   list => A('number', M(A(qr/\,/}, 'number')),
     EVALUATION(sub {return $_[0]->{number}})
   ),
   truth_statement =>
     O({t => qr/\. that is the truth\./},
      {t=>qr/\. that is not the truth\./},
      E(sub {
       if ($_[0]->{t} =~ /not/) {
         return 0;
       }
       return 1;
     })
   ),
  );
  
  my $how_many_parser = new Parse::Stallion(
   \%parsing_rules,
   {do_evaluation_in_parsing => 1,
    start_rule => 'start_expression',
  });
  
  $result = $how_many_parser->parse_and_evaluate(
    "there are 5 elements in 5,4,3,2,1. that is the truth.");
  
  print "$result should be 1\n";
  
  $result = $how_many_parser->parse_and_evaluate(
    "there are 5 elements in 5,4,3,1. that is not the truth.");
  
  print "$result should be 1\n";
  
  $result = $how_many_parser->parse_and_evaluate(
    "there are 5 elements in 5,4,3,1. that is the truth.");
  
  print "$result should be undef\n";


=head3 DEFAULT EVALUATION ROUTINE

If a rule does not have an evaluation routine specified, it is as if
a generic subroutine is used.

=head4 Generic Evaluation Routine 1

=over

=item *

If the passed in hash reference has only one key, then the value
of that key in the hash reference is returned.

=item *

If the passed in hash reference has more than one key, then the hash
reference is returned.

=back

It is as if this routine were run:

  sub {
    my $parameters = shift;
    if (ref $parameters eq 'HASH') {
      if (keys %$parameters == 1) {
        my ($key) = keys %$parameters;
        return $parameters->{$key};
      }
    }
    return $parameters;
  }

=head4 Generic Evaluation Routine 2

If do_not_compress_eval is set when creating the parser,
it is as if this routine were run:

  sub {
    return shift;
  }

Example:

  my %no_eval_rules = (
   start_rule => A('term',
    M(A({plus=>qr/\s*\+\s*/}, 'term'))),
   term => A({left=>'number'},
    M(A({times=>qr/\s*\*\s*/},
     {right=>'number'}))),
   number => qr/\s*\d*\s*/
  );                               
                      
  my $no_eval_parser = new Parse::Stallion(\%no_eval_rules,
   {do_not_compress_eval => 0});

  $result = $no_eval_parser->parse_and_evaluate("7+4*8");
   
  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ '7',
                { 'left' => '4',
                  'right' => [ '8' ],
                  'times' => [ '*' ] } ] }

  my $dnce_no_eval_parser = new Parse::Stallion(\%no_eval_rules,
   {do_not_compress_eval => 1});

  $result = $dnce_no_eval_parser->parse_and_evaluate("7+4*8");

  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ { 'left' => '7' },
                { 'left' => '4',
                  'right' => [ '8' ],
                  'times' => [ '*' ] } ] }

=head3 Parameter types to Evaluation Routines

If a named parameter could appear more than once, it is passed
as an array, else as a scalar.  Being passed as an array could be
caused by the name being within a B<'MULTIPLE'> rule which does not
have maximum children of 1 or occuring more than once within the
subrules of an B<'AND'> rule.

The routine which_parameters_are_arrays returns a hash of the
possible values passed to an evaluation routine.  For a given key,
if the value is 1, the key would be passed to the evaluation routine
as an array, if the value is 0, it would be passed as a scalar.

=head3 MORE COMPLICATED EXAMPLE

  The following is a simple calculator:

   %calculator_rules = (
    start_expression => A(
      'expression', qr/\z/,
      E(sub {return $_[0]->{expression}})
     ),
    expression => A(
      'term', 
       M(A('plus_or_minus', 'term')),
      E(sub {my $to_combine = $_[0]->{term};
       my $plus_or_minus = $_[0]->{plus_or_minus};
       my $value = $to_combine->[0];
       for my $i (1..$#{$to_combine}) {
         if ($plus_or_minus->[$i-1] eq '+') {
           $value += $to_combine->[$i];
         }
         else {
           $value -= $to_combine->[$i];
         }
       }
       return $value;
      })
     ),
    term => A(
      'number', 
       M(A('times_or_divide', 'number')),
       E(sub {my $to_combine = $_[0]->{number};
       my $times_or_divide = $_[0]->{times_or_divide};
       my $value = $to_combine->[0];
       for my $i (1..$#{$to_combine}) {
         if ($times_or_divide->[$i-1] eq '*') {
           $value *= $to_combine->[$i];
         }
         else {
           $value /= $to_combine->[$i]; #does not check for zero
         }
       }
       return $value;
      })
    ),
    number => L(
      qr/\s*[+\-]?(\d+(\.\d*)?|\.\d+)\s*/,
      E(sub{ return 0 + $_[0]; })
    ),
    plus_or_minus => qr/\s*([\-+])\s*/,
    times_or_divide => qr/\s*([*\/])\s*/
   );

   $calculator_parser = new Parse::Stallion(\%calculator_rules,
     {start_rule => 'start_expression'
   });

   my $result = $calculator_parser->parse_and_evaluate("3+7*4");
   # $result should contain 31

  my $array_p = $calculator_parser->which_parameters_are_arrays('term');
  # $array_p would be {number => 1, times_or_divide => 1}

  $array_p = $calculator_parser->which_parameters_are_arrays(
   'start_expression');
  # $array_p would be {expression => 0}

=head3 STRING_EVALUATION

Instead of passing an evaluation subroutine, one can pass in the
string of a subroutine via STRING_EVALAUATION (or SE).  The string
is modified so that the passed in parameters become local variables.

Example:

    a_rule => A('x_1', 'x_2', 'x_3', 'x_1'),
      SE('#comment'));

results in the evaluation routine equivalent to:

     sub {
     $x_1 = $_[0]->{x_1};
     $x_2 = $_[0]->{x_2};
     $x_3 = $_[0]->{x_3};
     #comment
     }

If 'use_parse_match' or rule is a leaf then $_ is set to the parameter $_[0];
else, $_ is the one unnamed rule or an array ref of the unnamed rules:

    $_ = $_[0]->{''};

=head2 LEAF DETAILS

Leaf rules can be set up as follows:

  LEAF($leaf_arg, PARSE_FORWARD(sub{...}), PARSE_BACKTRACK(sub{...}),
   EVALUATION(sub{...}), UNEVALUATION(sub{...}), DISPLAY($display));

If $leaf_arg is a Regexp, it is converted into a hash ref:
{regex_match => $leaf_arg} for internal purposes.

If a default PARSE_FORWARD is not provided then
a regexp match is attempted on the string being parsed at the
current_value's position.
Default parse_forward and parse_backtrack subroutines can be provided
for leaves.

The subroutine in PARSE_FORWARD (or PF) is called when moving forwards
during the parse.  Its one parameter is a hash of:
    parse_this_ref # The object being parsed
    current_value # current value of parse
    parameters # Same as to evaluation routine of leaf node's parent if
               # evaluation in parsing and only known parameters
    node_parse_match # Same as to evaluation routine of leaf node's parent
               # if evaluation in parsing and only existing descendents
    parse_hash # hash for storing global variables during given parse
    node_hash # hash for storing variables of parent's node
    leaf_rule_info # $leaf_arg's

The regexp matching done if there is no PARSE_FORWARD routine is similar to:

If the parsing should continue forward it should return an array with
the first argument true (1), the second argument a "parse match" to store
as what was matched, and the thrid argument the new current value.
Else it should return 0.

The subroutine in PARSE_BACKTRACK (or PB) is called when backtracking
through a leaf.  Its one parameter is a hash of
    parse_this_ref # The object being parsed
    current_value # current value of parse
    value_when_entered # value when leaf was created
    match # value that was returned by parse_forward as match
    parameters # Same as to evaluation routine of leaf node's parent if
               # evaluation in parsing and only known parameters
    node_parse_match # Same as to evaluation routine of leaf node's parent
               # if evaluation in parsing and only existing descendents
    parse_hash # hash for storing global variables during given parse
    node_hash # hash for storing variables of parent's node
    leaf_rule_info # $leaf_arg's

It should return false.  If it returns true, then the parsing immediately
ends in failure.  This can be used to set up a rule

  pass_this_no_backtrack => L(qr//,PB(sub{return 1}))

that if encountered during parsing during a backtrack means that the parsing
will end.

The string $display is used in the related module Parse::Stallion::EBNF
as to the string to show for the leaf rule.

EVALUATION and UNEVALUATION are explained in the section B<'EVALUATION'>.

=head2 PARSING NON-STRINGS

Four subroutines may be provided: a default B<'leaf'>
rule matcher/modifier for when the parser is moving forward and
a default B<'leaf'> rule unmodifier for when the parser is backtracking.
A third optional subroutine, initial_value, sets the initial current value
else it is 0.

The fourth subroutine, final_value, should return the final value
of a successful parse for a given object.  This subroutine is
similar to parsing strings ensuring, or not ensuring,  that the entire
string is matched instead of matching only a portion.

  my $object_parser = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
       my $parameters = shift;
       ...
       return ($true_if_object_matches_rule,
        $value_to_store_in_leaf_node,
        $value_equal_or_greater_than_current_value);
     },
    parse_backtrack =>
     sub {
       my $parameters = shift;
       ...
       return; #else parsing halts
      },
    initial_value => sub {my ($object_ref, $parse_hash) = @_;
       ...
       return $initial_value;
    },
    final_value =>
     sub {my ($object_ref, $current_value, $parse_hash) = @_;
        ...
       return $final_value; # parse ends if $final_value==$current_value
     },
  });

When evaluating the parse tree, the parameters to the B<'leaf'> nodes are
the values returned in parse_forward, $value_to_store_in_leaf_node.
These values are joined together for parse_match.

The script object_string.pl in the example directory shows how to use this.

=head3 B<'LEAF'> LEAF PARSE FORWARD/BACKTRACK

All B<'leaf'> rules need to be set up such that when the parser is moving
forward and reaches a B<'leaf'>, the
B<'leaf'> rule attempts to match the object being parsed at the current value.
If there is a match, then the current_value may increase.

When backtracking, the object being parsed should be reverted, if changed, to
the state before being matched by the B<'leaf'> rule.

=head3 NON_DECREASING VALUE

The third value returned from parse_forward should be equal or
greater than the $current_value that was passed in.

This value is used to detect and prevent "left recursion" by not
allowing a non-B<'leaf'> rule to repeat at the same value.
B<'Multiple'> rules are prevented from repeating more than once at
the same value.

The value also cuts down on the number of steps by allowing the parser to
not repeat dead-end parses.  If during the parse, the same rule is
attempted a second time on the parse object with the same value,
and the first parse did not succeed, the parser will begin backtracking.

In parsing a string, the value is the current position within the string.

=head3 STRINGS

By default, strings are matched, which, if a reference to the
string instead of the string is passed in to parse_and_evaluate, is similar to
that found in the test case object_string.t:

  my $calculator_stallion = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
      my $parameters = shift;
      my $input_string_ref = $parameters->{parse_this_ref};
      my $rule_definition = $parameters->{leaf_rule_info};
      my $m = $rule_definition->{regex_match};
      if ($$input_string_ref =~ s/\A($m)//) {
        return (1, $1, 0 - length($string));
      }
      return 0;
     },

    parse_backtrack =>
     sub {
      my $parameters = shift;
      my $input_string_ref = $parameters->{parse_this_ref};
      my $stored_value = $parameters->{match};
      if (defined $stored_value) {
        $$input_string_ref = $stored_value.$$input_string_ref;
      }
      return;
     },

    initial_value =>
     sub {
       my $input_string_ref = shift;
       return 0 - length($$input_string_ref);
     },

    final_value =>
     sub {
       return 0;
     }
  });

=head2 EXPORT

The following are EXPORTED from this module:

 A AND E EVALUATION L LEAF LEAF_DISPLAY LOCATION M MULTIPLE O OPTIONAL
 OR PARSE_FORWARD PARSE_BACKTRACK PB PF SE STRING_EVALUATION U
 UNEVALUATION USE_PARSE_MATCH Z ZERO_OR_ONE

=head1 PERL Requirements

Parse::Stallion's installation uses Test::More and Time::Local
requiring perl 5.6 or higher.
Parse::Stallion should work with earlier versions of perl, neither
of those modules is required outside of the test cases for installation.

=head1 AUTHOR

Arthur Goldstein, E<lt>arthur@acm.orgE<gt>

=head1 ACKNOWLEDGEMENTS

Damian Conway and Greg London. 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-9 by Arthur Goldstein.  All Rights Reserved.

This module is free software. It may be used, redistributed and/or modified
under the terms of the Perl Artistic License
(see http://www.perl.com/perl/misc/Artistic.html)


=head1 BUGS

Please email in bug reports.

=head1 TO DO AND FUTURE POSSIBLE CHANGES

License

Please send in suggestions.

=head1 SEE ALSO

example directory (includes stallion.html, a javascript translation of
 Parse::Stallion) and test case directory t

Parse::Stallion::EBNF. Outputs grammars in more readable form.  Also
contains an example of how one could input a grammar from a string, similar
to how many parsers take their input.

Parse::Stallion::CSV. Example of how to create a parser from specification.

Perl 6 grammars.

lex, yacc, ..., other parsers.

=cut
