#Copyright 2007-8 Arthur S Goldstein

package Parse::Stallion::Talon;
use Carp;
use strict;
use warnings;
use 5.006;
our $VERSION = '0.04';

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $parameters = shift;
  my $parent = $parameters->{parent};
  my $self = {};
  bless $self, $class;

  if ($parent) {
    $self->{parent} = $parent;
    push @{$parent->{children}}, $self;
  }
  $self->{values} = $parameters->{values};
  $self->{children} = [];

  return $self;
}

sub stringify {
#Example:    $tree->stringify({
#values=>['steps','name','parse_match','pvalue']});
  my $self = shift;
  my $parameters = shift;
  my $values = $parameters->{values};
  my $spaces = $parameters->{spaces} || '';
  my $value_separator;
  if (exists $parameters->{value_separator}) {
    $value_separator = $parameters->{value_separator};
  }
  else {
    $value_separator = '|';
  }

  my $line = $spaces;

  foreach my $value (@$values) {
    if (defined $self->{values}->{$value}) {
      $line .= $self->{values}->{$value}.$value_separator;
    }
    else {
      $line .= $value_separator;
    }
  }

  $line .= "\n";
  foreach my $child ($self->children) {
    $parameters->{spaces} = $spaces.' ';
    $line .= $child->stringify($parameters);
  }

  return $line;
}

sub parent {
  my $self = shift;
  if (defined $self->{parent}) {return $self->{parent}};
  return;
}

sub children {
  my $self = shift;
  return @{$self->{children}};
}

sub children_ref {
  my $self = shift;
  return $self->{children};
}

sub values {
  my $self = shift;
  return $self->{values};
}

sub right_sibling { 
  my $self = shift;
  my $parent = $self->parent;
  if ($parent) {
    my @siblings = $parent->children;
    for (my $i = 0; $i < $#siblings;$i++) {
      if ($siblings[$i] == $self) {
        return $siblings[$i+1];
      }
    }
  }
}

sub bottom_up_depth_first_search {
  my $self = shift;
  my $parameters = shift;
  my @results;
  my $moving_down = 1;
  my $current_node = $self;
  while ($current_node) {
    if ($moving_down) {
      if ($current_node->children) {
        $current_node = $current_node->{children}->[0];
      }
      else {
        $moving_down = 0;
        push @results, $current_node;
      }
    }
    elsif ($current_node->parent) {
      if ($current_node->right_sibling) {
        $moving_down = 1;
        $current_node = $current_node->right_sibling;
      }
      else {
        push @results, $current_node->parent;
        $current_node = $current_node->parent;
      }
    }
    else {
      $current_node = undef;
    }
  }
  return @results;
}

sub remove_node_from_parent {
  my $self = shift;
  my $parameters = shift;
  my $replace_with = $parameters->{replace_with} || [];
  my $parent = $self->parent;
  if ($parent) {
    my $count = 0;
    while (defined $parent->{children}->[$count] &&
     $parent->{children}->[$count] ne $self) {$count++}
    if (defined $parent->{children}->[$count]) {
      splice (@{$parent->{children}}, $count, 1, @$replace_with);
    }
    else {
      croak ("corrupt tree\n");
    }
    delete $self->{parent};
  }
  return $parent;
}

sub copy_node_and_sub_nodes {
  my $self = shift;
  my $parameters = shift;
  my $values_to_copy = $parameters->{values_to_copy};
  my $copy;
  $copy = new Parse::Stallion::Talon;
  foreach my $value_to_copy (@$values_to_copy) {
    if (exists $self->{values}->{$value_to_copy}) {
      $copy->{values}->{$value_to_copy} = $self->{values}->{$value_to_copy};
    }
  }
  foreach my $child (@{$self->{children}}) {
    my $new_child = $child->copy_node_and_sub_nodes($parameters);
    $new_child->{parent} = $copy;
    push @{$copy->{children}}, $new_child;
  }
  return $copy;
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
  my $trace_fh = $parameters->{trace_fh} || $parsing_info->{null_fh};
  my $object_being_parsed = $parameters->{parse_this};
  my $start_node = $parsing_info->{start_rule};
  my $max_steps = $parameters->{max_steps} || 20000;

  my $tree = new Parse::Stallion::Talon({
   values => {name => $start_node,
     steps => 0,
     value_when_entered =>
      &{$parsing_info->{increasing_value}}($object_being_parsed),
     alias => 'b__XZ__XZ',
   },
  });
  $tree->{current_subrule_number} = 0;
  $tree->{subrule_counts}->[0] = 0;

  $parsing_info->{current_node} = $tree;
  $parsing_info->{tree_root} = $tree;
  $parsing_info->{moving_forward} = 1;
  $parsing_info->{moving_down} = 1;
  $parsing_info->{parse_trace} = [];
  $parsing_info->{ventured_out_on} = {};
  $parsing_info->{steps} = 0;
  $parsing_info->{trace_fh} = $trace_fh;
  $parsing_info->{active_rules_values} = {};
  if ($parsing_info->{do_evaluation_in_parsing}) {
    $tree->{previous_parsing_evaluation_arr_ref} = ['beginning__XZ__',{}];
    $parsing_info->{rule}->{beginning__XZ__}->{rule_count}->{'b__XZ__XZ'} = 1;
    $tree->{parsing_evaluation_arr_ref} =
     $parsing_info->{parsing_evaluation_arr_ref} = [$start_node,{}];
  }
  $parsing_info->{object_being_parsed} = $object_being_parsed;
  $parsing_info->{current_value} =
   &{$parsing_info->{increasing_value}}($object_being_parsed);

  while (($parsing_info->{steps} < $max_steps) &&
   $parsing_info->{current_node}) {
    while ($parsing_info->{current_node} &&
     (++$parsing_info->{steps} < $max_steps)) {
      $parsing_info->parse_step;
      print $trace_fh "Step ".$parsing_info->{steps}." cnn ";
      if ($parsing_info->{current_node}) {
        print $trace_fh $parsing_info->{current_node}->values->{name}."\n";
      }
    }
    if (!$parsing_info->{current_node} &&
     (!&{$parsing_info->{end_of_parse_allowed}}(
      $parsing_info->{object_being_parsed})) &&
     $parsing_info->{moving_forward}) {
      $parsing_info->{moving_forward} = 0;
      $parsing_info->{moving_down} = 1;
      $parsing_info->{current_node} = $tree;
    }
  }
  $parsing_info->{results}->{start_rule} = $parsing_info->{start_rule};
  $parsing_info->{results}->{number_of_steps} = $parsing_info->{steps};
  $parsing_info->{results}->{unparsed} = $parsing_info->{object_being_parsed};
  $parsing_info->{results}->{parse_trace} = $parsing_info->{parse_trace};
  if ($parsing_info->{moving_forward} && $parsing_info->{steps} < $max_steps) {
    $parsing_info->{results}->{parse_succeeded} = 1;
    $parsing_info->{results}->{parse_failed} = 0;
  }
  else {
    $parsing_info->{results}->{parse_succeeded} = 0;
    $parsing_info->{results}->{parse_failed} = 1;
  }
  foreach my $node ($tree->bottom_up_depth_first_search) {
    print $trace_fh "considering node ".$node->{values}->{steps}."\n";
    if (exists $node->values->{parse_match}) {
      $node->{values}->{pvalue} = $node->values->{parse_match};
    }
    elsif (!exists $node->{values}->{pvalue}) {
      $node->{values}->{pvalue} = '';
    }
    if ($parsing_info->{remove_white_space}) {
      my $parent = $node->parent;
      if (my $parent = $node->parent) {
        if (exists $parent->{values}->{pvalue}) {
          $parent->{values}->{pvalue} .= $node->values->{pvalue};
        }
        else {
          $parent->{values}->{pvalue} = $node->values->{pvalue};
        }
        print $trace_fh "parent ".$parent->{values}->{steps}." ";
        print $trace_fh "pv ".$parent->{values}->{pvalue}."\n";
      }
      else {
        print $trace_fh "No parent on ".$node->{values}->{steps}."\n";
      }
      print $trace_fh "pval now '".$node->{values}->{pvalue}."'\n";
      $node->{values}->{pvalue} =~ s/^\s*//s;
      $node->{values}->{pvalue} =~ s/\s*$//s;
    }
    if (defined $node->{values}->{pvalue}) {
      print $trace_fh "pval now '".$node->{values}->{pvalue}."'\n";
    }
    else {
      print $trace_fh "pval not set\n";
    }
  }
  print $trace_fh $tree->stringify({
   values=>['steps','name','parse_match','pvalue']});
  $parsing_info->{results}->{tree} =
    $tree->copy_node_and_sub_nodes({values_to_copy=>[
     'pvalue', 'name','alias','parse_match']});
  if ($parsing_info->{do_evaluation_in_parsing} &&
   $parsing_info->{results}->{parse_succeeded}) {
    $parsing_info->{results}->{parsing_evaluation} =
     $parsing_info->{parsing_evaluation_arr_ref}->[1]->{'b__XZ__XZ'};
  }
  return $parsing_info->{results}->{parse_succeeded};
}

sub parse_step {
  my $parsing_info = shift;

  $parsing_info->{object_being_parsed} =
   &{$parsing_info->{parse_function}}($parsing_info->{object_being_parsed});
  my $current_node_name = $parsing_info->{current_node_name} =
   $parsing_info->{current_node}->{values}->{name};
  my $current_rule = $parsing_info->{current_rule} =
   $parsing_info->{rule}->{$current_node_name};
  push @{$parsing_info->{parse_trace}}, {
   rule_name => $current_node_name,
   moving_forward => $parsing_info->{moving_forward},
   moving_down => $parsing_info->{moving_down},
   value =>
    &{$parsing_info->{display_value}}($parsing_info->{object_being_parsed}),
  };
  if ($parsing_info->{moving_down}) {
    $parsing_info->handle_inner_rule_moving_down;
  }
  else {
    $parsing_info->handle_inner_rule_moving_up;
  }
  return;
}

sub remove_node_from_parse {
  my $parsing_info = shift;
  $parsing_info->{moving_forward} = 0;
  $parsing_info->{moving_down} = 0;
  if (!$parsing_info->{current_node}->{values}->{'beyond'}) {
    $parsing_info->{blocked}->{$parsing_info->{current_node_name}}
     ->{$parsing_info->{current_value}} = 1;
  }
  if ($parsing_info->{current_node}->{values}->{value_when_entered} !=
   $parsing_info->{current_value}) {
#  croak ("value switched cannot remove");
  }
  delete $parsing_info->{active_rules_values}->
   {$parsing_info->{current_node_name}.'__XZ__XZ__'.
   $parsing_info->{current_value}};
  if ($parsing_info->{do_evaluation_in_parsing}) {
    if ($parsing_info->{current_rule}->{parsing_evaluation}) {
      $parsing_info->{parsing_evaluation_arr_ref} =
       $parsing_info->{current_node}->{previous_parsing_evaluation_arr_ref};
    }
  }
  my $parent_subrule_number =
   $parsing_info->{current_node}->{values}->{parent_subrule_number};
  if (defined $parent_subrule_number) {
    $parsing_info->{current_node} = $parsing_info->{current_node}->{parent};
    pop @{$parsing_info->{current_node}->{children}};
    $parsing_info->{current_node}->{current_subrule_number} =
     $parent_subrule_number;
    $parsing_info->{current_node}->{subrule_counts}->[$parent_subrule_number]--;
  }
  else {
    $parsing_info->{current_node} = undef;
  }
}

sub inner_rule_conditions_satisfied {
  my $parsing_info = shift;
  if (scalar(@{$parsing_info->{current_node}->{children}}) <
    $parsing_info->{current_rule}->{minimum_children}) {
    return 0;
  }
  if (($parsing_info->{current_rule}->{maximum_children}) &&
   (scalar(@{$parsing_info->{current_node}->{children}}) >
   $parsing_info->{current_rule}->{maximum_children})) {
    return 0;
  }

  my $subrule_number = $parsing_info->{current_node}->{current_subrule_number};

  if ($parsing_info->{current_rule}->{minimum_child_count} >
   $parsing_info->{current_node}->{subrule_counts}->[$subrule_number]) {
    return 0;
  }
  if ($parsing_info->{current_rule}->{minimum_child_count} &&
   ($subrule_number < $#{$parsing_info->{current_rule}->{subrule_list}})) {
    return 0;
  }

  return 1;
}

sub inner_create_child {
  my $parsing_info = shift;

  my $maximum_children =  $parsing_info->{current_rule}->{maximum_children};
  if ($maximum_children &&
   ($maximum_children ==
   scalar(@{$parsing_info->{current_node}->{children}}))) {
    $parsing_info->{moving_forward} = 0;
    $parsing_info->{moving_down} = 0;
    return;
  }

  my $subrule_number = $parsing_info->{current_node}->{current_subrule_number};
  my $subrule_max = $parsing_info->{current_rule}->{maximum_child_count};
  if ($subrule_max && 
   ($parsing_info->{current_node}->{subrule_counts}->[$subrule_number] ==
    $subrule_max)) {
    if ($subrule_number ==
     $#{$parsing_info->{current_rule}->{subrule_list}}) {
      $parsing_info->{moving_forward} = 0;
      $parsing_info->{moving_down} = 0;
      return;
    }
    else {
      $subrule_number =
       ++$parsing_info->{current_node}->{current_subrule_number};
      $parsing_info->{current_node}->{subrule_counts}->[$subrule_number] = 0;
    }
  }

  $parsing_info->{current_node}->{subrule_counts}->[$subrule_number]++;

  my $subrule_info =
   $parsing_info->{current_rule}->{subrule_list}->[$subrule_number];
  my $child_rule_name = $subrule_info->{name};
  my $alias = $subrule_info->{alias};

  my $current_value =
   &{$parsing_info->{increasing_value}}($parsing_info->{object_being_parsed});

  if (!defined $parsing_info->{rule}->{$child_rule_name}->{leaf_info}) {
    if ($parsing_info->{active_rules_values}->{$child_rule_name.'__XZ__XZ__'.
     $parsing_info->{current_value}}++) {
      croak ("$child_rule_name duplicated in parse on same string");
    }
  }

  $parsing_info->{current_node} = $parsing_info->{current_node}->new({
   parent => $parsing_info->{current_node},
   values => {
    name => $child_rule_name,
    alias => $alias,
    value_when_entered => $current_value,
    steps => $parsing_info->{steps},
    parent_subrule_number => $subrule_number,
   },
  });
  $parsing_info->{current_node}->{children} = [];
  $parsing_info->{current_node}->{current_subrule_number} = 0;
  $parsing_info->{current_node}->{subrule_counts}->[0] = 0;
  $parsing_info->{moving_forward} = 1;
  $parsing_info->{moving_down} = 1;
  if ($parsing_info->{do_evaluation_in_parsing}) {
    if ($parsing_info->{rule}->{$child_rule_name}->{parsing_evaluation}) {
      $parsing_info->{current_node}->{previous_parsing_evaluation_arr_ref} =
       $parsing_info->{parsing_evaluation_arr_ref};
      $parsing_info->{current_node}->{parsing_evaluation_arr_ref} =
       $parsing_info->{parsing_evaluation_arr_ref} = [$child_rule_name, {}];
      foreach my $alias
       (keys %{$parsing_info->{rule}->{$child_rule_name}->{rule_count}}) {
        if ($parsing_info->{rule}->{$child_rule_name}->{rule_count}->{$alias}
         > 1) {
          $parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias} = [];
        }
      }
    }
  }
}

sub mark_node_satisfied {
  my $parsing_info = shift;

  my $current_value =
   &{$parsing_info->{increasing_value}}($parsing_info->{object_being_parsed});

  if ($parsing_info->{current_node}->{ventured}->{$current_value}++) {
    $parsing_info->{moving_forward} = 0;
    $parsing_info->{moving_down} = 1;
    $parsing_info->{rejected} = 1;
  }
  else {
    my ($pe_value, $reject) = (undef, 0);
    if ($parsing_info->{do_evaluation_in_parsing}) {
      if ($parsing_info->{current_rule}->{parsing_evaluation}) {
        ($pe_value, $reject) =
         &{$parsing_info->{current_rule}->{parsing_evaluation}}(
          $parsing_info->{parsing_evaluation_arr_ref}->[1],
          $parsing_info->{object_being_parsed}
         );
      }
    }
    if (defined $reject && $reject) {
      $parsing_info->{moving_forward} = 0;
      $parsing_info->{moving_down} = 1;
      $parsing_info->{rejected} = 1;
    }
    else { # !$reject
      $parsing_info->{current_node}->{values}->{'beyond'} = 1;
      $parsing_info->{current_node}->{values}->{'pe_value'} = $pe_value;

      if ($parsing_info->{do_evaluation_in_parsing}) {
        if ($parsing_info->{current_rule}->{parsing_evaluation}) {
          my $alias = $parsing_info->{current_node}->{values}->{alias};
          $parsing_info->{parsing_evaluation_arr_ref} =
           $parsing_info->{current_node}->
           {previous_parsing_evaluation_arr_ref};

          if (defined $alias) {
            my $pe_rule_name =
             $parsing_info->{parsing_evaluation_arr_ref}->[0];

            if ($parsing_info->{rule}->{$pe_rule_name}->{rule_count}->{$alias}
              > 1) {
              push
               @{$parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias}},
               $pe_value;
             }
             else {
               $parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias} =
                $pe_value;
            }
          }
        }
      }

      $parsing_info->{moving_down} = 0;
      $parsing_info->{moving_forward} = 1;
      $parsing_info->{current_node} = $parsing_info->{current_node}->parent;
    }
  }
}

sub continue_on_to_parent {
  my $parsing_info = shift;
  if ($parsing_info->inner_rule_conditions_satisfied) {
    $parsing_info->mark_node_satisfied;
  }
  else {
    $parsing_info->{moving_forward} = 0;
    $parsing_info->{moving_down} = 1;
    $parsing_info->{rejected} = 1;
  }
}

sub move_back_to_youngest_child_or_remove_node {
  my $parsing_info = shift;
  if (scalar(@{$parsing_info->{current_node}->{children}})) {
    $parsing_info->{moving_down} = 1;
    $parsing_info->{moving_forward} = 0;

    $parsing_info->{current_node} =
     $parsing_info->{current_node}->{children}->[
      $#{$parsing_info->{current_node}->{children}}];
  }
  else {
    $parsing_info->remove_node_from_parse;
  }
}

sub handle_inner_rule_moving_down {
  my $parsing_info = shift;
  if ($parsing_info->{moving_forward}) {
    if (defined $parsing_info->{current_rule}->{leaf_info}) {
      my ($able_to_modify, $value_to_store) =
       &{$parsing_info->{leaf_parse_forward}}
       (\$parsing_info->{object_being_parsed},
        $parsing_info->{current_rule}->{leaf_info}
       );
      $parsing_info->{current_value} = &{$parsing_info->{increasing_value}}(
       $parsing_info->{object_being_parsed});
      if ($parsing_info->{current_node}->{values}->{value_when_entered} >
       $parsing_info->{current_value}) {
        croak ("Moving forward on ".
         $parsing_info->{current_node_name}." resulted in backwards progress");
      }
      if (!$able_to_modify) {
        $parsing_info->remove_node_from_parse;
      }
      else {
        $parsing_info->{current_node}->values->{'parse_match'} =
         $value_to_store;
        if ($parsing_info->{do_evaluation_in_parsing}) {
          my $eval_value = $value_to_store;
          if ($parsing_info->{remove_white_space}) {
            $eval_value =~ s/^\s*//s;
            $eval_value =~ s/\s*$//s;
          }
          my $alias = $parsing_info->{current_node}->{values}->{alias};
          if ($parsing_info->{current_rule}->{parsing_evaluation}) {
            $parsing_info->{parsing_evaluation_arr_ref}->[1] = $eval_value;
          }
          elsif (defined $alias) {
            my $pe_rule_name =
             $parsing_info->{parsing_evaluation_arr_ref}->[0];

            if ($parsing_info->{rule}->{$pe_rule_name}->{rule_count}->{$alias}
              > 1) {
              push
               @{$parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias}},
               $eval_value;
             }
             else {
               $parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias} =
                $eval_value;
            }
          }
        }
        $parsing_info->mark_node_satisfied;
      }
    }
    elsif ($parsing_info->{blocked}->{$parsing_info->{current_node_name}}->
     {$parsing_info->{current_value}}
     ) {
      $parsing_info->remove_node_from_parse;
    }
    elsif ($parsing_info->{current_rule}->{minimize_children}) {
      $parsing_info->continue_on_to_parent;
    }
    else {
      $parsing_info->inner_create_child;
    }
  }
  else { # !$parsing_info->{moving_forward}
    if ($parsing_info->{rejected}) {
      $parsing_info->{rejected} = 0;
    }
    elsif ($parsing_info->{do_evaluation_in_parsing}) {
      my $alias = $parsing_info->{current_node}->{values}->{alias};
      if (defined $alias) {
        if ($parsing_info->{rule}->
         {$parsing_info->{parsing_evaluation_arr_ref}->[0]}
         ->{rule_count}->{$alias} > 1) {
          pop @{$parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias}};
        }
        else {
          delete $parsing_info->{parsing_evaluation_arr_ref}->[1]->{$alias};
        }
      }

      if ($parsing_info->{current_rule}->{parsing_unevaluation}) {

        $parsing_info->{parsing_evaluation_arr_ref} =
         $parsing_info->{current_node}->{parsing_evaluation_arr_ref};

        &{$parsing_info->{current_rule}->{parsing_unevaluation}}(
         $parsing_info->{parsing_evaluation_arr_ref}->[1],
         $parsing_info->{object_being_parsed}
        );
      }

    }
    if ($parsing_info->{current_rule}->{leaf_info}) {
      &{$parsing_info->{leaf_parse_backtrack}}
       (\$parsing_info->{object_being_parsed},
        $parsing_info->{current_rule}->{leaf_info},
        $parsing_info->{current_node}->{values}->{'parse_match'}
       );
      $parsing_info->{current_value} = &{$parsing_info->{increasing_value}}
       ($parsing_info->{object_being_parsed});
      if (!$parsing_info->{backtrack_can_change_value} &&
       ($parsing_info->{current_node}->{values}->{value_when_entered} !=
       $parsing_info->{current_value})) {
        croak ("Reverting on ".
         $parsing_info->{current_node_name}." resulted in changed value");
      }
      $parsing_info->remove_node_from_parse;
    }
    elsif ($parsing_info->{current_rule}->{minimize_children}) {
      $parsing_info->inner_create_child;
    }
    else {
      $parsing_info->move_back_to_youngest_child_or_remove_node;
    }
  }
}

sub handle_inner_rule_moving_up {
  my $parsing_info = shift;
  if ($parsing_info->{moving_forward}) {
    if ($parsing_info->{current_rule}->{minimize_children}) {
      $parsing_info->continue_on_to_parent;
    }
    else { # !$parsing_info->{current_rule}->{minimize_children}
      $parsing_info->inner_create_child;
    }
  }
  else { # !$parsing_info->{moving_forward}
    my $subrule_number =
     $parsing_info->{current_node}->{current_subrule_number};
    if (($subrule_number < $#{$parsing_info->{current_rule}->{subrule_list}})
     && ($parsing_info->{current_node}->{subrule_counts}->[$subrule_number]
      >= $parsing_info->{current_rule}->{minimum_child_count}
     )) {
      $parsing_info->{current_node}->{current_subrule_number}++;
      $parsing_info->{current_node}->{subrule_counts}->
       [$parsing_info->{current_node}->{current_subrule_number}] = 0;
      $parsing_info->inner_create_child;
    }
    else {
      if ($parsing_info->{current_rule}->{minimize_children}) {
        $parsing_info->move_back_to_youngest_child_or_remove_node;
      }
      else { # !$parsing_info->{current_rule}->{minimize_children}
        $parsing_info->continue_on_to_parent;
      }
    }
  }
}


package Parse::Stallion;
use strict;
use warnings;
use Carp;
use File::Spec;

my $null_fh;
open($null_fh, ">", File::Spec->devnull);

sub end_of_parse_allowed {
  my $string = shift;
  if (!defined $string) { return 1};
  return $string eq '';
}

sub increasing_value {
  my $value = shift;
  if (!defined $value) {return 0};
  return 0 - length($value);
}

sub match_with_remove {
  my $object_being_parsed_ref = shift;
  my $rule = shift;
  if (my $x = $rule->{regex_match}) {
    my $y = $rule->{regex_not_match};
    if ($y && ($$object_being_parsed_ref =~ /\A($y)/)) {
      return 0, undef;
    }
    elsif ($$object_being_parsed_ref =~ s/\A($x)//) {
      my $value = $1;
      return 1, $value;
    }
    else {
      return 0, undef;
    }
  }
  else {
    croak ("leaf missing required regex_match\n");
  }
}

sub reverse_match_with_add {
  my $object_being_parsed = shift;
  my $rule_info = shift;
  my $stored_value = shift;
  $$object_being_parsed = $stored_value.$$object_being_parsed;
}

sub display_value {
  my $value = shift;
  return $value;
}

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $parameters = shift;
  my $self = {};

  $self->{remove_white_space} = $parameters->{remove_white_space};
  $self->{do_evaluation_in_parsing} = $parameters->{do_evaluation_in_parsing}
   || 0;
  $self->{do_not_compress_eval} = $parameters->{do_not_compress_eval} || 0;
  $self->{backtrack_can_change_value} =
   $parameters->{backtrack_can_change_value} || 0;
  $self->{not_string} = $parameters->{not_string};
  if ($parameters->{end_of_parse_allowed}) {
    $self->{end_of_parse_allowed} = $parameters->{end_of_parse_allowed};
  }
  else {
    $self->{end_of_parse_allowed} = \&end_of_parse_allowed;
  }
  if (defined $parameters->{parse_forward}) {
    $self->{leaf_parse_forward} = $parameters->{parse_forward};
  }
  else {
    $self->{leaf_parse_forward} = \&match_with_remove;
  }
  if (defined $parameters->{parse_backtrack}) {
    $self->{leaf_parse_backtrack} = $parameters->{parse_backtrack};
  }
  else {
    $self->{leaf_parse_backtrack} = \&reverse_match_with_add;
  }
  if (defined $parameters->{increasing_value_function}) {
    $self->{increasing_value} = $parameters->{increasing_value_function};
  }
  else {
    $self->{increasing_value} = \&increasing_value;
  }
  if (defined $parameters->{display_value_function}) {
    $self->{display_value} = $parameters->{display_value_function};
  }
  else {
    $self->{display_value} = \&display_value;
  }
  $self->{unique_name_counter} = 0;
  $self->{null_fh} = $null_fh;
  bless $self, $class;
  if (defined $parameters->{rules_to_set_up_hash}) {
    $self->set_up_full_rule_set($parameters);
  }
  else {
    croak "Missing rules_to_set_up_hash";
  }
  $self->{parse_function} = $parameters->{parse_function} ||
   \&empty_parse_function;
  return $self;
}

sub empty_parse_function {
  return shift;
}

sub parse_and_evaluate {
  my $self = shift;
  my $parameters = shift;
  if (ref $parameters eq 'SCALAR') {
    $parameters = {parse_this => $$parameters, overwrite_this => $parameters};
  }
  elsif (ref $parameters eq '') {
    $parameters = {parse_this => $parameters};
  }
  elsif (ref $parameters->{parse_this} eq 'SCALAR') {
    $parameters->{overwrite_this} = $parameters->{parse_this};
    $parameters->{parse_this} = ${$parameters->{parse_this}};
  }
  my $parser = new Parse::Stallion::Parser($self);
  my $parse_results = $parser->parse($parameters);
  my $to_return;
  if ($parser->{results}->{parse_failed}) {
    $to_return = undef;
  }
  elsif ($self->{do_evaluation_in_parsing}) {
    if (exists $parser->{results}->{parsing_evaluation}) {
      $to_return = $parser->{results}->{parsing_evaluation}
    }
    else {
      $to_return = undef;
    }
  }
  else {
    $to_return = $self->do_tree_evaluation({tree=>$parser->{results}->{tree}});
  }
  if (defined $parameters->{overwrite_this}) {
    ${$parameters->{overwrite_this}} =  $parser->{results}->{unparsed};
  }
  if (wantarray) {
    return $to_return, $parser->{results};
  }
  else {
    return $to_return;
  }
}

#package rules

sub add_rule {
  my $self = shift;
  my $rule = shift;
  my $rule_name = $rule->{rule_name} || croak ("Rule name cannot be empty");
  if ($self->{rule}->{$rule_name}) {
    croak ("Rule $rule_name already exists\n");
  }
  $self->{rule}->{$rule_name}->{generated} = $rule->{generated} || 0;
  my $base_rule = $rule->{base_rule} || $rule->{generated} || $rule_name;

  my $subrule_list;
  if ($subrule_list = $rule->{and} || $rule->{a}) {
    $self->{rule}->{$rule_name}->{maximum_children} = scalar(@$subrule_list);
    $self->{rule}->{$rule_name}->{minimum_children} = scalar(@$subrule_list);
    $self->{rule}->{$rule_name}->{minimum_child_count} = 1;
    $self->{rule}->{$rule_name}->{maximum_child_count} = 1;
  }
  elsif ($subrule_list = $rule->{or} || $rule->{o}) {
    $self->{rule}->{$rule_name}->{maximum_children} = 1;
    $self->{rule}->{$rule_name}->{minimum_children} = 1;
    $self->{rule}->{$rule_name}->{minimum_child_count} = 0;
    $self->{rule}->{$rule_name}->{maximum_child_count} = 1;
  }
  elsif ($subrule_list = $rule->{multiple} || $rule->{m} ) {
    $self->{rule}->{$rule_name}->{maximum_children} =
     $rule->{maximum_children} || 0;
    $self->{rule}->{$rule_name}->{minimum_children} =
     $rule->{minimum_children} || 0;
    $self->{rule}->{$rule_name}->{minimum_child_count} =
     $rule->{minimum_child_count} || 0;
    $self->{rule}->{$rule_name}->{maximum_child_count} =
     $rule->{maximum_child_count} || 0;
  }
  elsif (my $o = $rule->{optional} || $rule->{zero_or_one} || $rule->{z} ) {
    $subrule_list = [$o];
    $self->{rule}->{$rule_name}->{maximum_children} = 1;
    $self->{rule}->{$rule_name}->{minimum_children} = 0;
    $self->{rule}->{$rule_name}->{minimum_child_count} = 0;
    $self->{rule}->{$rule_name}->{maximum_child_count} = 1;
  }
  elsif (my $regex_match
   = $rule->{regex_match} || $rule->{leaf} || $rule->{l}) {
    $self->{rule}->{$rule_name}->{leaf_info} = {
      regex_match => $regex_match,
      regex_not_match => $rule->{regex_not_match},
    }
  }
  elsif ($rule->{leaf_info}) {
    $self->{rule}->{$rule_name}->{leaf_info} = $rule->{leaf_info};
  }
  else {
    croak "Improperly set up rule $rule_name";
  }

  $self->{rule}->{$rule_name}->{minimize_children} = $rule->{match_min_first}
   || $rule->{minimize_children} || 0;

  $self->{rule}->{$rule_name}->{parsing_evaluation} =
   $rule->{evaluation} || $rule->{e} || $rule->{eval};
  $self->{rule}->{$rule_name}->{parsing_unevaluation} =
   $rule->{parsing_unevaluation} || $rule->{u} || $rule->{uneval};

  if (defined $subrule_list) {
    if (ref $subrule_list ne 'ARRAY') {$subrule_list = [$subrule_list]};
    $self->{rule}->{$rule_name}->{subrule_list} = [];
    foreach my $subrule (@$subrule_list) {
      my $rule_name_or_rule;
      my $generated;
      my $alias;
      my $subrule_name;
      my $rule_info;
      if (ref $subrule eq 'ARRAY') {
        $alias = $subrule->[1];
        $rule_info = $subrule->[0];
      }
      else {
        $rule_info = $subrule;
      }
      if (ref $rule_info eq 'HASH') {
        $rule_name_or_rule = {%$rule_info};
        if (!defined $alias) {
          if (exists $rule_name_or_rule->{alias}) {
            $alias = $rule_name_or_rule->{alias};
          }
          elsif ($rule_name_or_rule->{regex_match} ||
           $rule_name_or_rule->{leaf} ||
           $rule_name_or_rule->{l} ||
           $rule_name_or_rule->{evaluation} ||
           $rule_name_or_rule->{e} ||
           $rule_name_or_rule->{eval}
          ) {
            $alias = '';
          }
        }
        if (!exists $rule_name_or_rule->{rule_name}) {
          $rule_name_or_rule->{rule_name} =
           $rule_name.'__XZ__'.$self->{unique_name_counter}++;
          if (!$alias) {
            $rule_name_or_rule->{generated} =
             $self->{rule}->{$rule_name}->{generated} || $rule_name;
          }
        }
        else {
          if (!defined $alias) {
            $alias = $rule_name_or_rule->{rule_name};
          }
        }
        $self->add_rule($rule_name_or_rule);
        $subrule_name = $rule_name_or_rule->{rule_name};
        if (!defined $alias) {
          foreach my $counted_rule (keys 
           %{$self->{rule}->{$subrule_name}->{rule_count}}) {
            if ($self->{rule}->{$rule_name}->{maximum_children} == 1) {
              if ((!defined
               $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule}) ||
               $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} <
               $self->{rule}->{$subrule_name}->{rule_count}->{$counted_rule}) {
                $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} =
                 $self->{rule}->{$subrule_name}->{rule_count}->{$counted_rule};
              }
            }
            elsif ($self->{rule}->{$rule_name}->{maximum_child_count} == 1) {
              $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} +=
               $self->{rule}->{$subrule_name}->{rule_count}->{$counted_rule};
            }
            else {
              $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} = 2;
            }
          }
        }
      }
      else {
        $subrule_name = $rule_info;
        $alias = $alias || $subrule_name;
      }
      push @{$self->{rule}->{$rule_name}->{subrule_list}},
       {alias => $alias, name => $subrule_name};
      if (defined $alias) {
        if ($self->{rule}->{$rule_name}->{maximum_children} == 1) {
          if (!$self->{rule}->{$rule_name}->{rule_count}->{$alias}) {
            $self->{rule}->{$rule_name}->{rule_count}->{$alias} = 1;
          }
        }
        elsif ($self->{rule}->{$rule_name}->{maximum_child_count} == 1) {
          $self->{rule}->{$rule_name}->{rule_count}->{$alias}++;
        }
        else {
          $self->{rule}->{$rule_name}->{rule_count}->{$alias} = 2;
        }
      }
    }
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
      push @unreachable, "No path to rule $rule";
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

sub return_self_routine {
  return shift;
}

sub new_generic_routine {
  my $parameters = shift;
  if (ref $parameters eq 'HASH') {
    if (keys %$parameters == 1) {
      my ($key) = keys %$parameters;
      return $parameters->{$key};
    }
  }
  return $parameters;
}

sub nothing_routine {
}

sub generate_evaluate_subroutines {
  my $self = shift;
  my $parameters = shift;
  foreach my $rule (keys %{$self->{rule}}) {
    if (!$self->{rule}->{$rule}->{generated}) {
      if (!$self->{rule}->{$rule}->{parsing_evaluation}) {
        if ($self->{do_not_compress_eval}) {
          $self->{rule}->{$rule}->{parsing_evaluation} = \&return_self_routine;
        }
        else {
          $self->{rule}->{$rule}->{parsing_evaluation} = \&new_generic_routine;
        }
      }
      if ($self->{do_evaluation_in_parsing}) {
        if (!$self->{rule}->{$rule}->{parsing_unevaluation}) {
          $self->{rule}->{$rule}->{parsing_unevaluation} = \&nothing_routine;
        }
      }
    }
  }
}

sub set_up_full_rule_set {
  my $self = shift;
  my $parameters = shift;
  my $rules_to_set_up_array = $parameters->{rules_to_set_up_array};
  my $rules_to_set_up_hash = $parameters->{rules_to_set_up_hash};
  my $start_rule = $parameters->{start_rule};

  foreach my $hash_rule_name (sort keys %$rules_to_set_up_hash) {
    $self->add_rule({rule_name => $hash_rule_name,
     %{$rules_to_set_up_hash->{$hash_rule_name}}});
  }

  if (!defined $start_rule) {
    my %covered_rule;
    foreach my $rule_name (keys %{$self->{rule}}) {
      foreach my $subrule_name
       (@{$self->{rule}->{$rule_name}->{subrule_list}}) {
        $covered_rule{$subrule_name}++;
      }
    }
    START: foreach my $rule_name (keys %{$self->{rule}}) {
      if (!$covered_rule{$rule_name}) {
        $start_rule = 'start_rule';
        last START;
      }
    }
  }

  my @missing_rules = $self->make_sure_all_names_covered({return_list=>1});
  if ($#missing_rules > -1) {
    croak "Missing rules: ".join("\n",@missing_rules)."\n";
  }
 
  $self->{start_rule} = $start_rule;
  my @unreachable_rules = $self->make_sure_all_rules_reachable({
   start_rule=>$start_rule});
  if ($#unreachable_rules > -1) {
    croak "Unreachable rules: ".join("\n",@unreachable_rules)."\n";
  }

  $self->generate_evaluate_subroutines;
}

sub which_parameters_are_arrays {
  my $self = shift;
  my $parameters = shift;
  my $rule_name = $parameters->{rule_name};
  my $rules_details = $self->{rule};
  my %to_return;
  foreach my $child_rule_name (sort keys
   %{$rules_details->{$rule_name}->{rule_count}}) {
    if ($rules_details->{$rule_name}->{rule_count}->{$child_rule_name} > 1) {
      $to_return{$child_rule_name} = 'Array';
    }
    else {
      $to_return{$child_rule_name} = 'Single Value';
    }
  }
  return \%to_return;
}

sub do_tree_evaluation {
  my $self = shift;
  my $parameters = shift;
  my $tree = $parameters->{tree};
  my $rules_details = $self->{rule};
  my $result;
  foreach my $node ($tree->bottom_up_depth_first_search) {
    my $rule_name = $node->{values}->{name};
    my $alias = $node->{values}->{alias};
    if (defined $alias) {
      if (my $subroutine_to_run =
       $rules_details->{$rule_name}->{parsing_evaluation}) {
        my $parameters;
        if (!($node->{child_values})) {
          $parameters = $node->{values}->{pvalue};
        }
        else {
          $parameters = $node->{child_values};
        }
        ($result) = &$subroutine_to_run($parameters);
      }
      else {
        $result = $node->{values}->{pvalue};
      }
      $node->{values}->{computed_value} = $result;
      my $parent = $node->parent;
      my $parent_name = undef;
      if (defined $parent) {$parent_name = $parent->{values}->{name};}
      while (defined $parent &&
       ! $rules_details->{$parent->{values}->{name}}->{parsing_evaluation}) {
        $parent = $parent->parent;
        if (defined $parent) {
          $parent_name = $parent->{values}->{name};
        }
      }
      if (defined $parent_name) {
        if ($rules_details->{$parent_name}->{rule_count}->{$alias} > 1) {
          push @{$parent->{child_values}->{$alias}}, $result;
        }
        else {
          $parent->{child_values}->{$alias} = $result;
        }
      }
    }
  }
  return $result;
}

1;

__END__

=head1 NAME

Parse::Stallion - Perl backtracking parser and resultant tree evaluator

=head1 SYNOPSIS

  use Parse::Stallion;

  my %rules = (rule_name_1 => {..rule_definition..},
   rule_name_2 => {..rule_definition..}, ...);

  my $stallion = new Parse::Stallion({
    rules_to_set_up_hash => \%rules,
    start_rule => 'rule_name_1', #default is rule which is not subrule
    do_evaluation_in_parsing => 0, #default is 0
    remove_white_space => 1, #default is 0
  });

  my $result = $stallion->parse_and_evaluate($given_string);

  my ($value, $parse_info) =
   $stallion->parse_and_evaluate({parse_this => $s, max_steps => 10});

Rule Definitions:

  {and => ['subrule_1', 'subrule_2', ...], evaluation => sub{...}}

  {or => ['subrule_1', 'subrule_2', ...], evaluation => sub{...}}

  {multiple => 'subrule_1', evaluation => sub{...}}

  {leaf => qr/regex/, evaluation => sub{...}}

=head1 DESCRIPTION

Stallion parses and evaluates a string using entered grammar rules.
The parsing is done top-down via an initial start rule, in a depth first
search forming a parse tree.
When a rule does not match the parser backtracks to a node that has another
option.

The evaluation subroutines are given a reference to a hash representing
the returned values of the named sub-nodes.
The evaluation subroutine for each node may be done while creating the
parse tree and reject a match affecting which strings parse.
This allows complex grammars.

If the evaluation is not done while parsing, if the string is
successfully parsed, the parse tree is evaluated in bottom up,
left to right order, by calling each tree node's rule's subroutine.

The grammars recognized are context free and are similar to
Extended Backus Normal Form.

The object being parsed does not need to be a string.  Except for
the section on non-strings, the documentation assumes strings are being parsed.

=head2 COMPLETE EXAMPLES

The following examples read in two unsigned integers and adds them.

  use Parse::Stallion;

   my %basic_grammar = (
    expression => {
     and => ['number',
       {regex_match => qr/\s*\+\s*/},
      'number'],
      evaluation =>
       sub {return $_[0]->{number}->[0] + $_[0]->{number}->[1]}
    },
    number => {regex_match => qr/\d+/,
      evaluation => sub{return 0 + $_[0];}}
     #0 + $_[0] converts the matched string into a number
   );

   my $parser = new Parse::Stallion(
   {rules_to_set_up_hash => \%basic_grammar});

   my $result = $parser->parse_and_evaluate('7+4');
   #$result should contain 11

   my %grammar_2 = (
    expression => {
     and => ['number',
      {regex_match => qr/\s*\+\s*/},
      ['number', 'right_number']],
      evaluation => sub {return $_[0]->{number} + $_[0]->{right_number}}
    },
    number => {regex_match => qr/\d+/,
      evaluation => sub{return 0 + $_[0];}}
   );

   my $parser_2 = new Parse::Stallion(
   {rules_to_set_up_hash => \%grammar_2, start_rule => 'expression'});

   my $result_2 = $parser_2->parse_and_evaluate('8+5');
   #$result_2 should contain 13

=head2 RULES

There are 4 rule types: B<'leaf'>, B<'and'>, B<'or'>, and B<'multiple'>.

One rule is the designated start rule from which parsing begins.
If the 'start_rule' parameter is omitted, the one rule which is not a subrule
is used as the start rule.
The start rule can be of any type, though if the start rule is a B<'leaf'>,
the grammar is essentially just a regular expression.

After a successful parse, the external nodes correspond to the substrings
that the B<'leaf'> rules matched; the other rule types correspond to the
internal nodes.

=head3 LEAF

A B<'leaf'> rule contains a regular expression that must match the
beginning part of the remaining input string.
During parsing, when a B<'leaf'> matches, the matched substring is
removed from the input string, though reattached if backtracking occurs.

Optionally, a B<'leaf'> rule can also contain a regular expression for which it
must not match.

Examples:

  {regex_match => qr/xx\w+/}

and, using a different notation,

  {'leaf' => qr/xx\w+/}

would match any perl word (\w+) starting with "xx".

  {regex_match => qr/\w+/, regex_not_match => qr/qwerty/}

would match any perl word (\w+) except for those that begin with the string
"qwerty".

=head3 AND

An B<'and'> rule contains a list of subrules that must be completely matched,
from left to right, for the 'and' rule to match.

Examples (equivalent):

  {and => ['rule_1', 'rule_2', 'rule_3']}

  {a => ['rule_1', 'rule_2', 'rule_3']}

=head3 OR

An B<'or'> rule contains a list of subrules, one of which must be matched
for the B<'or'> rule to match.

During parsing, the subrules are attempted to be matched left to right.
If a subrule matches and then is subsequently backtracked, the parser
will try to match the next subrule.  If there is no next subrule, the rule is
removed from the potential parse tree and the parser backtracks to
the B<'or'> rule's parent.

Examples (equivalent):

  {or => ['rule_1', 'rule_2', 'rule_3']};

  {o => ['rule_1', 'rule_2', 'rule_3']};

=head3 MULTIPLE (and OPTIONAL)

A B<'multiple'> rule matches if each of its subrules
match repeatedly between a minimum and maximum number of times.
The default minimum is 0 and the default maximum is "infinite".

If the maximum is undef or 0 then there is no limit to how often the
subrules can be repeated.  However, for there to be another repetition,
the input string must have been shortened, else it would be
considered an illegal form of "left recursion".

If the parameter 'match_min_first' is not set the maximal number
of allowed/possible matches of the repeating rule are tried
and then if backtracking occurs, the number of matches is decremented by one.
Else, if 'match_min_first' is set, the minimal number of matches
is tried first and the number of matches increases when backtracking.

Examples (equivalent):

  {multiple => ['rule_1', 'rule_2']};

  {m => ['rule_1', 'rule_2']};

  {m => ['rule_1', 'rule_2], match_min_first => 0,
    minimum_children=> 0, maximum_children => 0,
    minimum_child_count => 0, maximum_child_count => 0};
  }

One can label a rule with the value B<'optional'> that maps
to a B<'multiple'> rule with minimum 0 and maximum 1.

Examples (equivalent):

  {optional => 'rule_1'};

  {zero_or_one => 'rule_1'};

  {z => 'rule_1'};

  {'multiple' => 'rule_1',
   minimum_child_count => 0, maximum_child_count => 1,
   minimum_children => 0, maximum_children => 1};

=head3 SIMILARITY BETWEEN RULE TYPES.

The following rules all parse tree-wise equivalently.

  {and => ['subrule']};

  {o => ['subrule']};

  {m => 'subrule',
   minimum_child_count => 1, maximum_child_count => 1,
   minimum_children => 1, maximum_children => 1};

The following are equivalent:

  {and => ['subrule 1','subrule 2','subrule 3']};

  {'multiple' => ['subrule 1','subrule 2','subrule 3'],
   minimum_child_count => 1, maximum_child_count => 1};

The following are equivalent:

  {or => ['subrule 1','subrule 2','subrule 3']};

  {'multiple' => ['subrule 1','subrule 2','subrule 3'],
   minimum_child_count => 0, maximum_child_count => 1
   minimum_children => 1, maximum_children => 1};

=head3 NESTED RULES

Rules can be nested inside of other rules.  See the section
B<EVALUATION> for how nested rules affect tree evaluations.

To nest a rule, place it inside of a reference to a hash.
Example:

  sum => {and => ['number',
    {multiple => {and => ['plus', 'number']}}]}

is equivalent parsing wise to

  sum => { and => ['number', 'plus_numbers']};
  plus_numbers = { multiple => 'plus_number'};
  plus_number => { and => ['plus', 'number']};

One can also use an alias for a rule.
This sets the name used when evaluating the parsed expression,
but does not affect the parsing.

Example:

  adding =  {
   and => ['number', {regex_match => qr/\s*[+]\s*/},
     ['number', 'right_number'],
   e => sub {return $_[0]->{number} + $_[0]->{right_number}}
  };

=head3 RULE NAMES

Avoid naming rules with the substring '__XZ__',
to avoid confliciting with the internal names.

=head3 ENSURING RULES FORM COMPLETE GRAMMAR

Stallion ensures that a grammar is complete and 'croak's if
the given grammar has any rules not reachable from the start rule
or if within any rule a subrule does not exist.

=head2 PARSE_AND_EVALUATE

After a Parse::Stallion is set up, strings are parsed and evaluated
via parse_and_evaluate.  In scalar context, the returned value is the
returned value of the top node's evaluation routine.

=head3 RETURNED VALUES

If parse_and_evaluate is called in wantarray context, the first value
returned in the result of the evaluation and the second is information on
the parse.

  my ($value, $parse_info) =
   $stallion->parse_and_evaluate($given_string);

  $parse_info->{parse_succeeded}; # is 1 if the string parses.
  $parse_info->{parse_failed}; # is 1 if the string does not parse.
  $parse_info->{number_of_steps}; # number of steps parsing took
  $parse_info->{unparsed}; # unmatched part of string, see END_OF_PARSING
  $parse_info->{start_rule};

  $parse_info->{parse_trace};
  # reference to array of hashes showing each step, the hash keys are
  #  1) rule_name
  #  2) moving_forward (value 0 if backtracking),
  #  3) moving_down (value 0 if moving up parse tree)
  #  4) value (display_value_function of parsed object,
  #     by default the yet unparsed portion of the input string)

  $parse_info->{tree}; # the parse tree if the string parses.

The tree is an internal object having a function, that converts the
tree into a string, each node consisting of one line:

  $results->{tree}->stringify({values=>['name', 'parse_match']});

This displays the names and for B<leaf> nodes the matched string.  Internal
node names will show up.

=head3 NUMBER OF PARSE STEPS

If the parsing reaches the maximum number of steps without completing a
parse tree, the parse fails.

A step is an action on a node, roughly speaking matching a
regex for a B<'leaf'> rule, or moving forward or backtracking from a rule.

By default, the maximum number of steps is set to 20,000.
The maximum number of steps can be changed:

  $stallion->parse_and_evaluate({max_steps=>100000, parse_this=>$string});

=head3 "PARSE_FUNCTION"

One can pass in a subroutine parse_function that is executed at every
parse step and takes the current object as the parameter and its returned
value is the new current object.

   my $step = 1;
   my $parser = new Parse::Stallion(
   {rules_to_set_up_hash => \%basic_grammar, start_rule => 'expression',
    parse_function => sub {my $o = shift;print "step ".$step++."\n";return $o}
   });

Parse::Stallion::CSVFH uses this to read from a file handle.

=head3 "LEFT RECURSION"

Parse::Stallion may encounter "left recursiveness"
during parsing in which case the parsing stops and a message is 'croak'ed.

"Left recursion" occurs during parsing when the same non-B<'leaf'> rule shows
up a second time on the parse tree with the "same" input string,
measured by the increasing_value_function.

Illegal Case 1:

     expression => {and => ['expression', 'plus', 'term']};

Illegal Case 2:

     rule_with_empty => { and => ['empty', 'rule_with_empty', 'other_rule'];
     empty => {regex_match => qr//};

Illegal Case 3:

     rule_with_optional => { and => ['nothing', 'optional_rule', 'nothing'];
     nothing => { and => ['empty']};
     empty => {regex_match => qr//};
     optional_rule => {optional => 'some_other_rule'};
     some_other_rule => {regex_match => qr/x/};

The 3rd case will detect left recursiveness if the optional rule does not
match and modify the input.

=head2 EVALUATION

Evaluation can occur during or after parsing.

If after parsing, Stallion will evaluate the parse tree
in a bottom up left to right order traversal.
When each node is encountered in the traversal, the node's subroutine
is called with the parameters and the returned value of that
subroutine will be used as a parameter to the node's parent's
subroutine, or in the case of a nested rule, up to the ancestral node's
subroutine with the named rule containing the nested rule.

When setting up a rule, one can specify a subroutine to be executed during
the evaluation, specified by the parameter 'evaluation', 'eval', or 'e'.

The parameter to a leaf node's evaluation routine is the string the
node matched.
The beginning and trailing white space can be removed before being passed
to the routine by by setting the parameter remove_white_space when creating
the parser:

  $parser = new Parse::Stallion({remove_white_space => 1});

The parameter to an internal node is a hash consisting of named parameters
corresponding to the subrules of a node's rule.
If a subrule can only occur once in the parse tree as a child node
of a rule's node, the hash parameter is a single value, else the hash
parameter corresponds to an array reference to an array.

By nesting a rule with an alias, the alias is used for the name of the
hash parameter instead of the rule name.

=head3 EVALUATION DURING PARSING

If the do_evaluation_in_parsing is set when a Parse::Stallion object is
created the evaluation occurs during the parsing instead of afterwards.

Every time a node is matched, its evaluation routine is called as
it would be during evaluation after parsing.  This is possible because
a node cannot be matched until all of its children are matched.

The evaluation routine may return a second parameter that tells
Parse::Stallion to reject or not reject the match.  This allows more
control over what can be parsed.

=head4 EVALUATION DURING PARSING EXAMPLE

The following is an example of a more complicated "grammar" being
parsed.

The first statement tells a truth about the number of elements in
a list, the second tells whether or not the first statement is true.
If the second statement is true, the string parses.

  my %parsing_rules = (
   start_expression => {
    and => ['two_statements', {leaf => qr/\z/}],
    evaluation => sub {return $_[0]->{'two_statements'}},
   },
   two_statements => {
     and=> ['list_statement','truth_statement'],
     evaluation => sub {
       if ($_[0]->{list_statement} != $_[0]->{truth_statement}) {
         return (undef, 1);
       }
       return 1;
     }
   },
   list_statement => {
     and => ['count_statement', 'list'],
     evaluation => sub {
       if ($_[0]->{count_statement} == scalar(@{$_[0]->{list}})) {
         return 1;
       }
       return 0;
     }
   },
   count_statement => {
     and => [{leaf=>qr/there are /i},'number',{l=>qr/ elements in /}],
     evaluation => sub {
       return $_[0]->{number};
     }
    },
   number => {
    leaf=>qr/\d+/,
     evaluation => sub { return 0 + shift; }
   },
   list => {and => ['number', {multiple=>{and=>[{l=>qr/\,/}, 'number']}}],
    evaluation => sub {return $_[0]->{number}}
   },
   truth_statement => {
     or => [{l=>qr/\. that is the truth\./, alias=>'t'},
      {l=>qr/\. that is not the truth\./, alias=>'t'}],
     evaluation => sub {
       if ($_[0]->{t} =~ /not/) {
         return 0;
       }
       return 1;
     }
   },
  );
  
  my $how_many_parser = new Parse::Stallion({
    do_evaluation_in_parsing => 1,
    rules_to_set_up_hash => \%parsing_rules,
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

If a rule does not have an evaluation routine specified,
a generic subroutine is used.  Two routines are provided:

=head4 Generic Evaluation Routine 1

=over

=item *

If the passed in hash reference has only one key, then the value
of that key in the hash reference is returned.

=item *

If the passed in hash reference has more than one key, then the hash
reference is returned.

=back

This is the routine:

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

The second default evaluation routine will be used if do_not_compress_eval
is set when creating the parser.  It does not remove the names of the rules
and the code is simply:

  sub return_self_routine {
    return shift;
  }

Example:

  my %no_eval_rules = (
   start_rule => { and => ['term',
    {multiple => {and => [[{regex_match=>qr/\s*\+\s*/},'plus'], 'term']}}]},
   term => { and => [['number','left'],
    {multiple => {and => [[{regex_match=>qr/\s*\*\s*/},'times'],
     ['number','right']]}}]},
   number => {regex_match => qr/\s*\d*\s*/},
  );                               
                      
  my $no_eval_parser = new Parse::Stallion({do_not_compress_eval => 0,
   rules_to_set_up_hash => \%no_eval_rules,
   });

  my $no_eval_parser = new Parse::Stallion({do_not_compress_eval => 0,
   rules_to_set_up_hash => \%no_eval_rules,
   });
  
  $result = $no_eval_parser->parse_and_evaluate({parse_this=>"7+4*8"});
   
  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ '7',
                { 'left' => '4',
                  'right' => [ '8' ],
                  'times' => [ '*' ] } ] }

  my $dnce_no_eval_parser = new Parse::Stallion({do_not_compress_eval => 1,
   rules_to_set_up_hash => \%no_eval_rules,
   });

  $result = $dnce_no_eval_parser->parse_and_evaluate({parse_this=>"7+4*8"});

  #$result contains:
  { 'plus' => [ '+' ],
    'term' => [ { 'left' => '7' },
                { 'left' => '4',
                  'right' => [ '8' ],
                  'times' => [ '*' ] } ] }

=head3 Parameters to Evaluation Routines

To aid in assisting which rules return array refs and which are
single values one can call the routine which_parameters_are_arrays.


=head3 MORE COMPLICATED EXAMPLE

  The following is a simple calculator:

   %calculator_rules = (
    start_expression => {
      and => ['expression', {regex_match => qr/\z/}],
      evaluation => sub {return $_[0]->{expression}},
     },
    expression => {
      and => ['term', 
       {repeating => {and => ['plus_or_minus', 'term'],},},],
      evaluation => sub {my $to_combine = $_[0]->{term};
       my $plus_or_minus = $_[0]->{plus_or_minus};
       my $value = shift @$to_combine;
       for my $i (0..$#{$to_combine}) {
         if ($plus_or_minus->[$i] eq '+') {
           $value += $to_combine->[$i];
         }
         else {
           $value -= $to_combine->[$i];
         }
       }
       return $value;
      },
     },
    term => {
      and => ['number', 
       {repeating => {and => ['times_or_divide', 'number']}}],
      evaluation => sub {my $to_combine = $_[0]->{number};
       my $times_or_divide = $_[0]->{times_or_divide};
       my $value = shift @$to_combine;
       for my $i (0..$#{$to_combine}) {
         if ($times_or_divide->[$i] eq '*') {
           $value *= $to_combine->[$i];
         }
         else {
           $value /= $to_combine->[$i]; #does not check for zero
         }
       }
       return $value;
      }
    },
    number => {
      regex_match => qr/\s*[+\-]?(\d+(\.\d*)?|\.\d+)\s*/,
      evaluation => sub{ return 0 + $_[0]; }
    },
    plus_or_minus => {
      regex_match => qr/\s*[\-+]\s*/,
    },
    times_or_divide => {
      regex_match => qr/\s*[*\/]\s*/
    },
   );

   $calculator_parser = new Parse::Stallion({
     rules_to_set_up_hash => \%calculator_rules,
     start_rule => 'start_expression'
   });

   my $result = $calculator_parser->parse_and_evaluate("3+7*4");
   # $result should contain 31

  my $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'term'});
  # $array_p would be {number => 'Array', times_or_divide => 'Array'}

  $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'start_expression'});
  # $array_p would be {expression => 'Single Value'}

=head2 END_OF_PARSING

By default, the entire string being parsed must be matched.
This can be changed with the end_of_parse_allowed parameter which is
a routine that is given the string/object being parsed.

The following example would let any string that generated a parse tree
match:

   $aa_parser = new Parse::Stallion({
     rules_to_set_up_hash => {start_rule => {l => qr/aa/}},
     end_of_parse_allowed => sub {return 1},
   });
  
  my ($results, $info) = $aa_parser->parse_and_evaluate('aab');
  #$info->{unparsed} contains 'b'; without end_of_parse_allowed no match

If the parse_this parameter to parse_and_evaluate is a reference to a
string, after a parse, the reference will contain the unparsed string.

  my $x = 'aabb';
  my $y = $aa_parser->parse_and_evaluate($x);
  #$x will contain 'aabb', $y contains 'aa'
  $y = $aa_parser->parse_and_evaluate(\$x);
  #$x will contain 'bb', $y contains 'aa'
  $x = 'aabb';
  $y = $aa_parser->parse_and_evaluate({parse_this => \$x});
  #$x will contain 'bb', $y contains 'aa'

=head2 PARSING NON-STRINGS

Four subroutines can be provided: an increasing_value function for ensuring
parsing is proceeding correctly, a B<leaf>
rule matcher/modifier for when the parser is moving forward,
a B<'leaf'> rule unmodifier for when the parser is backtracking,
and a display_value function for what is being parsed.
One can parse non-strings this way.

  my $object_parser = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
       my $object_ref = shift;
       my $parameters = shift;
       ...
       return ($true_if_object_matches_rule,
        $value_to_store_in_leaf_node);
     },
    parse_backtrack =>
     sub {
       my ($object_ref, $rules, $value_stored_in_leaf_node) = @_;
       ...
      },
    increasing_value_function =>
     sub {
       my $object = shift;
       ...
       return $value_of_object;
     },
    display_value_function => # for parse_trace
     sub {
      my $object = shift;
      ...
      return "Value of object now ...";
     }
  });

When evaluating the parse tree, the parameters to the leaf nodes are
the values returned in parse_foward, $value_to_store_in_leaf_node.

=head3 B<'LEAF'> LEAF PARSE FORWARD/BACKTRACK

All leaf rules need to be set up such that when the
parser is moving forward and reaches a B<'leaf'>, the
B<'leaf'> rule attempts to match the current input object.
If there is a match, then the input object is modified
to the object's next state and a value is stored to be called upon
later during tree evaluation.

When backtracking, the input object should be reverted to
the state before being matched by the B<'leaf'> rule.  This
requirement can be overridden by setting the backtrack_can_change_value
parameter when setting up a new Parse::Stallion.

In parsing a string, substrings are removed from the beginning of the
string and reattached to the beginning when backtracked.

=head3 INCREASING_VALUE FUNCTION

A function, called 'increasing_value', must be provided that takes
the object being parsed and returns a numeric value that either is
unchanged or increases after the B<'leaf'> rule's
match_and_modify_input_object is called.

This function is used to detect and prevent "left recursion" by not
allowing a non-leaf rule to repeat at the same value.
B<'Multiple'> rules are prevented from repeating more than once at
the same value.

The function also speeds up parsing, cutting down on the number of steps
by not repeating dead-end parses.  If during the parse, the same rule is
attempted a second time on the parse object with the same increasing_value,
and the first parse did not succeed, then Stallion will note that the
parsing was blocked before and begin backtracking.

In parsing a input string, the negative of the length of the input
string is used as the increasing function.

=head3 STRINGS

By default, strings are matched, which is similar to

  my $calculator_stallion = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
      my $input_string_ref = shift;
      my $rule_definition = shift;
      my $match_rule = $rule_definition->{regex_match} ||
       $rule_definition->{leaf} ||
       $rule_definition->{l};
      if ($$input_string_ref =~ /\A($match_rule)/) {
        my $matched = $1;
        my $not_match_rule = $rule_definition->{regex_not_match};
        if ($not_match_rule) {
          if (!($$input_string_ref =~ /\A$not_match_rule/)) {
            return (0, undef);
          }
        }
        $$input_string_ref = substr($$input_string_ref, length($matched));
        return (1, $matched);
      }
      return 0;
     },

    parse_backtrack =>
     sub {
      my $input_string_ref = shift;
      my $rule_definition = shift;
      my $stored_value = shift;
      if (defined $stored_value) {
        $$input_string_ref = $stored_value.$$input_string_ref;
      }
     },

    increasing_value_function => sub {
      my $string = shift;
      return 0 - length($string);
    },

    display_value_function => sub display_value {
      my $value = shift;
      return $value;
    }

  });

=head1 PERL Requirements

Parse::Stallion's installation uses Test::More and Time::Local
requiring perl 5.6 or higher.
Parse::Stallion should work with earlier versions of perl and neither
of those modules is really required.

=head1 AUTHOR

Arthur Goldstein, E<lt>arthur@acm.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-8 by Arthur Goldstein

=head1 BUGS

Please email in bug reports.

=head1 TO DO AND FUTURE POSSIBLE CHANGES

Please send in suggestions.

=head1 SEE ALSO

example directory

Parsing texts, including References to Extended Backus-Naur Form notation.

Parse::Stallion::CSV and Parse::Stallion::CSVFH.

Perl 6 grammars.

lex, yacc, ..., other parsers.

=cut
