#Copyright 2007-9 Arthur S Goldstein

package Parse::Stallion::Talon;
use Carp;
use strict;
use warnings;
use 5.006;

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
  my $parsing_info = {parse_stallion => $parameters};
  return bless $parsing_info, $class;
}

sub parse_leaf {
  my $parsing_info = shift;
  my $parameters = shift;
  my $start_rule_name = shift;
  my $parse_stallion = $parsing_info->{parse_stallion};
  my $parse_hash = $parameters->{parse_hash};
  my $parse_this_ref = $parse_hash->{parse_this_ref} =
   $parameters->{parse_this_ref};
  my $parse_this_length;
  if (defined $parse_this_ref) {
    $parse_this_length = length($$parse_this_ref);
  }
  else {
    $parse_this_length = 0;
  }
  my $do_evaluation_in_parsing = $parse_stallion->{do_evaluation_in_parsing};
  my $start_node = $parse_stallion->{rule}->{$start_rule_name};
  my $initial_position;
  if (defined $parameters->{start_position}) {
    $initial_position = $parameters->{start_position};
  }
  elsif ($parse_stallion->{initial_position_routine}) {
    $initial_position = $parse_stallion->{initial_position_routine}
    ($parse_this_ref, $parse_hash);
  }
  else {
    $initial_position = $parameters->{initial_pos} || 0;
  }

  my $tree;
  my @bottom_up_left_to_right;
  my $current_position;
  my $continue_forward;
  my $match;

  if (my $pf = $start_node->{parse_forward}) {
    $parse_hash->{parent_node} = {};
    $parse_hash->{current_position} = $initial_position;
    $parse_hash->{rule_name} = $start_rule_name;
    ($continue_forward, $match, $current_position) =
     &{$pf}($parse_hash);
    if (defined $current_position) {
      if ($current_position < $initial_position) {
        croak ("Parse forward on $start_rule_name resulted in
         backwards progress ($initial_position, $current_position)");
      }
    }
    else {
      $current_position = $initial_position;
    }
  }
  elsif (my $x = $start_node->{regex_match}) {
    pos $$parse_this_ref = $initial_position;
    if ($$parse_this_ref =~ m/$x/cg) {
      if (defined $2) {$match = $2;}
      else {$match = $1;}
      $continue_forward = 1;
      $current_position = pos $$parse_this_ref;
    }
    else {
      $continue_forward = 0;
    }
  }
  else {
    croak ("Cannot handle leaf $start_rule_name");
  }
  if ($continue_forward) {
    $tree = {
      name => $start_rule_name,
      alias => $start_node->{alias},
      steps => 1,
      parent => undef,
      position_when_entered => $initial_position,
      position_when_completed => $current_position,
      parse_match => $match,
      child_count => 0
    };
    my $reject;
    if ($do_evaluation_in_parsing) {
      $parameters->{nodes} = [$tree];
      $parse_hash->{current_position} = $current_position;
      (undef, $reject) = $parse_stallion->new_evaluate_tree_node(
       $parameters);
    }
    if (defined $reject && $reject) {
      $continue_forward = 0;
    }
    elsif (
     (($parse_stallion->{final_position_routine} &&
     (&{$parse_stallion->{final_position_routine}}($parse_this_ref,
      $current_position, $parse_hash) != $current_position))
     ||
      (!($parse_stallion->{final_position_routine}) &&
       ($parse_this_length != $current_position)))) {
      $continue_forward = 0;
    }
  }
  if ($continue_forward) {
    push @bottom_up_left_to_right, $tree;
  }
  else {
    $tree = undef;
  }


  my $results = $parameters->{parse_info};
  $results->{start_rule} = $start_rule_name;
  $results->{number_of_steps} = 1;
  $results->{final_position} = $current_position;
  $results->{final_position_rule} = $start_rule_name;
  $results->{parse_backtrack_value} = undef;
  $results->{maximum_position} = $current_position;
  $results->{maximum_position_rule} = $start_rule_name;
  $results->{parse_succeeded} = $continue_forward;
  $results->{tree} = $tree;
  $results->{bottom_up_left_to_right} = \@bottom_up_left_to_right;
  if ($do_evaluation_in_parsing) {
    $results->{parsing_evaluation} = $tree->{computed_value};
  }
  return $results;
}

sub parse {
  my $parsing_info = shift;
  my $parse_stallion = $parsing_info->{parse_stallion};
  my $parameters = shift;
  my $rule = $parse_stallion->{rule};
  my $start_rule;
  if (defined $parameters->{start_rule}) {
    if (!defined $rule->{$parameters->{start_rule}}) {
      croak ("Unknown start rule ".$parameters->{start_rule});
    }
    $start_rule = $parameters->{start_rule};
  }
  else {
    $start_rule = $parse_stallion->{start_rule};
  }
  if ($rule->{$start_rule}->{leaf_rule}) {
    return $parsing_info->parse_leaf($parameters, $start_rule);
  }
  my $parse_trace = $parameters->{parse_trace};
  my $parse_hash = $parameters->{parse_hash};
  my $parse_this_ref = $parse_hash->{parse_this_ref} =
   $parameters->{parse_this_ref};
  my $max_steps = $parameters->{max_steps} || $parse_stallion->{max_steps};
  my $no_max_steps = 0;
  if ($max_steps < 0) {
    $no_max_steps = 1;
    $max_steps = 1000000;
  }
  my @bottom_up_left_to_right;
  my $parse_this_length;
  if (defined $parse_this_ref) {
    $parse_this_length = length($$parse_this_ref);
  }
  else {
    $parse_this_length = 0;
  }
  my $move_back_mode = 0;

  my $first_alias =
   'b'.$parse_stallion->{separator}.$parse_stallion->{separator};

  my $current_position;
  if (defined $parameters->{start_position}) {
    $current_position = $parameters->{start_position};
  }
  elsif ($parse_stallion->{initial_position_routine}) {
    $current_position = $parse_stallion->{initial_position_routine}
    ($parse_this_ref, $parse_hash);
  }
  else {
    $current_position = $parameters->{initial_pos} || 0;
  }
  my $results = $parameters->{parse_info};
  $results->{start_position} = $current_position;
  my $maximum_position = $current_position;
  my $maximum_position_rule = $start_rule;

  my $any_minimize_children = $parse_stallion->{any_minimize_children} || 0;
  my $any_match_once = $parse_stallion->{any_match_once} || 0;
  my $any_parse_forward = $parse_stallion->{any_parse_forward} || 0;
  my $any_parse_backtrack = $parse_stallion->{any_parse_backtrack} || 0;
  my $fast_move_back = $parse_stallion->{fast_move_back};
  my $do_evaluation_in_parsing = $parse_stallion->{do_evaluation_in_parsing};
  my $bottom_up;
  if ($do_evaluation_in_parsing || $parse_stallion->{no_evaluation}) {
    $bottom_up = 0;
  }
  else {
    $bottom_up = 1;
  }

  my $tree = {
    name => $start_rule,
    steps => 0,
    alias => $first_alias,
    position_when_entered => $current_position,
    parent => undef,
    children => [],
    child_count => 0
  };
  bless($tree, 'Parse::Stallion::Talon');

  my $current_node = $tree;
  my $moving_forward = 1;
  my $moving_down = 1;
  my $steps = 0;
  my %active_rules_positions;
  my $message = 'Start of Parse';
  my ($new_rule_name, $new_alias);

  my $node_completed = 0;
  my $create_child = 0;
  my $move_back_to_child = 0;
  my $remove_node = 0;
  my %blocked;
  my $new_rule;
  my $new_sub_rule;
  my $continue_forward = 1;
  my ($match, $re_match);
  my $previous_position;
  my $current_node_name = $current_node->{name};
  my $current_rule = $rule->{$current_node_name};
  my $end_parse_now = 0;

  while (($steps < $max_steps) && $current_node) {
    while ($current_node && (++$steps <= $max_steps)) {
      if ($parse_trace) {
        my $parent_step = 0;
        if ($current_node->{parent}) {
          $parent_step = $current_node->{parent}->{steps};
        }
        push @$parse_trace, {
         rule_name => $current_node_name,
         moving_forward => $moving_forward,
         moving_down => $moving_down,
         position => $current_position,
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
            $new_sub_rule = $current_rule->{subrule_list}->[0];
            $new_rule_name = $new_sub_rule->{name};
            $new_alias = $new_sub_rule->{alias};
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
            $new_sub_rule = $current_rule->{subrule_list}->[
             $current_node->{child_count}];
            $new_rule_name = $new_sub_rule->{name};
            $new_alias = $new_sub_rule->{alias};
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
          $remove_node = 1;
        }
        elsif ($current_rule->{or_rule}) {
          if ($moving_down) {
            $move_back_to_child = 1;
          }
          else {
            if (!$move_back_mode && (++$current_node->{or_child_number} <
             $current_rule->{subrule_list_count})) {
              $new_sub_rule = $current_rule->{subrule_list}->[
               $current_node->{or_child_number}];
              $new_rule_name = $new_sub_rule->{name};
              $new_alias = $new_sub_rule->{alias};
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
        elsif (!$move_back_mode && (((!$any_minimize_children ||
         !$current_rule->{minimize_children}) && !$moving_down) &&
         (!$current_rule->{minimum_child} ||
         ($current_rule->{minimum_child} <= $current_node->{child_count})))) {
          $node_completed = 1;
        }
        elsif (!$move_back_mode && (($any_minimize_children &&
         $current_rule->{minimize_children} && $moving_down) &&
         (!$current_rule->{maximum_child} ||
         ($current_rule->{maximum_child} > $current_node->{child_count})))) {
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
        if ($blocked{$new_rule_name}{$current_position}) {
          $message =
           "Rule $new_rule_name blocked before on position $current_position"
           if $parse_trace;
          $moving_forward = 0;
          $moving_down = 0;
        }
        else {
          $new_rule = $rule->{$new_rule_name};
          $previous_position = $current_position;
          if ($any_parse_forward && (my $pf = $new_rule->{parse_forward})) {
            $parse_hash->{parent_node} = $current_node;
            $parse_hash->{current_position} = $current_position;
            $parse_hash->{rule_name} = $new_rule_name;
            ($continue_forward, $match, $current_position) =
             &{$pf}($parse_hash);
            if (defined $current_position) {
              if ($current_position < $previous_position) {
                croak ("Parse forward on $new_rule_name resulted in
                 backward progress ($previous_position, $current_position)");
              }
            }
            else {
              $current_position = $previous_position;
            }
          }
          elsif (my $x = $new_rule->{regex_match}) {
            pos $$parse_this_ref = $current_position;
            if ($$parse_this_ref =~ m/$x/cg) {
              if (defined $2) {$match = $2;}
              else {$match = $1;}
              $continue_forward = 1;
              $current_position = pos $$parse_this_ref;
              $message .= 'Leaf matched' if $parse_trace;
            }
            else {
              $continue_forward = 0;
              $message .= 'Leaf not matched' if $parse_trace;
            }
          }
          else {
            $match = undef;
          }

          if ($continue_forward) {
            if ($current_position > $maximum_position) {
              $maximum_position = $current_position;
              $maximum_position_rule = $new_rule_name;
            }
            my $new_node = {
              name => $new_rule_name,
              alias => $new_alias,
              steps => $steps,
              parent => $current_node,
              position_when_entered => $previous_position,
              parse_match => $match,
              child_count => 0
            };
            if ($new_rule->{leaf_rule}) {
              $node_completed = 1;
            }
            elsif ($active_rules_positions{$new_rule_name}{$current_position}++)
            {
              croak ("$new_rule_name duplicated at position $current_position");
            }
            else {
              $moving_forward = 1;
              $moving_down = 1;
            }
            push @{$current_node->{children}}, $new_node;
            $current_node->{child_count}++;
            $current_node = $new_node;
            $current_node_name = $new_rule_name;
            $current_rule = $rule->{$current_node_name};
            $message = "Creating child $new_rule_name on step $steps for ".
             "node created on step "
             .$current_node->{steps} if $parse_trace;
          }
          else {
            $continue_forward = 1;
            $moving_forward = 0;
            $moving_down = 0;
          }
        }
      }

      if ($node_completed) {
        $node_completed = 0;
        if ($current_node->{__ventured}->{$current_position}++) {
          $message .= " Already ventured beyond node at position "
           if $parse_trace;
          $moving_forward = 0;
          $moving_down = 1;
        }
        elsif ($current_position == $current_node->{position_when_entered}
         && $current_node->{parent} &&
         (defined $rule->{$current_node->{parent}->{name}}->{maximum_child})
         && ($current_node->{parent}->{child_count} >
         $rule->{$current_node->{parent}->{name}}->{minimum_child})
         ) {
          $message .= " Last child empty " if $parse_trace;
          $message .= " Child of multiple cannot be empty " if $parse_trace;
          $moving_forward = 0;
          $moving_down = 1;
        }
        else {
          my $reject;
          if ($do_evaluation_in_parsing) {
            $parameters->{nodes} = [$current_node];
            $parse_hash->{current_position} = $current_position;
            (undef, $reject) = $parse_stallion->new_evaluate_tree_node(
             $parameters);
          }
          if (defined $reject && $reject) {
            $moving_forward = 0;
            $moving_down = 1;
            $message .= " Node rejected" if $parse_trace;
          }
          else {
            push @bottom_up_left_to_right, $current_node if $bottom_up;
            $current_node->{'beyond'} = 1;
            $message .= " Completed node created on step ".
             $current_node->{steps} if $parse_trace;
            $moving_down = 0;
            $moving_forward = 1;
            delete $active_rules_positions{$current_node_name}
              {$current_node->{position_when_entered}};
            $current_node->{position_when_completed} = $current_position;
            if ($current_node = $current_node->{parent}) {
              $current_node_name = $current_node->{name};;
              $current_rule = $rule->{$current_node_name};
            }
          }
        }
      }
      elsif ($move_back_to_child) {
        $move_back_to_child = 0;
        $message .= " Backtracking to child" if $parse_trace;
        $moving_down = 1;
        $moving_forward = 0;
        pop @bottom_up_left_to_right if $bottom_up;
        $current_node =
         $current_node->{children}->[$current_node->{child_count}-1];
        $current_node_name = $current_node->{name};
        $current_rule = $rule->{$current_node_name};
        $active_rules_positions{$current_node_name}
         {$current_node->{position_when_entered}} = 1;
        if ($do_evaluation_in_parsing) {
          $parameters->{node} = $current_node;
          $parse_stallion->new_unevaluate_tree_node($parameters);
        }
        if ($any_match_once && !$move_back_mode
         && $rule->{$current_node_name}->{match_once}) {

          if ($fast_move_back) {
            $remove_node = 1;
            $message .= ". Fast Move Back " if $parse_trace;
          }
          else {
            $move_back_mode = 1;
            $current_node->{__move_back_to} = 1;
            $message .= ". Move Back Mode Enabled " if $parse_trace;
          }
        }
      }

      if ($remove_node) {
        $remove_node = 0;
        $moving_forward = 0;
        $moving_down = 0;
        $current_position = $current_node->{position_when_entered};
        if (!$current_node->{'beyond'}) {
          $blocked{$current_node_name}{$current_position} = 1;
          $message .= " Blocked node, " if $parse_trace;
        }
        delete $active_rules_positions{$current_node_name}{$current_position};
        $message .= " Removed node created on step ".$current_node->{steps}
         if $parse_trace;
        $parse_hash->{parse_match} = $current_node->{parse_match};
        if ($move_back_mode && $current_node->{__move_back_to}) {
          $move_back_mode = 0;
          $message .= ". Move Back Mode Completed"
           if $parse_trace;
        }
        $current_node = $current_node->{parent};
        if (defined $current_node) {
          pop @{$current_node->{children}};
          $current_node->{child_count}--;
          if ($any_parse_backtrack && $current_rule->{parse_backtrack}) {
            $parse_hash->{parent_node} = $current_node;
            $parse_hash->{current_position} = $current_position;
            $parse_hash->{rule_name} = $current_node_name;
            $end_parse_now = &{$current_rule->{parse_backtrack}}
              ($parse_hash);
            if ($end_parse_now) {
              $current_node = undef;
              $moving_forward = 0;
              last;
            }
          }
          $current_node_name = $current_node->{name};
          $current_rule = $rule->{$current_node_name};
        }
        delete $parse_hash->{parse_match};
      }
    }
    if (!$current_node && $moving_forward &&
     (($parse_stallion->{final_position_routine} &&
     (&{$parse_stallion->{final_position_routine}}($parse_this_ref,
      $current_position, $parse_hash) != $current_position))
     ||
      (!($parse_stallion->{final_position_routine}) &&
       ($parse_this_length != $current_position)))) {

      $moving_forward = 0;
      $moving_down = 1;
      $current_node = $tree;
      $current_node_name = $current_node->{name};
      $message .= ' . At top of tree but did not parse entire object'
       if $parse_trace;
      pop @bottom_up_left_to_right if $bottom_up;
      if ($any_match_once
       && $rule->{$current_node_name}->{match_once}) {
        if ($fast_move_back) {
          $current_node = undef;
          $message .= ". Fast Move Back " if $parse_trace;
        }
        else {
          $move_back_mode = 1;
          $current_node->{__move_back_to} = 1;
          $message .= ". Move Back Mode Enabled " if $parse_trace;
        }
      }
    }
    if ($no_max_steps && ($steps == $max_steps)) {
      $max_steps += 1000000;
    }
  }
  $results->{start_rule} = $start_rule;
  $results->{number_of_steps} = $steps;
  $results->{final_position} = $current_position;
  $results->{final_position_rule} = $current_node_name;
  $results->{parse_backtrack_value} = $end_parse_now;
  $results->{maximum_position} = $maximum_position;
  $results->{maximum_position_rule} = $maximum_position_rule;
  $results->{tree} = $tree;
  $results->{bottom_up_left_to_right} = \@bottom_up_left_to_right;
  if ($steps >= $max_steps) {
    croak ("Not enough steps to do parse, max set at $max_steps");
  }
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
our $VERSION = '0.90';
our @ISA = qw(Exporter);
our @EXPORT =
 qw(A AND O OR LEAF L MATCH_ONCE M MULTIPLE OPTIONAL ZERO_OR_ONE Z
    E EVALUATION U UNEVALUATION PF PARSE_FORWARD PB PARSE_BACKTRACK
    RULE_INFO R TERMINAL TOKEN
    LEAF_DISPLAY USE_STRING_MATCH LOCATION SE STRING_EVALUATION);
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
  $self->{max_steps} = $parameters->{max_steps} || 1000000;
  $self->{self} = $self;
  if ($self->{no_evaluation} = $parameters->{no_evaluation} || 0) {
    $self->{do_evaluation_in_parsing} = 0;
  }
  else {
    $self->{do_evaluation_in_parsing} = $parameters->{do_evaluation_in_parsing}
     || 0;
  }
  $self->{unreachable_rules_allowed} = $parameters->{unreachable_rules_allowed}
   || 0;
  $self->{do_not_compress_eval} = $parameters->{do_not_compress_eval} || 0;
  $self->{traversal_only} = $parameters->{traversal_only} || 0;
  $self->{separator} = $parameters->{separator} || $self->{separator};
  if (defined $parameters->{parse_forward}) {
    $self->{leaf_parse_forward} = $parameters->{parse_forward};
    $self->{any_parse_forward} = 1;
  }
  if (defined $parameters->{parse_backtrack}) {
    $self->{leaf_parse_backtrack} = $parameters->{parse_backtrack};
    $self->{any_parse_backtrack} = 1;
  }
  $self->{initial_position_routine} = $parameters->{initial_position_routine};
  if (defined $parameters->{final_position_routine}) {
    if ($parameters->{need_not_match_whole_string}) {
      croak ("only 1: final_position_routine And need_not_match_whole_string");
    }
    $self->{final_position_routine} = $parameters->{final_position_routine};
  }
  elsif ($parameters->{need_not_match_whole_string}) {
    $self->{final_position_routine} = sub {return $_[1];}
  }
  $self->set_up_full_rule_set($rules_to_set_up_hash, $parameters->{start_rule});
  $self->{fast_move_back} = $parameters->{fast_move_back} ||
   !($self->{any_parse_backtrack} || $self->{any_unevaluation});
  return $self;
}

sub rule_info_hash_ref {
  my $self = shift;
  return $self->{rule_info};
}

sub parse_and_evaluate {
  my $self = shift;
  my $parameters = $_[1] || {};
  if (defined $_[0]) {
    $parameters->{parse_this_ref} = \$_[0];
    if (ref $_[0] eq '') {
      $parameters->{initial_pos} = pos $_[0];
    }
  }
  my $parse_this_ref = $parameters->{parse_this_ref};
  my $parser = new Parse::Stallion::Parser($self);
  $parameters->{parse_info} = $parameters->{parse_info} || {};
  $parameters->{parse_hash} = $parameters->{parse_hash} || {};
  $parameters->{parse_hash}->{rule_info} = $self->rule_info_hash_ref;
  my $parser_results = eval {$parser->parse($parameters)};
  if ($@) {croak ($@)};
  my $to_return;
  if (!($parser_results->{parse_succeeded}) || $self->{no_evaluation}) {
    $to_return = undef;
  }
  elsif ($self->{do_evaluation_in_parsing}) {
    $to_return = $parser_results->{parsing_evaluation};
    if (!defined $to_return) {$to_return = ''};
  }
  else {
    $parameters->{nodes} = $parser_results->{bottom_up_left_to_right};
    $self->new_evaluate_tree_node($parameters);
    $to_return = $parser_results->{tree}->{computed_value};
    if (!defined $to_return) {$to_return = ''};
  }
  return $to_return;
}

#package rules
sub ri_sub {
  return ['RULE_INFO', @_];
}

sub R {ri_sub(@_)}
sub RULE_INFO {ri_sub(@_)}

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

sub USE_STRING_MATCH {return ['USE_STRING_MATCH']}

sub MATCH_ONCE {return ['MATCH_ONCE', @_]}

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
    return ['LEAF', qr/\G($p[0])/, LEAF_DISPLAY($p[0]), @q];
  }
  else {
    return ['LEAF', @p, @q];
  }
}

sub LEAF {leaf(@_)}
sub TOKEN {leaf(@_)}
sub TERMINAL {leaf(@_)}
sub L {leaf(@_)}

sub multiple {
  my @p;
  my @q;
  foreach my $parm (@_) {
    if ((ref $parm eq 'ARRAY') &&
     ($parm->[0] eq 'EVAL' || $parm->[0] eq 'UNEVAL' || $parm->[0] eq 'SEVAL'
      || $parm->[0] eq 'RULE_INFO' || $parm->[0] eq 'MATCH_ONCE'
      || $parm->[0] eq 'USE_STRING_MATCH')) {
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
    return ['MULTIPLE', 0, 0, $p[0], @q];
  }
  elsif ($#p == 2) {
    return ['MULTIPLE', $p[1], $p[2], $p[0], @q];
  }
  croak "Malformed MULTIPLE; arguments: ".join(", ", @_);
}

sub MULTIPLE {multiple(@_)}
sub M {multiple(@_)}

sub optional {
  return ['MULTIPLE', 0, 1, @_];
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
      $self->{any_unevaluation} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'MATCH_MIN_FIRST') {
      if ($rule_type ne 'MULTIPLE') {
        croak ("Rule $rule_name: Only multiple rules can have MATCH_MIN_FIRST");
      }
      $self->{rule}->{$rule_name}->{minimize_children} = 1;
      $self->{any_minimize_children} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'MATCH_ONCE') {
      $self->{rule}->{$rule_name}->{match_once} = 1;
      $self->{any_match_once} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'RULE_INFO') {
      if ($self->{rule_info}->{$rule_name}) {
        croak ("Rule $rule_name has more than one rule_info");
      }
      $self->{rule_info}->{$rule_name} = $sub_rule->[1];
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'LEAF_DISPLAY') {
      if ($self->{rule}->{$rule_name}->{leaf_display}) {
        croak ("Rule $rule_name has more than one leaf_display");
      }
      if ($rule_type ne 'LEAF') {
        croak ("Only leaf rules can have LEAF_DISPLAY in rule $rule_name");
      }
      $self->{rule}->{$rule_name}->{leaf_display} = $sub_rule->[1];
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'USE_STRING_MATCH') {
      $self->{rule}->{$rule_name}->{use_string_match} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'PARSE_FORWARD') {
      if ($self->{rule}->{$rule_name}->{parse_forward}) {
        croak ("Rule $rule_name has more than one parse_forward");
      }
      $self->{rule}->{$rule_name}->{parse_forward} = $sub_rule->[1]
       || croak ("Rule $rule_name Illegal parse_forward routine");
      $self->{any_parse_forward} = 1;
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
    elsif (!defined $sub_rule) {
      croak "undefined sub_rule in rule $rule_name\n";
    }
    else {
      push @copy_of_rule, $sub_rule;
    }
  }
  shift @copy_of_rule; #Remove rule type
  $self->{rule}->{$rule_name}->{leaf_rule} = 0;
  $self->{rule}->{$rule_name}->{or_rule} = 0;
  $self->{rule}->{$rule_name}->{and_rule} = 0;
  $self->{rule}->{$rule_name}->{multiple_rule} = 0;
  if ($rule_type eq 'LEAF') {
    my $leaf_info = shift @copy_of_rule;
    if (ref $leaf_info eq 'Regexp') {
      $self->{rule}->{$rule_name}->{regex_match} = $leaf_info;
      if ('' =~ $leaf_info) { #xyzzy
        $self->{rule}->{$rule_name}->{zero} = 1;
      }
    }
    elsif (defined $leaf_info) {
      if (defined $self->{rule_info}->{$rule_name}) {
        croak ("Duplicate info on $rule_name, leaf info is put into rule_info");
      }
      $self->{rule_info}->{$rule_name} = $leaf_info;
    }
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
      $self->{rule}->{$rule_name}->{multiple_rule} = 1;
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
      if ($self->{rule}->{$rule_name}->{use_string_match}) {
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
            push @list, "Rule $rule missing subrule: $rule_name";
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

  if (!$self->{unreachable_rules_allowed}) {
    my @unreachable_rules = $self->make_sure_all_rules_reachable({
     start_rule=>$start_rule});
    if ($#unreachable_rules > -1) {
      croak "Unreachable rules: ".join("\n",@unreachable_rules)."\n";
    }
  }

  $self->look_for_left_recursion;
  $self->{start_rule} = $start_rule;

}

sub look_for_left_recursion {
  my $self = shift;
  my %checked_rules;
  foreach my $rule (keys %{$self->{rule}}) {
    my $current_rule = $rule;
    my $moving_down = 1;
    my %active_rules;
    my @active_rules;
    my $previous_allows_zero = 0;
    while (defined $current_rule) {
      if ($moving_down) {
        if ($active_rules{$current_rule}++) {
          croak "Left recursion in grammar: ".
           join(" leads to ", @active_rules, $current_rule);
        }
        push @active_rules, $current_rule;
        if ($checked_rules{$current_rule}
         || $self->{rule}->{$current_rule}->{leaf_rule}) {
          $moving_down = 0;
        }
        else {
          $active_rules{$current_rule} = 1;
          if ($self->{rule}->{$current_rule}->{multiple_rule}) {
            $current_rule = $self->{rule}->{$current_rule}->{sub_rule_name};
          }
          else {
            $current_rule =
             $self->{rule}->{$current_rule}->{subrule_list}->[0]->{name};
          }
        }
      }
      else {
        if ($previous_allows_zero) {
          if ($self->{rule}->{$current_rule}->{multiple_rule} ||
           $self->{rule}->{$current_rule}->{or_rule}) {
            $self->{rule}->{$current_rule}->{zero} = 1;
          }
          elsif ($self->{rule}->{$current_rule}->{and_rule} &&
           ($active_rules{$current_rule} ==
           $self->{rule}->{$current_rule}->{subrule_list_count})) {
            $self->{rule}->{$current_rule}->{zero} = 1;
          }
          else {
            $previous_allows_zero = 0;
          }
        }
        if ($self->{rule}->{$current_rule}->{multiple_rule} ||
         $self->{rule}->{$current_rule}->{leaf_rule} ||
         $checked_rules{$current_rule}) {
          delete $active_rules{$current_rule};
          $previous_allows_zero = $self->{rule}->{$current_rule}->{zero} || 0;
          pop @active_rules;
          $current_rule = $active_rules[-1];
        }
        elsif ($active_rules{$current_rule} ==
           $self->{rule}->{$current_rule}->{subrule_list_count}) {
            $previous_allows_zero = $self->{rule}->{$current_rule}->{zero} || 0;
            delete $active_rules{$current_rule};
            pop @active_rules;
            $current_rule = $active_rules[-1];
        }
        elsif ($self->{rule}->{$current_rule}->{and_rule}) {
          my $previous_rule =
           $self->{rule}->{$current_rule}->{subrule_list}->
           [$active_rules{$current_rule}-1]->{name};
          if ((defined $self->{rule}->{$previous_rule}->{zero} &&
           $self->{rule}->{$previous_rule}->{zero}) ||
           ($self->{rule}->{$previous_rule}->{multiple_rule} &&
           $self->{rule}->{$previous_rule}->{minimum_child} == 0)) {
            $current_rule = 
             $self->{rule}->{$current_rule}->{subrule_list}->
             [$active_rules{$current_rule}++]->{name};
            $moving_down = 1;
          }
          else {
            $previous_allows_zero = $self->{rule}->{$current_rule}->{zero} || 0;
            delete $active_rules{$current_rule};
            pop @active_rules;
            $current_rule = $active_rules[-1];
          }
        }
        else {
          $current_rule = 
           $self->{rule}->{$current_rule}->{subrule_list}->
           [$active_rules{$current_rule}++]->{name};
          $moving_down = 1;
        }
      }
    }
  }
}

sub new_unevaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $node = $parameters->{node};
  my $rules_details = $self->{rule};
  my $rule_name = $node->{name};
  my $rule = $rules_details->{$rule_name};
  my $subroutine_to_run = $rule->{parsing_unevaluation};
  my $traversal_only = $self->{traversal_only};
  my $params_to_eval = $node->{__parameters};

  if ($rule->{use_parse_match}) {
    $params_to_eval = $node->{parse_match};
  }

  if (defined $subroutine_to_run) {
    my $parse_hash = $parameters->{parse_hash};
    delete $parse_hash->{parent_node};
    delete $parse_hash->{current_position};
    delete $parse_hash->{rule_name};
    $parse_hash->{current_node} = $node;
    &$subroutine_to_run($params_to_eval, $parse_hash);
    delete $parse_hash->{current_node};
  }

  my $parent;
  if (!$traversal_only && ($parent = $node->{parent})) {

    foreach my $param (keys %{$node->{passed_params}}) {
      if (my $count = $node->{passed_params}->{$param}) {
        if ($count > scalar(@{$parent->{__parameters}->{$param}})) {
          croak("Unevaluation parameter miscount; rule $rule_name p: $param");
        }
        splice(@{$parent->{__parameters}->{$param}}, - $count);
      }
      else {
        delete $parent->{__parameters}->{$param};
      }
    }
    delete $node->{passed_params};
  }
}

sub new_evaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $nodes = $parameters->{nodes};
  my $traversal_only = $self->{traversal_only};
  my $rules_details = $self->{rule};
  my @results;

  my $parse_hash = $parameters->{parse_hash};
  delete $parse_hash->{parent_node};
  foreach my $node (@$nodes) {
    my $rule_name = $node->{name};
    my $params_to_eval = $node->{__parameters};
    my $rule = $rules_details->{$rule_name};
    my $subroutine_to_run = $rule->{parsing_evaluation};

    if ($rule->{use_parse_match}) {
      $params_to_eval = $node->{parse_match};
    }
    elsif ($rule->{use_string_match}) {
      $params_to_eval = substr(${$parse_hash->{parse_this_ref}},
       $node->{position_when_entered},
       $node->{position_when_completed} - $node->{position_when_entered});;
    }
    my $alias = $node->{alias};

    my $cv;
    if ($subroutine_to_run) {
      $parse_hash->{rule_name} = $rule_name;
      $parse_hash->{current_node} = $node;
      @results = &$subroutine_to_run($params_to_eval, $parse_hash);
      $cv = $results[0];
    }
    elsif (!$traversal_only) {
      if ($rule->{generated} || $self->{do_not_compress_eval}) {
        $cv = $params_to_eval;
      }
      elsif ((ref $params_to_eval eq 'HASH') && (keys %$params_to_eval == 1)) {
        ($cv) = values %$params_to_eval;
      }
      else {
        $cv = $params_to_eval;
      }
    }
    $node->{computed_value} = $cv;

    my $parent;
    if (!$traversal_only && ($parent = $node->{parent})) {
      my $parent_name = $parent->{name};

      if (defined $alias) {
        if ($rules_details->{$parent_name}->{rule_count}->{$alias} > 1) {
          push @{$parent->{__parameters}->{$alias}}, $cv;
          $node->{passed_params}->{$alias} = 1;
        }
        else {
          $parent->{__parameters}->{$alias} = $cv;
          $node->{passed_params}->{$alias} = 0;
        }
      }
      else { # !defined alias
        foreach my $key (keys %$cv) {
          if ($rules_details->{$rule_name}->{rule_count}->{$key} > 1) {
            if (scalar(@{$cv->{$key}})) {
              push @{$parent->{__parameters}->{$key}}, @{$cv->{$key}};
              $node->{passed_params}->{$key} = scalar(@{$cv->{$key}});
            }
          }
          elsif ($rules_details->{$parent_name}->{rule_count}->{$key} > 1) {
            push @{$parent->{__parameters}->{$key}}, $cv->{$key};
            $node->{passed_params}->{$key} = 1;
          }
          else {
            $parent->{__parameters}->{$key} = $cv->{$key};
            $node->{passed_params}->{$key} = 0;
          }
        }
      }
    }
  }
  delete $parse_hash->{current_node};

  return @results;
}

sub LOCATION {
  my ($text_ref, $value) = @_;
  if (ref $text_ref ne 'SCALAR') {
    croak "First arg to LOCATION must be string ref";
  }
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
    no_evaluation => 0, #default 0
    max_steps => 200000, #default 1000000;
    do_not_compress_eval => 0, #default 0
    separator => '__XZ__', #default '__XZ__'
    need_not_match_whole_string => 0, #default 0
    parse_forward => sub {...}, #default no sub
    parse_backtrack => sub {...}, #default no sub
    traversal_only => 0, #default 0
    unreachable_rules_allowed => 0, #default 0
    fast_move_back => 0, #default 0 unless unevaluation/parse_backtrack
  });

  my $parse_info = {}; # optional, little impact on performance
  my $parse_hash = {}; # optional, little impact on performance
  my $parse_trace = []; # optional, some impact on performance
  my $result = $stallion->parse_and_evaluate($given_string,
    # usually omit the following
   {max_steps => 30000, #default from parser's creation
    parse_info => $parse_info, #if provided, parse info returned
    parse_trace => $parse_trace, # if provided, trace returned
    start_position => 0, #default 0
    start_rule => $start_rule, # default from parser creation
    parse_hash => $parse_hash, #used as parse_hash in called routines
   });
  # returns undef if unable to parse


Rule Definitions (may be abbreviated to first letter):

  AND('subrule_1', 'subrule_2', ..., EVALUATION(sub{...}))

  OR('subrule_1', 'subrule_2', ..., EVALUATION(sub{...}))

  MULTIPLE('subrule_1', EVALUATION(sub{...}))

  LEAF(qr/regex/, EVALUATION(sub{...}))

=head1 DESCRIPTION

Stallion parses and evaluates a string using entered grammar rules.
The parsing is done top-down via a start rule, in a depth first
search forming a parse tree.
When a rule does not match the parser backtracks to a node that has another
option.

For evaluating a tree node, the evaluation subroutine is given a reference
to a hash representing the returned values of the child nodes.
The evaluation may be done while creating the parse tree and reject a
match affecting which strings parse;
this allows complex grammars.

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
    number => LEAF(qr/\d+/)
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
    number => L(qr/\d+/)
   );

   my $parser_2 = new Parse::Stallion(
    \%grammar_2, {start_rule => 'expression'});

   my $result_2 = $parser_2->parse_and_evaluate('8 + 5');
   #$result_2 should contain 13

   use Parse::Stallion::EBNF; #see documentation on Parse::Stallion::EBNF

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

A B<'LEAF'> rule contains a regexp that must match the input string
starting from the current position.
During parsing, when a B<'LEAF'> matches, the parser's position is moved
to the end of the match.  The matched value is stored in the parse tree.
The text LEAF is optional, regexp's are assumed to be leaves.

One may use the keyword TOKEN or TERMINAL instead of LEAF.

If the regexp matches but is empty, the matched value is set to an empty
string as opposed to an undefined value.

Examples (equivalent):

  LEAF(qr/xx\w+/)

  L(qr/xx\w+/)

  qr/xx\w+/

  TOKEN(qr/xx\w+/)

would match any perl word (\w+) starting with "xx".

See the section B<'LEAF DETAILS'> for more details on B<'LEAF'> rules.

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
are the minimum and maximum repetitions allowed.
The default minimum is 0 and the default maximum is "infinite", though
this is represented by setting the maximum to 0.

Every occurrence of the subrule must increase the position, this
prevents "left recursion".

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
conflicting with internally generated rule names.  This can be changed by
using the 'separator' parameter.

=head3 ENSURING RULES FORM COMPLETE GRAMMAR

Stallion ensures that a grammar is complete and croaks if the given grammar
has any rules not reachable from the start rule or if within any rule a
subrule does not exist.

The parameter unreachable_rules_allowed can override the reachability condition.

=head3 MATCH_ONCE()

If the parameter MATCH_ONCE is part of a rule, only one match is tried,
no backtracking to other possible matches involving descendants of
a node created by that rule.
This is for making matching faster by cutting down
the number of steps though it also does affect what can be matched.

In the parser below 'x' can be matched by the rule but 'xx' will
not be because of the MATCH_ONCE(), B<'OR'> rules are tried left to right.

  $p = new Parse::Stallion({r => O(qr/x/, qr/xx/, qr/yy/, MATCH_ONCE)});
  $p->parse_and_evaluate('x'); #returns 'x'
  $p->parse_and_evaluate('yy'); #returns 'yy'
  $p->parse_and_evaluate('xx'); #does not parse, returns undef

In a B<'MULTIPLE'> rule with MATCH_ONCE(), if 'match_min_first' is used,
then the maximum repetition number is meaningless.
It makes almost no sense to have MATCH_ONCE(), 'match_min_first', and
a minimum repetition of 0 in the same rule, the rule will be matched with
no children.

If there are no parse_backtrack and no unevaluation routines then a
MATCH_ONCE routine can be done in fast mode, just chopping off the
node from the tree without backtracking through the subtree at the node.
The check for parse_backtrack and unevaluation routines can be
overridden by creating the parser with the fast_move_back parameter.

MATCH_ONCE can take a subroutine as an argument.  This is passed in
the parse_hash parameter as found in parse_forward.  If the subroutine
returns a true value, then the fast version of MATCH_ONCE is used even
if there are parse_backtrack or unevaluation routines.

=head4 MATCH_ONCE Examples

The 3 following parsers all parse the same strings but can take
different amounts of steps on the same input.

  my $pi = {};

  my $mo_1 = new Parse::Stallion(
   {rule1 => A(M(qr/t/), M(qr/t/), qr/u/)});
  $result = $mo_1->parse_and_evaluate('ttttt',{parse_info => $pi});
  print "parse steps 1 ".$pi->{number_of_steps}."\n"; # should be 157

  my $mo_2 = new Parse::Stallion(
   {rule2 => A(M(qr/t/, MATCH_ONCE()), M(qr/t/, MATCH_ONCE()), qr/u/)});
  $result = $mo_2->parse_and_evaluate('ttttt',{parse_info => $pi});
  print "parse steps 2 ".$pi->{number_of_steps}."\n"; # should be 15

  my $mo_3 = new Parse::Stallion(
   {rule2 => A(M(qr/t/, MATCH_ONCE()), M(qr/t/, MATCH_ONCE()),
     L(qr/u/, PB(sub {return 0})), MATCH_ONCE())});
  $result = $mo_3->parse_and_evaluate('ttttt',{parse_info => $pi});
  print "parse steps 3 ".$pi->{number_of_steps}."\n"; # should be 27

=head2 PARSE_AND_EVALUATE

After setting up a Parse::Stallion parser, strings are parsed and evaluated
via parse_and_evaluate.  The returned value is the
returned value of the root node's evaluation routine.

In a typical parse, the current position corresponds to how much of
the string from left to right has been parsed, moving from 0 to its length.

=head3 PARTIAL STRING PARSES

The parser completes a parse only if the grammar matches
the whole string unless the parameter need_not_match_whole_string is set.

Example showing differences

   my $one_grammar = {start => qr/1/};
   my $parser = new Parse::Stallion($one_grammar);
   my $partial_parser = new Parse::Stallion($one_grammar,
    {need_not_match_whole_string => 1});
   $parser->parse_and_evaluate('12');  # does not parse
   $partial_parser->parse_and_evaluate('12');  # parses (returns '1')

=head3 START POSITION AND REFERENCE INPUT

The default start position of $input_string is pos $input_string
which is most likely 0.
One can specify the start_position as a parameter of parse_and_evaluate
or by creating an initial_position_routine.

Example showing how to loop on input

  my $parser = new Parse::Stallion({n => L(qr/(\d+)\;/,E(sub{$_[0]+1}))},
   {need_not_match_whole_string => 1});
  my $input = '342;234;532;444;3;23;';
  my $pi = {final_position => 0};
  my $input_length = length($input);
  while ($pi->{final_position} != $input_length) {
    push @results, $parser->parse_and_evaluate($input,
     {parse_info=> $pi, start_position => $pi->{final_position}});
  }
  # @results should contain (343, 235, 533, 445, 4, 24)

However, by noting that the pos of a string is set by parse_and_evaluate,
one can rewrite the loop above as:

  my $parser = new Parse::Stallion({n => L(qr/(\d+)\;/,E(sub{$_[0]+1}))},
   {need_not_match_whole_string => 1});
  my $input = '342;234;532;444;3;23;';
   while (my $result = $parser->parse_and_evaluate($input)) {
    push @results, $result;
  }
  # @results should contain (343, 235, 533, 445, 4, 24)
  # pos $input would be undef before loop and 21 after loop

=head3 RETURNED VALUES

One can check if the returned value is 'undef' to determine if an
evaluation failed, an empty string is returned if evaluation results in an
undef.  Also one can look at $parse_info->{parse_succeeded} which
has a value even if there is no evaluation.

To get details on the parsing from parse_and_evaluate, there
are two optional parameters: parse_info that receives a hash ref
and parse_trace that receives an array ref.  These ref's are
filled in during parse_and_evaluate.

  my $parse_info = {};
  my $parse_trace = [];
  my $value = $parser->parse_and_evaluate($string_to_parse,
   {parse_info=>$parse_info, parse_trace => $parse_trace});

  $parse_info->{parse_succeeded}; # true (1) if string parses
  $parse_info->{tree}; # Root of resultant parse tree
  $parse_info->{number_of_steps}; # Number of steps taken
  $parse_info->{start_rule}; # Start rule used for this parse
  $parse_info->{start_position}; # Initial position of parse
  $parse_info->{final_position}; # 0 if parse failed
  $parse_info->{final_position_rule}; # Last rule looked at
  $parse_info->{maximum_position}; # Maximum position in parse
  $parse_info->{maximum_position_rule}; # First rule at maximum position
  $parse_info->{parse_backtrack_value};
   # 0 unless parse backtrack call ends parse

An entry in $parse_trace looks like:

  $parse_trace->[$step]->{rule_name}
  $parse_trace->[$step]->{moving_forward} # 0 if backtracking
  $parse_trace->[$step]->{moving_down} # 0 if moving up parse tree
  $parse_trace->[$step]->{current_position}
  $parse_trace->[$step]->{node_creation_step} # for current node
  $parse_trace->[$step]->{parent_node_creation_step}
  $parse_trace->[$step]->{message} # informative message on previous step
  $parse_trace->[$step]->{tree} # stringified snapshot of parse tree

=head4 STRINGIFIED PARSE TREE

The tree is a Parse::Stallion object having a function, that converts a
tree into a string, each node consisting of one line:

  $parse_info->{tree}->stringify({values=>['name','parse_match']});

Internally generated node names, from rules generated by breaking up
the entered rules into subrules, will show up. The module
Parse::Stallion::EBNF shows the grammar with these generated subrules.
The node keys described in the section Parse Tree Nodes can be passed to
stringify.

=head3 PARSE STEPS

A step is an action on a node, roughly speaking matching a
regex for a B<'leaf'> node, or moving forward or backtracking from a node.
Each step is listed in the optional parse_trace.

If the parsing reaches the maximum number of steps the parse fails (croak).
The maximum number of steps can be changed via max_steps.  If max_steps
is set to a negative number, there is no limit on the number of steps.

  $stallion->parse_and_evaluate($string, {max_steps=>200000});

=head3 "LEFT RECURSION"

Parse::Stallion checks the grammar for "left recursion" and will not
build the grammar if left recursion is detected (croaks).
However, there are some cases which are not possible
to detect, i.e. whether a parse forward routine will change the position
or a case where a regexp matches but returns an empty string such
as qr/\B/ .

Parse::Stallion may encounter "left recursion"
during parsing in which case the parsing stops and a message is 'croak'ed.

"Left recursion" occurs during parsing when the same non-B<'leaf'> rule shows
up a second time on the parse tree at the same position.

Illegal Case 1:

     expression => AND('expression', 'plus', 'term')

Expression leads to expression leads to expression ....

Illegal Case 2:

     rule_with_empty => AND('empty', 'rule_with_empty', 'other_rule')
     empty => qr//

The second case is detected while building the grammar, regexp's are
checked to see if they match the empty string.

Illegal Case 3:

     rule_with_pf => A(L(PF(sub {return 1}))', 'rule_with_pf',
      'other_rule')

The third case will be detected during parsing.

=head2 EVALUATION

Evaluation can occur during or after parsing.

Each rule may have an evaluation subroutine tied to it. When defining
a rule if there is no subroutine, a default "do nothing" subroutine is provided.
Nested subrules may have a subroutine tied to them though by default
they have none.

When setting up a rule, one can specify the EVALUATION subroutine
by the parameter 'EVALUATION' or 'E' which in turn takes one parameter,
the evaluation subroutine for that node.

Each node has a computed value that is the result of calling its
evaluation routine.  The returned value of the parse is the
computed value of the root node.

There are two parameters to a node's evaluation routine.

The first parameter to the evaluation routine is either a
hash or a string.

If the node is a leaf regexp that has a parenthesized match inside,
what is matched by the first parenthesized match is the parameter.
Else if the node is a leaf then what is matched by the leaf is
the first parameter.
Else if 'USE_STRING_MATCH()' has been set for the node's rule,
the substring equivalent to a join
of all the matched strings of the nodes' descendants is the parameter.

For other internal nodes, the first parameter is a hash.
The hash's keys are the named subrules of the node's rule, the values
are the computed value of the corresponding children nodes.  If a key could
repeat, the value is an array reference.

The second parameter to an evaluation routine is the "parse_hash",
see the section entitled Parse Hash.

By nesting a rule with an alias, the alias is used for the name of the
hash parameter instead of the rule name.

=head3 Parse Hash

The parse hash is a hash ref that is passed to the evaluation, unevaluation,
parse_forward, and parse_backtrack routines.  It is the same hash
ref throughout a specific parse so one can store values there to pass
among the routines.  One can pass in a hash ref, with some preset keys,
to be used as the parse_hash for a given parse_and_evaluate call.

There are several keys that are set

   parse_this_ref # Reference to object being parsed
   current_position # The current position of the object being parsed
                    #, not set for evaluation after parsing
   parent_node # Node in tree for child to be created for parse_forward
               # and parse_backtrack, child has been removed before call
               # to parse_backtrack; see Parse Tree Nodes
   current_node # active node in parse tree for evaluation, unevaluation,
                # see section Parse Tree Nodes
   parse_match # for parse_backtrack routine, match from parse_forward
   rule_name # Name of rule, may be internally generated
   rule_info # Hash of rule names which have RULE_INFO set

Any future parameters will be given double underscores at the start
of their names.

=head4 Parse Tree Nodes

A parse tree node is a hash reference composed of:

    name, # Name of rule, this may be internally generated
    alias, # Alias of rule in evaluation phase parameter list
    steps, # Number of steps in parse when node created
    parent, # Node's parent hash reference
    position_when_entered, # Position when node created
    position_when_completed, # Position when node completely parsed
    children, # Array reference to nodes of children (undef if leaf)
    child_count, # scalar(@children)
    parse_match, # matched leaf string or match returned by parse_forward

In addition, there will be some keys beginning with double underscore (__).

Parse tree nodes are also passed to the parse forward and parse backtrack
subroutines.

One should not change the values of a parse node hash.
However, one is allowed
to add key/values to the hash (avoid key names with double underscores).

=head3 Evaluation Examples

Comments refer to the parameters of the evaluation subroutine.

   LEAF(qr/d\w+/, E(sub {...})) # word starting with d

   L(qr/(d)\w+/, E(sub {...})) # $_[0] = 'd'

   L(qr/\s*(\w+)\s*/, E(sub {...})) # white space trimmed

   A(qr/a/, qr/b/, E(sub {...})) #$_[0]->{''}->['a','b']

   A(qr/a/, qr/b/, E(sub {...}), USE_STRING_MATCH()) # $_[0] = 'ab'

   A({f=>qr/a/}, {f=>qr/b/}, E(sub {...})) # $_[0]->{'f'} = ['a','b']

   A('rule1', 'rule2', 'rule3', E(sub {...}))
    #params are $_[0]->{rule1}, $_[0]->{rule2}, $_[0]->{rule3}

=head3 LOCATION

A function, LOCATION is provided that takes a string reference and a position
in the string and computes the line number and tab value of the given position.

  my ($line, $tab);
  my $loc_grammar = {
    start =>
     A(qr/....../s,
       L(qr//, E(
         sub {
          ($line, $tab) = LOCATION($_[1]->{parse_this_ref},
           $_[1]->{current_node}->{position_when_entered})
         })),
       qr/.*/s)
  };
  my $loc_parser = new Parse::Stallion($loc_grammar);
  $loc_parser->parse_and_evaluate("ab\nd\nfghi");
  # $line == 3,  $tab == 2

  One can also use this function after a parse to determine where the
  maximum position occured in the input string.

=head3 EVALUATION AFTER PARSING

In evaluation after parsing, the default, Parse::Stallion will evaluate
the parse tree in a bottom up left to right traversal.

=head3 EVALUATION (AND UNEVALUATION) DURING PARSING

If the do_evaluation_in_parsing is set when a Parse::Stallion object is
created the evaluation occurs during the parsing instead of afterwards.
Alternatively, if there exists any UNEVALUATION routine, the evaluation
is done during parsing.

Every time a node is matched, its evaluation routine is called.
The parse_hash will have the key current_position set and
the node will not yet have the key position_when_completed.

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

  our %keywords = ('key1'=> 1, 'key2' => 1);
  my %g = (
   start => A('leaf', qr/\;/),
   leaf => L(
     qr/\w+/,
     E(sub {if ($keywords{$_[0]}) {return (undef, 1)} return $_[0]}),
   ),
  );
  my $parser = new Parse::Stallion(\%g, {do_evaluation_in_parsing=>1});
  $parser->parse_and_evaluate('key1;'); #should return false
  $parser->parse_and_evaluate('key3;'); #should return true
   # ( {''=>';',leaf=>'key3'} )

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
   number => qr/\d+/ ,
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

  my %n_eval_rules = (
   start_rule => A('term',
    M(A({plus=>qr/\s*\+\s*/}, 'term'))),
   term => A({left=>'number_or_x'},
    M(A({times=>qr/\s*\*\s*/},
     {right=>'number'}))),
   number_or_x => O('number',qr/x/),
   number => qr/\s*\d*\s*/
  );

  my $n_eval_parser = new Parse::Stallion(\%n_eval_rules,
   {do_not_compress_eval => 0});

  $result = $n_eval_parser->parse_and_evaluate("7+4*8");

  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ '7',
                { 'left' => '4',
                  'right' => [ '8' ],
                  'times' => [ '*' ] } ] }

  my $dnce_n_eval_parser = new Parse::Stallion(\%n_eval_rules,
   {do_not_compress_eval => 1});

  $result = $dnce_n_eval_parser->parse_and_evaluate("7+4*8");

  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ { 'left' => {number => '7'} },
                { 'left' => {number => '4'},
                  'right' => [ {number => '8'} ],
                  'times' => [ '*' ] } ] }

=head3 Parameter types to Evaluation Routines

If a named parameter could appear more than once, it is passed
as an array, else as a scalar.  Being passed as an array could be
caused by either:

=over

=item 1.

the name being within a B<'MULTIPLE'> rule which does not
have maximum children of 1

=item 2.

occurring more than once within the subrules of an B<'AND'> rule.

=back

The routine which_parameters_are_arrays returns a hash of the
possible values passed to an evaluation routine.  For a given key,
if the value is 1, the key would be passed to the evaluation routine
as an array, if the value is 0, it would be passed as a scalar.

=head3 MORE COMPLICATED EVALUATION EXAMPLE

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
      E(sub{ return $_[0]; })
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

If the rule is a leaf then $_ is set to the parameter $_[0];
else, $_ is the one unnamed rule or an array ref of the unnamed rules:

    $_ = $_[0]->{''};

=head3 NO EVALUATION

Evaluation can be prevented by setting no_evaluation when the grammar
is created.  The return of parse_and_evaluate is always undef in this case
but parse_info can be used to view the parse results.

=head3 TRAVERSAL ONLY

There is some overhead to computing the parameters with the names of
the subrules.  If traversal_only is set when the grammar is created, this
is not computed and the first parameter to each evaluation subroutine is undef.

=head2 LEAF DETAILS

Leaf rules can be set up as follows:

  LEAF($leaf_arg, PARSE_FORWARD(sub{...}), PARSE_BACKTRACK(sub{...}),
   EVALUATION(sub{...}), UNEVALUATION(sub{...}), LEAF_DISPLAY($display));

If $leaf_arg is a Regexp, it is converted into a hash ref:
{regex_match => $leaf_arg} for internal purposes.

If a default PARSE_FORWARD is not provided then
a regexp match is attempted on the string being parsed at the
current_position.
Default parse_forward and parse_backtrack subroutines can be provided
for leaves.

The subroutine in PARSE_FORWARD (or PF) is called when moving forwards
during the parse.  Its one parameter is a hash described in the
section entitled Parse Hash above.

If the parsing should continue forward it should return an array with
the first argument true (1), the second argument the "parse_match" to store
at the node, and an optional third argument being the new parse position.
The new parse position must be greater than or equal to the previous position.
If parsing should not continue, parse_forward should return 0.

The subroutine in PARSE_BACKTRACK (or PB) is called when backtracking
has destroyed a (leaf) node.  Its one parameter is the pares_hash.

The parse backtrack routine should normally return a false value.
If it returns true, the parsing immediately ends in failure.
The value ending the parse is returned in parse_backtrack_value.
This can be used to set up a rule

  pass_this_no_backtrack => L(qr//,PB(sub{return 1}))

that if encountered during parsing during a backtrack means that the parsing
will end.

EVALUATION and UNEVALUATION are explained in the section B<'EVALUATION'>.

=head3 LEAF_DISPLAY

See Parse::Stallion::EBNF for this exported keyword.

=head3 PARSE_FORWARD and PARSE_BACKWARD on non-leaf nodes

It is possible to create PARSE_FORWARD and PARSE_BACKWARD routines on
non-leaves.  These routines are executed before the node is created
and after it is destroyed.  They may change the position of the parse
and the returned value of the match is stored in the node's hash
"parse_match" key.

=head2 OTHER PARSING NOTES

=head3 PARSING NON-STRINGS

Four subroutines may be provided: a default B<'leaf'>
rule matcher/modifier for when the parser is moving forward and
a default B<'leaf'> rule "unmodifier" for when the parser is backtracking.
A third optional subroutine, initial_position_routine,
sets the initial current value else it is 0.

The fourth subroutine, final_position_routine, should return the final position
of a successful parse for a given object.  This subroutine is
similar to parsing strings ensuring, or not ensuring, that the entire
string is matched instead of matching only a portion.

  my $object_parser = new Parse::Stallion(\%grammar, {
    ...
    parse_forward =>
     sub {
       my $parameters = shift;
       ...
       return ($true_if_object_matches_rule,
        $value_to_store_in_leaf_node,
        $value_equal_or_greater_than_current_position);
     },
    parse_backtrack =>
     sub {
       my $parameters = shift;
       ...
       return; #else parsing halts
      },
    initial_position_routine => sub {my ($object_ref, $parse_hash) = @_;
       ...
       return $initial_position;
    },
    final_position_routine =>
     sub {my ($object_ref, $current_position, $parse_hash) = @_;
        ...
       return $final_position;
        # parse ends if $final_position==$current_position
     },
  });

By default parsing only ends if the entire string is parsed and
the start rule is matched.
To allow parsing to end regardless of position in the string when
the start rule is matched:

    final_position_routine => sub {return $_[1];}

This is also done with the parameter need_not_match_whole_string.

When evaluating the parse tree, the parameters to the B<'leaf'> nodes are
the values returned in parse_forward.

The script object_string.pl in the example directory demonstrates this section.

=head4 B<'LEAF'> LEAF PARSE FORWARD/BACKTRACK

All B<'leaf'> rules need to be set up such that when the parser is moving
forward and reaches a B<'leaf'>, the
B<'leaf'> rule attempts to match the object being parsed
at the current position.
If there is a match, then the current_position may increase.

When backtracking, the object being parsed should be reverted, if changed, to
the state before being matched by the B<'leaf'> rule.

=head4 NON_DECREASING POSITION

The third value returned from parse_forward should be equal or
greater than the $current_position that was passed in.

The position is used to detect and prevent "left recursion" by not
allowing a non-B<'leaf'> rule to repeat at the same position.
B<'MULTIPLE'> rules are prevented from repeating more than once at
the same position.

The position also cuts down on the number of steps by allowing the parser to
not repeat dead-end parses.  If during the parse, the same rule is
attempted a second time on the parse object at the same position,
and the first parse did not succeed, the parser will begin backtracking.

=head4 STRINGS

By default, strings are matched, which, if a reference to the
string instead of the string is passed in to parse_and_evaluate, is similar to
that found in the test case object_string.t:

  my $calculator_stallion = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
      my $parameters = shift;
      my $input_string_ref = $parameters->{parse_this_ref};
      my $rule_info = $parameters->{rule_info};
      my $rule_name = $parameters->{rule_name};
      my $rule_definition = $rule_info->{$rule_name};
      my $m = $rule_definition->{nsl_regex_match};
      if ($$input_string_ref =~ s/\A($m)//) {
        return (1, $1, 0 - length($string));
      }
      return 0;
     },

    parse_backtrack =>
     sub {
      my $parameters = shift;
      my $input_string_ref = $parameters->{parse_this_ref};
      my $stored_value = $parameters->{parse_match};
      if (defined $stored_value) {
        $$input_string_ref = $stored_value.$$input_string_ref;
      }
      return;
     },

    initial_position_routine =>
     sub {
       my $input_string_ref = shift;
       return 0 - length($$input_string_ref);
     },

    final_position_routine =>
     sub {
       return 0;
     }
  });

=head3 PARSING VERY LARGE INPUTS

In a normal course of parsing, the input string is split up and stored
at each leaf node.  If the input size is very large, this could cause
memory problems.  Note, the input string is not copied, space will
be consumed by the leaves containing all the substrings and the
parse tree itself.

Below are some mostly untested tips on how this can be handled:

=head4 NOT STORING VALUES IN LEAFS

By allowing the first parenthesized expression of a leaf to be empty,
i.e.: qr/()leaf_reg_ex/, then the empty string will be stored at that leaf.
When evaluating the leaf, the first parameter will be the empty string.
One can make use of USE_STRING_MATCH.

=head4 REMOVE NODES FROM TREE DURING PARSE

One need be very careful to try this.  If the parse
is always moving forward and will never backtrack then after a node
is evaluated, i.e. if do_parsing_in_evaluation=1, then the
children of that node are no longer needed.  Since the evaluation
routine has access to the node and the node's children, one
can delete the {children} key from the node when a node is completed.
This would keep the parse tree small.

=head2 EXPORT

The following are EXPORTED from this module:

 A AND E EVALUATION L LEAF LEAF_DISPLAY LOCATION MATCH_ONCE M MULTIPLE O
 OPTIONAL OR PARSE_FORWARD PARSE_BACKTRACK PB PF RULE_INFO R SE
 STRING_EVALUATION TERMINAL TOKEN U
 UNEVALUATION USE_STRING_MATCH Z ZERO_OR_ONE

=head1 PERL Requirements

Parse::Stallion's installation uses Test::More and Time::Local
requiring perl 5.6 or higher.
Parse::Stallion should work with earlier versions of perl, neither
of those modules is required outside of the test cases for installation.

=head1 VERSION

0.89

=head1 AUTHOR

Arthur Goldstein, E<lt>arthur@acm.orgE<gt>

=head1 ACKNOWLEDGEMENTS

Damian Conway, Christopher Frenz, and Greg London.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-9 by Arthur Goldstein.  All Rights Reserved.

This module is free software. It may be used, redistributed and/or modified
under the terms of the Perl Artistic License
(see http://www.perl.com/perl/misc/Artistic.html)


=head1 BUGS

Please email in bug reports.

=head1 TO DO AND FUTURE POSSIBLE CHANGES

left recursion checking, is it really checking things off or running through each node?  Also, if parse_forward routine in there, remove zero'ing.

new doc on min children and empty

Run through all the files in demo of recdescent and get running

croak on invalid start rule?

Fast mode.  There are checks in parsing for the parse trace, parse_backtrack,
parse_forward, left recursion, ...  Removing these would make the parser
less flexible/safe but faster.

Please send in suggestions.

=head1 SEE ALSO

example directory (includes stallion.html, a javascript translation of
 an earlier version of Parse::Stallion) and test case directory t

Parse::Stallion::EBNF. Outputs grammars in more readable form.  Also
contains an example of how one could input a grammar from a string, similar
to how many parsers take their input.

Parse::Stallion::CSV. Example of how to create a parser from specification.

Perl 6 grammars.

lex, yacc, ..., other parsers.

=cut
