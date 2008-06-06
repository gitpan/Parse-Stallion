#Copyright 2007-8 Arthur S Goldstein

package Parse::Stallion::Talon;
use Carp;
use strict;
use warnings;
use 5.006;
our $VERSION = '0.01';

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
#values=>['steps','name','parse_match','pvalue'],show_parent=>1});
  my $self = shift;
  my $parameters = shift;
  my $values = $parameters->{values};
  my $show_parent = $parameters->{show_parent};
  my $parent = '';
  if (exists $parameters->{parent}) {
    $parent = $parameters->{parent};
  }
  my $spaces = $parameters->{spaces} || '';
  my $value_separator;
  if (exists $parameters->{value_separator}) {
    $value_separator = $parameters->{value_separator};
  }
  else {
    $value_separator = '|';
  }

  my $line = $spaces;

  if ($show_parent) {
    $line .= $parent.$value_separator;
  }

  foreach my $value (@$values) {
    if (exists $self->{values}->{$value}) {
      $line .= $self->{values}->{$value}.$value_separator;
    }
    else {
      $line .= $value_separator;
    }
  }

  $line .= "\n";
  foreach my $child ($self->children) {
    $parameters->{parent} = $self->values->{steps};
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

1;


package Parse::Stallion;
use strict;
#use warnings;
use Carp;

my $global_self;
my %handle_rule_type;
my $current_node;
my $current_node_name;
my $rule;
my $current_position;
my $tree;
my $rule_ref;
my $match_hash;
my $current_rule;
my $moving_forward;
my $moving_down;
my $steps;
my $trace;
my $do_evaluation_in_parsing;
my $string_being_parsed_yn;
my $scan_array_being_parsed;
my $object_being_parsed;
my @current_scan_array;
my %rules_from_root_to_current;
my %rules_from_root_to_current_count;
my $parsing_evaluation_hash_ref;
my @parsing_evaluation_hash_stack;
 #rules from root to current: purposes: prevent infinite loops,
 # it is a hash ref of newly traversed rules on the current string.
 #the have value corresponds to 
 # the position within the rule for 'or' rules.
 #leaves are not recorded (they have no children and cannot cause an infinite
 # loop)
 # A leaf that changes the value of the current string, by matching
 # some characters at the front, resets the active rules ref to
 # an empty hash.  If by backtracking, the leaf is removed from the
 # tree, the previous active rules list becomes active.
 #multiple and 'and' rules if appear have at most one item in the list
 #'or' rules may appear more than once in the list in strictly ascending order
my %total_rule_count;
my %ventured_out_on;
my $latest_stallion;

sub empty_parse_function {
  return shift;
}

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $parameters = shift;
  my $self = {};
  $latest_stallion = $self;
  my ($and_nodes, $or_nodes, $leaf_nodes) = @_;

  $self->{keep_white_space} = $parameters->{keep_white_space};
  $self->{scanner} = $parameters->{scanner};
  $do_evaluation_in_parsing = $self->{do_evaluation_in_parsing}
   = $parameters->{do_evaluation_in_parsing}
   || 0;
  $self->{not_string} = $parameters->{not_string};
  $self->{croak_on_failing} = $parameters->{croak_on_failing};
  $string_being_parsed_yn = 0;
  $scan_array_being_parsed = 0;
  if ($self->{scanner}) {
    $scan_array_being_parsed = 1;
  }
  elsif (!$self->{not_string}) {
    $string_being_parsed_yn = 1;
  }
  $self->{parse_function} = $parameters->{parse_function} ||
   \&empty_parse_function;
  bless $self, $class;
  if (defined $parameters->{rules_to_set_up_hash}) {
    $self->set_up_full_rule_set($parameters);
  }
  return $self;
}

sub parse_failed {
  my $self = shift;
  return $self->{parse_failed};
}

sub parse_and_evaluate {
  my $self = shift;
  my $parameters = shift;
  my $parse_results = $self->parse($parameters);
  if ($self->{parse_failed} && $self->{croak_on_failing}) {
    croak "Parse failed\n"
  }
  if (exists $self->{results}->{parsing_evaluation}) {
#print STDERR "Using pe\n";
   return $self->{results}->{parsing_evaluation}};
#print STDERR "calling dte\n";
  return $self->do_tree_evaluation({tree=>$parse_results->{tree}});
}

sub display_value {
  if ($string_being_parsed_yn) {
    return $object_being_parsed;
  }
  elsif ($scan_array_being_parsed) {
    return $#{$object_being_parsed};
  }
}
my $display_value = \&display_value;

sub increasing_value {
  if ($string_being_parsed_yn) {
    if (!defined $object_being_parsed) {return 0};
    return 0 - length($object_being_parsed);
  }
  elsif ($scan_array_being_parsed) {
    return 0 - $#{$object_being_parsed};
  }
}
my $increasing_value = \&increasing_value;

sub end_of_parse_allowed {
  if ($string_being_parsed_yn) {
#print STDERR "string $object_being_parsed\n";
    if (!defined $object_being_parsed) { return 1};
    return $object_being_parsed eq '';
  }
  elsif ($scan_array_being_parsed) {
#print STDERR "scn\n";
    if (!defined $object_being_parsed) { return 1};
    return $#{$object_being_parsed} == -1;
  }
  else {
    croak "Unknown object being parsed\n";
  }
}

sub parse {
  my $self = shift;
  my $parameters = shift;
  my @scan_array;
#print STDERR "Parse called\n";
  if ($parameters->{scan_array}) {
    @scan_array = @{$parameters->{scan_array}};
    $object_being_parsed = \@scan_array;
  }
  else {
    $object_being_parsed = $parameters->{parse_this};
  }
  $global_self = $self;
  my $start_node;
  $self->{parse_failed} = 0;
  $rule_ref = $self->{rule};
  $match_hash = {};
  if (defined $parameters->{initial_node}) {
    $start_node = $parameters->{initial_node};
  }
  else {
    $start_node = $self->{default_starting_rule};
  }
  $trace = $parameters->{trace};
  $self->{parse_trace} = [];
  my $max_steps = $parameters->{max_steps} || 20000;
  %rules_from_root_to_current = ();
  %rules_from_root_to_current_count = ();
  %total_rule_count = ($start_node => 1);
  @parsing_evaluation_hash_stack = (['beginning',{}]);
  $parsing_evaluation_hash_ref = [$start_node,{}];
  #@steps_on_node = ();

  $tree = new Parse::Stallion::Talon({
   values => {name => $start_node,
     steps => 0,
     new_value_when_entered => $self->increasing_value,
   },
  });
  $self->{tree} = $tree;

  my %parsing_info;
  $current_node = $tree;
  $moving_forward = 1;
  $moving_down = 1;
  %ventured_out_on = ();
  $steps = 0;
  $parsing_info{moved_beyond} = {};
  $parsing_info{did_not_move_beyond} = {};

  while (($steps < $max_steps) && $current_node) {
    while ($current_node && (++$steps < $max_steps)) {
      $self->parse_step(\%parsing_info);
      if ($trace) {
        print STDERR "Step $steps cnn ";
        if ($current_node) {
          print STDERR $current_node->values->{name}."\n";
        }
      }
    }
    if (!$current_node && !end_of_parse_allowed && $moving_forward) {
#print STDERR "end of parse is ".end_of_parse_allowed."\n";
#print STDERR "curr string is $object_being_parsed\n";
      $moving_forward = 0;
      $moving_down = 1;
      $current_node = $tree;
      $parsing_evaluation_hash_ref =
       $current_node->{values}->{parsing_evaluation_hash};
    }
  }
#print STDERR "parse ended\n";
  my %results;
  $results{number_of_steps} = $steps;
  $results{did_not_move_beyond} = $parsing_info{did_not_move_beyond};
  $results{moved_beyond} = $parsing_info{moved_beyond};
  $results{total_rule_count} = \%total_rule_count;
  $results{parse_trace} = $self->{parse_trace};
  if ($moving_forward && $steps < $max_steps) {
    $results{parse_succeeded} = 1;
    $results{parse_failed} = 0;
#print STDERR "Parse succeeded\n";
  }
  else {
    $results{parse_succeeded} = 0;
    $self->{parse_failed} = $results{parse_failed} = 1;
#print STDERR "Parse failed mf $moving_forward steps $steps ms $max_steps\n";
  }
  foreach my $node ($tree->bottom_up_depth_first_search) {
#use Data::Dumper;
#print STDERR "nv ".Dumper($node->{values})."\n";
    if ($trace) {
      print STDERR "considering node ".$node->{values}->{steps}."\n";
    }
    if (exists $node->values->{parse_match}) {
#print STDERR "have pm\n";
      $node->{values}->{pvalue} = $node->values->{parse_match};
    }
    elsif (!exists $node->{values}->{pvalue}) {
#print STDERR "have no pv\n";
      $node->{values}->{pvalue} = '';
    }
    if ($string_being_parsed_yn && !$self->{keep_white_space}) {
      my $parent = $node->parent;
      if (my $parent = $node->parent) {
        if (exists $parent->{values}->{pvalue}) {
          $parent->{values}->{pvalue} .= $node->values->{pvalue};
        }
        else {
          $parent->{values}->{pvalue} = $node->values->{pvalue};
        }
        if ($trace) {
         print STDERR "parent ".$parent->{values}->{steps}." ";
         print STDERR "pv ".$parent->{values}->{pvalue}."\n";}
      }
      elsif ($trace) {
        print STDERR "No parent on ".$node->{values}->{steps}."\n";
      }
      if ($trace) {print STDERR "pval now '".$node->{values}->{pvalue}."'\n";}
      $node->{values}->{pvalue} =~ s/^\s*//s;
      $node->{values}->{pvalue} =~ s/\s*$//s;
    }
    if ($trace) {print STDERR "pval now '".$node->{values}->{pvalue}."'\n";}
  }
if ($trace) {
print STDERR $tree->stringify({
 values=>['steps','name','parse_match','pvalue'],show_parent=>1});
}
  $results{tree} =
    $tree->copy_node_and_sub_nodes({values_to_copy=>[
     'pvalue', 'name','alias']});
#  if (!($self->{scanner}) && $self->{do_evaluation_in_parsing}) {}
  if ($self->{do_evaluation_in_parsing}) {
    $results{parsing_evaluation} =
     $parsing_evaluation_hash_ref->[1]->{''};
#use Data::Dumper;
#print STDERR "set pehr to ".Dumper($parsing_evaluation_hash_ref)."\n";
  }
#use Data::Dumper;
#print STDERR "pehr ".Dumper($parsing_evaluation_hash_ref)."\n";
  return $self->{results} = \%results; 
}

sub parse_step {
  my $self = shift;
  my $parameters = shift;
  #my $current_node = $parameters->{current_node};

  $object_being_parsed = &{$self->{parse_function}}($object_being_parsed);
  $current_node_name = $current_node->values->{name};
  $rule = $rule_ref->{$current_node_name};
  $current_position = $current_node->{values}->{position};
  $parameters->{blocked} = 0;
  my $current_node_type = $rule_ref->{$current_node_name}->{rule_type};
#print STDERR "mf $moving_forward md $moving_down ";
#print STDERR $current_node_name." reporting to ";
#print STDERR $parsing_evaluation_hash_ref->[0];
#print STDERR ": ".$object_being_parsed."\n";
  if (!$handle_rule_type{$current_node_type}) {
    croak("unknown rule type $current_node_type for rule $current_node_name\n");
  }
#print STDERR "nt $current_node_type cnn $current_node_name\n";
#print STDERR "cp $current_position \n";
  push @{$self->{parse_trace}}, {
   rule_name => $current_node_name,
   moving_forward => $moving_forward,
   moving_down => $moving_down,
   value => &$display_value($object_being_parsed),
  };
  &{$handle_rule_type{$current_node_type}}($self, $parameters);
#print STDERR "after pehs ".Dumper(\@parsing_evaluation_hash_stack)."\n";
  return;
}

sub create_child {
  my $child_rule_name = shift;
  my $alias = shift;
  my $child_initial_position = 0;
#use Data::Dumper;
#if ($trace) {
#print STDERR "rfrom r to c\n";
#print STDERR Dumper(\%rules_from_root_to_current)."\n";
#}
  if ($#{$rules_from_root_to_current{$child_rule_name}}>-1) {
    if ($rules_from_root_to_current{$child_rule_name}->[0]->{values}->
     {new_value_when_entered} == &$increasing_value($object_being_parsed)
     ) {
      if ($rule_ref->{$child_rule_name}->{rule_type} eq 'and') {
        croak ("$child_rule_name duplicated in parse on same string");
      }
      elsif ($rule_ref->{$child_rule_name}->{rule_type} eq 'or') {
        $child_initial_position =
         $rules_from_root_to_current{$child_rule_name}
         ->[0]->{values}->{position} + 1;
      }
      elsif ($rule_ref->{$child_rule_name}->{rule_type} eq 'multiple') {
        croak ("$child_rule_name Duplicated in parse on same string");
      }
      else {
        die "This should not have happened";
      }
    }
  }
  $current_node = $current_node->new({
   parent => $current_node,
   values => {
    name => $child_rule_name,
    alias => $alias,
    new_value_when_entered => &$increasing_value($object_being_parsed),
    steps => $steps,
    position => $child_initial_position,
   },
  });
  unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
   $current_node;
  $total_rule_count{$current_node->{values}->{name}}++;
  $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
  if (($rule_ref->{$child_rule_name}->{rule_type} ne 'leaf') &&
   ($rule_ref->{$child_rule_name}->{rule_type} ne 'scan_leaf') &&
   ($rule_ref->{$child_rule_name}->{parsing_evaluation})) {
#use Data::Dumper;
#print STDERR "adding ".Dumper($parsing_evaluation_hash_ref)."\n";
    push @parsing_evaluation_hash_stack, $parsing_evaluation_hash_ref;
    $parsing_evaluation_hash_ref = [$child_rule_name, {}];
  }
}

sub complete_matched_node {
  my $pe_value = shift;
  shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
  $moving_down = 0;
  $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
  if ($do_evaluation_in_parsing) {
    my $alias = $current_node->{values}->{alias};
    if ($rule->{parsing_evaluation}) {
      $current_node->{values}->{parsing_evaluation_hash} =
       $parsing_evaluation_hash_ref;
      $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
      if (!defined $alias) {$current_node->{values}->{alias} = $alias = ''}
    }
    my $pe_rule_name = $parsing_evaluation_hash_ref->[0];
    if (!defined $pe_rule_name || !defined $alias) {
      if ($#parsing_evaluation_hash_stack == -1) {
        $parsing_evaluation_hash_ref->[1]->{''} = $pe_value;
      }
    }
    elsif (!defined $rule_ref->{$pe_rule_name}->{rule_count}->{$alias}) {
      $parsing_evaluation_hash_ref->[1]->{$alias} = $pe_value;
    }
    elsif ($rule_ref->{$pe_rule_name}->{rule_count}->{$alias} > 1) {
      if (defined $parsing_evaluation_hash_ref->[1]->{$alias}) {
        push @{$parsing_evaluation_hash_ref->[1]->{$alias}}, $pe_value;
      }
      else {
        $parsing_evaluation_hash_ref->[1]->{$alias} = [$pe_value];
      }
    }
    else {
      $parsing_evaluation_hash_ref->[1]->{$alias} = $pe_value;
    }
  }
  $current_node = $current_node->parent;
}

sub cancel_matched_node_evaluation {
  my $alias = $current_node->{values}->{alias};
  if (defined $alias) {
    my $pe_rule_name = $parsing_evaluation_hash_ref->[0];
    if (defined $pe_rule_name) {
      if (defined $rule_ref->{$pe_rule_name}->{rule_count}->{$alias} &&
       ($rule_ref->{$pe_rule_name}->{rule_count}->{$alias} > 1)) {
        pop @{$parsing_evaluation_hash_ref->[1]->{$alias}};
      }
      else {
        delete $parsing_evaluation_hash_ref->[1]->{$alias};
      }
    }
  }
  if ($current_node->{values}->{parsing_evaluation_hash}) {
    push @parsing_evaluation_hash_stack, $parsing_evaluation_hash_ref;
    $parsing_evaluation_hash_ref =
     $current_node->{values}->{parsing_evaluation_hash};
    if (defined $rule->{parsing_unevaluation}) {
      &{$rule->{parsing_unevaluation}}($parsing_evaluation_hash_ref->[1]);
    }
  }
}

sub handle_and_rule_type {
  my $self = shift;
  my $parameters = shift;
  my $current_node_name = $current_node->{values}->{name};
  my $rule = $rule_ref->{$current_node_name};
  my $next_rule_name;
  if ($moving_forward) {
    if (!@{$current_node->{children}}) {
      $self->see_if_blocked_before($parameters);
    }
    my $node_list = $rule->{composed_of};
    my $next_and_child = scalar(@{$current_node->{children}});
    if ($parameters->{blocked}) {
#print STDERR "blocked\n";
      $parameters->{blocked} = 0;
      $moving_forward = 0;
      $moving_down = 0;
      #Make subroutine of lines below til remove_node_from_parent....?
      shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
      $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
      if ($rule->{parsing_evaluation}) {
        $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
      }
      $current_node = $current_node->remove_node_from_parent;
    }
    elsif ($next_rule_name = $node_list->[$next_and_child]) {
      $moving_down = 1;
       create_child($next_rule_name, $rule->{alias_list}->[$next_and_child]);
    }
    else {
      my ($pe_value, $reject) = (undef, 0);
      if ($rule->{parsing_evaluation}) {
        ($pe_value, $reject) =
         &{$rule->{parsing_evaluation}}($parsing_evaluation_hash_ref->[1]);
      }
      if (defined $reject && $reject) {
        $moving_forward = 0;
      }
      else { # !$reject
#parse_evaluation
        $current_node->{values}->{'beyond'} = 1;
        my $first_value = $current_node->values->{new_value_when_entered};
        my $step_name = $current_node->values->{steps};
        if (!exists $parameters->{moved_beyond}->{$current_node_name}) {
          $parameters->{moved_beyond}->{$current_node_name} = {};
        }
        $parameters->{moved_beyond}->{$current_node_name}->{$first_value} = 1;
        my $current_value = &$increasing_value($object_being_parsed);
        if ($ventured_out_on{$step_name}{$current_value}++) {
          $moving_down = 1;
          $moving_forward = 0;
        }
        else {
          complete_matched_node($pe_value);
        }
      }
    }
  }
  else { #if (!$moving_forward)
    my $last_and_child = $#{$current_node->{children}};
    if ($moving_down) {
      if ($self->{do_evaluation_in_parsing}) {
        cancel_matched_node_evaluation;
      }
      $current_node->{values}->{'beyond'} = 0;
      $current_node = $current_node->{children}->[$last_and_child];
      unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
       $current_node;
      $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
    } # if ($moving_down)
    else { #$moving_down == 0
      if ($last_and_child == -1) {
        if (!$parameters->{moved_beyond}->{$current_node_name}->
         {$current_node->values->{new_value_when_entered}}) {
          $parameters->{did_not_move_beyond}->{$current_node_name}->
           {$current_node->values->{new_value_when_entered}} = 1;
        }
        shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
        $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
        if ($rule->{parsing_evaluation}) {
          $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
        }
        $current_node = $current_node->remove_node_from_parent;
      } # $last_and_child == -1
      else {
        $current_node = $current_node->{children}->[$last_and_child];
        unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
         $current_node;
        $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
        $moving_down = 1;
      }
    }
  }
}
$handle_rule_type{'and'} = \&handle_and_rule_type;

sub handle_or_rule_type {
  my $self = shift;
  my $parameters = shift;
  my $current_node_name = $current_node->{values}->{name};
  my $rule = $rule_ref->{$current_node_name};
  my $current_position = $current_node->{values}->{position};
  if ( $moving_forward==0 ) {
    if ($moving_down) {
      if ($self->{do_evaluation_in_parsing}) {
        cancel_matched_node_evaluation;
      }
      $current_node->{values}->{'beyond'} = 0;
      $current_node = $current_node->{children}->[0];
      $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
      unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
       $current_node;
    }
    else {
      $current_position = ++$current_node->{values}->{position};
      $moving_forward = 1;
    }
  }
  if ($moving_forward) {
    my $node_list = $rule_ref->{$current_node_name}->{'any_one_of'};
    if ($moving_down && $current_position == 0) {
      $self->see_if_blocked_before($parameters);
    }
    if ($parameters->{blocked}) {
#print STDERR "blocked\n";
      $parameters->{blocked} = 0;
      $moving_forward = 0;
      $moving_down = 0;
      shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
      $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
      if ($rule->{parsing_evaluation}) {
        $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
      }
      $current_node = $current_node->remove_node_from_parent;
    }
    elsif ($current_node->{children}->[0]) { #moving_down == 0
      my ($pe_value, $reject) = (undef, 0);
      if ($rule->{parsing_evaluation}) {
        ($pe_value, $reject) =
         &{$rule->{parsing_evaluation}}($parsing_evaluation_hash_ref->[1]);
      }
      if (defined $reject && $reject) {
        $moving_down = 1;
        $moving_forward = 0;
        $current_node = $current_node->{children}->[0];
        $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
        unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
         $current_node;
      }
      else { # !$reject
        $current_node->{values}->{'beyond'} = 1;
        my $first_value = $current_node->values->{new_value_when_entered};
        $parameters->{moved_beyond}->{$current_node_name}->{$first_value} = 1;
        complete_matched_node($pe_value);
      }
    }
    elsif ($node_list->[$current_position]) {
      $moving_down = 1; #unneeded?
      create_child($node_list->[$current_position],
       $rule->{alias_list}->[$current_position]);
    }
    else { #exhausted all the nodes in the or list
      $moving_forward = 0;
      $moving_down = 0;
      if (!exists $parameters->{moved_beyond}->{$current_node_name}) {
        $parameters->{moved_beyond}->{$current_node_name} = {};
      }
      if (!$parameters->{moved_beyond}->{$current_node_name}->
       {$current_node->values->{new_value_when_entered}}) {
        if (!exists $parameters->{did_not_move_beyond}->{$current_node_name}) {
          $parameters->{did_not_move_beyond}->{$current_node_name} = {};
        }
        $parameters->{did_not_move_beyond}->{$current_node_name}->
         {$current_node->values->{new_value_when_entered}} = 1;
      }
      shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
      $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
      if ($rule->{parsing_evaluation}) {
        $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
      }
      $current_node = $current_node->remove_node_from_parent;
    }
  }
}
$handle_rule_type{'or'} = \&handle_or_rule_type;

sub match_with_remove {
  my $ignore_object_being_parsed = shift; #ignored
  my $rule = shift;
  if ($string_being_parsed_yn) {
    if (my $x = $rule->{regex_match}) {
      my $y = $rule->{regex_not_match};
      if ($y && ($object_being_parsed =~ /\A($y)/)) {
        return 0, undef;
      }
      elsif ($object_being_parsed =~ s/\A($x)//) {
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
  elsif ($scan_array_being_parsed) {
#print STDERR "mwr $object_being_parsed sbyn $string_being_parsed_yn\n\n";
#use Data::Dumper;
#print STDERR "\n";
#print STDERR Dumper($rule);
#print STDERR "\n";
#print STDERR Dumper($object_being_parsed);
#print STDERR "\n";
#print STDERR "\n";
    if (my $x = $rule->{scan_leaf_match}) {
      if (($#{$object_being_parsed} > -1) &&
       ($object_being_parsed->[0]->{token} eq $x)) {
        return 1, shift @$object_being_parsed;
      }
      else {
        return 0, undef;
      }
    }
    elsif ($#{$object_being_parsed} > -1) {
      return 0, undef;
    }
    return 1, undef;
  }
  else {
    croak ('Do not know how to parse this object');
  }
}
my $leaf_parse_forward = \&match_with_remove;

sub reverse_match_with_add {
  my $self = shift;
  if ($string_being_parsed_yn) {
    $object_being_parsed = $current_node->values->{'parse_match'}.
     $object_being_parsed;
  }
  elsif ($scan_array_being_parsed) {
    unshift @$object_being_parsed, $current_node->{values}->{'parse_match'};
  }
  else {
    croak ('Do not know how to parse this object');
  }
}
my $leaf_parse_backtrack = \&reverse_match_with_add;

sub handle_leaf_rule_type {
  my $self = shift;
  my $parameters = shift;
  my $current_node_name = $current_node->{values}->{name};
  my $rule = $rule_ref->{$current_node_name};
  shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
  $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
  my $value_to_store;
  if ($moving_forward) {
    my $value_when_entered = &$increasing_value($object_being_parsed);
    ($moving_forward,$value_to_store) =
     &$leaf_parse_forward(\$object_being_parsed, $rule);
#print STDERR "vts $value_to_store mf $moving_forward\n";
#use Data::Dumper;
#print STDERR "cnleaf $current_node_name ".Dumper($value_to_store)."\n";
    if ($value_when_entered > &$increasing_value($object_being_parsed)) {
      croak ("Moving forward on leaf $current_node_name resulted in".
       " backwards progress");
    }
    $current_node->values->{'parse_match'} = $value_to_store;
#print STDERR "cnvpm '".$current_node->values->{'parse_match'}."'\n";
  }
  else {
    &$leaf_parse_backtrack(\$object_being_parsed,
     $current_node->values->{'parse_match'});
    if ($self->{do_evaluation_in_parsing}) {
      my $alias = $current_node->{values}->{alias};
      if (defined $alias) {
        my $pe_rule_name = $parsing_evaluation_hash_ref->[0];
        if (defined $pe_rule_name) {
          if (defined $rule_ref->{$pe_rule_name}->{rule_count}->{$alias} &&
           ($rule_ref->{$pe_rule_name}->{rule_count}->{$alias} > 1)) {
            pop @{$parsing_evaluation_hash_ref->[1]->{$alias}};
          }
          else {
            delete $parsing_evaluation_hash_ref->[1]->{$alias};
          }
        }
      }
      if (defined $rule->{parsing_unevaluation}) {
        &{$rule->{parsing_unevaluation}}
         ($current_node->values->{'parse_match'});
      }
    }
  }
  if ($moving_forward) {
    my ($pe_value, $reject) = ($value_to_store, 0);
    if ($rule->{parsing_evaluation}) {
      ($pe_value, $reject) =
       &{$rule->{parsing_evaluation}}($value_to_store);
    }
#print STDERR "pe $pe_value reject $reject\n";
    if (!(defined $reject) || !$reject) {
      if ($self->{do_evaluation_in_parsing}) {
#print STDERR "working on $current_node_name vts: $value_to_store with $pe_value\n";
        my $pe_rule_name = $parsing_evaluation_hash_ref->[0];
        my $alias = $current_node->{values}->{alias};
        if (!defined $alias) {
          $current_node->{values}->{alias} = $alias = '';
        }
        if (!defined $pe_rule_name) {
#print STDERR "no prn or no alias\n";
          if ($#parsing_evaluation_hash_stack == -1) {
#print STDERR "set pev with $pe_rule_name\n";
            $parsing_evaluation_hash_ref->[1]->{''} = $pe_value;
          }
        }
        elsif (!defined $rule_ref->{$pe_rule_name}->{rule_count}->{$alias}) {
          $parsing_evaluation_hash_ref->[1]->{$alias} = $pe_value;
        }
        elsif ($rule_ref->{$pe_rule_name}->{rule_count}->{$alias} > 1) {
          if (defined $parsing_evaluation_hash_ref->[1]->{$alias}) {
            push @{$parsing_evaluation_hash_ref->[1]->{$alias}}, $pe_value;
          }
          else {
            $parsing_evaluation_hash_ref->[1]->{$alias} = [$pe_value];
          }
        }
        else {
          $parsing_evaluation_hash_ref->[1]->{$alias} = $pe_value;
        }
      }
      $current_node = $current_node->parent;
    }
    else {
      &$leaf_parse_backtrack(\$object_being_parsed,
       $current_node->values->{'parse_match'});
      $moving_forward = 0;
      $current_node = $current_node->remove_node_from_parent;
    }
  }
  else {
    $current_node = $current_node->remove_node_from_parent;
  }
  $moving_down = 0;
}
$handle_rule_type{'leaf'} = \&handle_leaf_rule_type;
$handle_rule_type{'scan_leaf'} = \&handle_leaf_rule_type;

sub handle_multiple_rule_type {
  my $self = shift;
  my $parameters = shift;
  my $current_node_name = $current_node->{values}->{name};
  my $rule = $rule_ref->{$current_node_name};
  my $next_multi_child = $#{$current_node->{children}}+1;
  my $max_to_use = 0;
  if (defined $rule->{maximum}) {
    $max_to_use = $rule->{maximum};
  }
  my $min_to_use = 0;
#use Data::Dumper;
#print STDERR "rule is ".Dumper($rule)."\n";
  if (defined $rule->{minimum}) {
    $min_to_use = $rule->{minimum} || 0;
#print STDERR "min to use set to $min_to_use\n";
  }
  if ($moving_forward) {
    if ($next_multi_child == 0) {
      if (defined
       $parameters->{maximum}->{$current_node_name}->
        {&$increasing_value($object_being_parsed)}) {
        $current_node->{max_to_use} = 
         $parameters->{maximum}->{$current_node_name}->
          {&$increasing_value($object_being_parsed)};
      }
    }
    if (defined $current_node->{max_to_use}) {
      $max_to_use = $current_node->{max_to_use};
    }
    if ($moving_down == 0) { #is this possible?
      if ($current_node->{children}->[$next_multi_child-1]->
       {values}->{new_value_when_entered}
       == &$increasing_value($object_being_parsed)) {
        croak ("Child of multiple $current_node_name did not change what is being parsed");
      }
    }
    if ($max_to_use && $max_to_use==$next_multi_child) {
      my ($pe_value, $reject) = (undef, 0);
      if ($rule->{parsing_evaluation}) {
        ($pe_value, $reject) =
         &{$rule->{parsing_evaluation}}($parsing_evaluation_hash_ref->[1]);
      }
      if (!(defined $reject) || !$reject) {
        if (!($current_node->{values}->{'beyond'})) {
          $current_node->{values}->{'beyond'} = 1;
          my $first_value = $current_node->values->{new_value_when_entered};
          $parameters->{moved_beyond}->{$current_node_name}->{$first_value} = 1;
          $parameters->{maximum}->{$current_node_name}->{$first_value} =
           $next_multi_child;
        }
        complete_matched_node($pe_value);
      }
      else { # $reject
        $moving_down = 1;
        $moving_forward = 0;
        $current_node = $current_node->{children}->[$next_multi_child-1];
        $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
        unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
         $current_node;
      }
    }
    else {
      my $repeating = $rule->{'repeating'};
      $moving_down = 1;
      create_child($repeating, $rule->{repeating_alias});
    }
  }
  else { # $moving_forward == 0
    if ($moving_down) {
      if (!$next_multi_child) {
        shift @{$rules_from_root_to_current{$current_node->{values}->{name}}};
        $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
        if ($rule->{parsing_evaluation}) {
          $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
        }
        $current_node = $current_node->remove_node_from_parent;
        $moving_down = 0;
      }
      else {
        if ($self->{do_evaluation_in_parsing}) {
          cancel_matched_node_evaluation;
        }
        $current_node = $current_node->{children}->[$next_multi_child-1];
        unshift @{$rules_from_root_to_current{$current_node->{values}->{name}}},
         $current_node;
        $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
      }
    }
    else { #$moving_down == 0
      if ($next_multi_child < $min_to_use) {
        if (!$next_multi_child) {
          if (!$parameters->{moved_beyond}->{$current_node_name}->
           {$current_node->values->{new_value_when_entered}}) {
            $parameters->{did_not_move_beyond}->{$current_node_name}->
             {$current_node->values->{new_value_when_entered}} = 1;
          }
          shift
           @{$rules_from_root_to_current{$current_node->{values}->{name}}};
          $rules_from_root_to_current_count{$current_node->{values}->{name}}--;
          if ($rule->{parsing_evaluation}) {
            $parsing_evaluation_hash_ref = pop @parsing_evaluation_hash_stack;
          }
          $current_node = $current_node->remove_node_from_parent;
        }
        else {
          $current_node = $current_node->{children}->[$next_multi_child-1];
          unshift
           @{$rules_from_root_to_current{$current_node->{values}->{name}}},
           $current_node;
          $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
          $moving_down = 1;
        }
      } # $current_position>=$min_to_use
      else {
        my ($pe_value, $reject) = (undef, 0);
        if ($rule->{parsing_evaluation}) {
          ($pe_value, $reject) =
           &{$rule->{parsing_evaluation}}($parsing_evaluation_hash_ref->[1]);
        }
        if (!(defined $reject) || !$reject) {
          $moving_forward = 1;
          if (!($current_node->{values}->{'beyond'})) {
            $current_node->{values}->{'beyond'} = 1;
            my $first_value = $current_node->values->{new_value_when_entered};
            $parameters->{moved_beyond}->{$current_node_name}->{$first_value}
             = 1;
            $parameters->{maximum}->{$current_node_name}->{$first_value} =
             $next_multi_child;
          }
          complete_matched_node($pe_value);
        }
        else { # $reject
          $moving_down = 1;
          $moving_forward = 0; #not needed?
          $current_node = $current_node->{children}->[$next_multi_child-1];
          $rules_from_root_to_current_count{$current_node->{values}->{name}}++;
          unshift
           @{$rules_from_root_to_current{$current_node->{values}->{name}}},
           $current_node;
        }
      }
    }
  }
}
$handle_rule_type{'multiple'} = \&handle_multiple_rule_type;

sub see_if_blocked_before {
  my $self = shift;
  my $parameters = shift;
  my $did_not_move_beyond = $parameters->{did_not_move_beyond};
  my $current_node_name = $current_node->{values}->{name};

#print STDERR "dnb of $current_node_name is ";
  if (!(exists $did_not_move_beyond->{$current_node_name})) {
    $did_not_move_beyond->{$current_node_name} = {};
  }
#print STDERR "cnv ".join(".cnv.",keys %{$current_node->values})."\n";
#print STDERR $did_not_move_beyond->{$current_node_name}."\n";
  if (defined
   $did_not_move_beyond->{$current_node_name}->
   {$current_node->values->{new_value_when_entered}}
  ) {
    $parameters->{blocked}=1;
  }
}

my $unique_name_counter = 0;

sub add_rule {
  my $self = shift;
  my $rule = shift;
  my $rule_name = $rule->{rule_name};
#print STDERR "adding rule $rule_name\n";
  if ($rule_name eq '') {
    croak ("Rule name cannot be empty");
  }
  if ($self->{rule}->{$rule_name}) {
    croak ("Rule $rule_name already exists\n");
  }
  my $rule_type = $rule->{rule_type};
  $self->{rule}->{$rule_name}->{generated} = $rule->{generated} || 0;
  my $base_rule = $rule->{base_rule} || $rule->{generated} || $rule_name;

  my $rule_defined=0;
  if ($rule->{composed_of} || $rule->{and} || $rule->{a}) {
    $rule_defined=1;
    if ($rule_type) {
      if ($rule_type ne 'and') {
        croak("Mismatch and rule type $rule_type for rule $rule_name");
      }
    }
    else {
      $rule_type = 'and';
    }
  }
  if ($rule->{any_one_of} || $rule->{or} || $rule->{o}) {
    $rule_defined=1;
    if ($rule_type) {
      if ($rule_type ne 'or') {
        croak("Mismatch or rule type $rule_type for rule $rule_name");
      }
    }
    else {
      $rule_type = 'or';
    }
  }
  if ($rule->{repeating} || $rule->{multiple} || $rule->{m} ) {
    $rule_defined=1;
    if ($rule_type) {
      if ($rule_type ne 'multiple') {
        croak("Mismatch multiple rule type $rule_type for rule $rule_name");
      }
    }
    else {
      $rule_type = 'multiple';
    }
  }
  if ($rule->{regex_match} || $rule->{leaf} || $rule->{l}) {
    $rule_defined=1;
    if ($rule_type) {
      if ($rule_type ne 'leaf') {
        croak("Mismatch multiple rule type $rule_type for rule $rule_name");
      }
    }
    else {
      $rule_type = 'leaf';
    }
  }
  if (defined $rule->{scan_leaf_match} || defined $rule->{scan_leaf}) {
    $rule_defined=1;
    if ($rule_type) {
      if ($rule_type ne 'scan_leaf') {
        croak("Mismatch scan leaf rule type $rule_type for rule $rule_name");
      }
    }
    else {
      $rule_type = 'scan_leaf';
    }
  }
  if (defined $rule->{optional} || $rule->{zero_or_one} || $rule->{z}) {
    if ($rule_type) {
      if ($rule_type ne 'multiple') {
        croak("Mismatch optional rule type $rule_type for rule $rule_name");
      }
    }
    $rule_defined=1;
    $rule_type = 'multiple';
    $rule->{multiple} = $rule->{optional};
    $rule->{minimum} = 0;
    $rule->{maximum} = 1;
  }

  if (!$rule_defined) {
    croak ("Unable to properly define rule $rule_name");
  }

  $self->{rule}->{$rule_name}->{evaluation} =
   $rule->{evaluation} || $rule->{e};
  if ($self->{do_evaluation_in_parsing}) {
    $self->{rule}->{$rule_name}->{parsing_evaluation} =
     $self->{rule}->{$rule_name}->{evaluation};
  }
  $self->{rule}->{$rule_name}->{rule_type} = $rule_type;
  if ($rule_type eq 'or') {
    my $any_one_of = $rule->{any_one_of} || $rule->{or} || $rule->{o};
    if (defined $any_one_of) {
      my @any_one_of_list;
      my @alias_list;
      foreach my $rule_name_or_rule (@$any_one_of) {
        my $generated;
        my $alias;
        my $sub_rule;
        if (ref $rule_name_or_rule eq 'ARRAY') {
          $alias = $rule_name_or_rule->[1];
          $rule_name_or_rule = $rule_name_or_rule->[0];
        }
        if (ref $rule_name_or_rule eq 'HASH') {
          if (exists $rule_name_or_rule->{alias}) {
            $alias = $rule_name_or_rule->{alias};
          }
          if (!exists $rule_name_or_rule->{rule_name}) {
            $rule_name_or_rule->{rule_name} =
             $rule_name.'__XZ__'.$unique_name_counter++;
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
          $sub_rule = $rule_name_or_rule->{rule_name};
          if (!defined $alias) {
            foreach my $counted_rule (keys 
             %{$self->{rule}->{$sub_rule}->{rule_count}}) {
#options are: new counted rule (ok), same count (single or array, ok),
#different count (single vs. array, not ok!)
              if ($self->{rule}->{$rule_name}->{rule_count}->{$counted_rule}
               &&
               ($self->{rule}->{$rule_name}->{rule_count}->{$counted_rule}
               != $self->{rule}->{$sub_rule}->{rule_count}->{$counted_rule})
              ) {
                croak ("Miscount 'or' rule: $rule_name, counting: ".
                 "$sub_rule, sub_rule cannot occur once in one or ".
                 "condition and multiple times in another");
              }
              else {
                $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} =
                 $self->{rule}->{$sub_rule}->{rule_count}->{$counted_rule};
              }
            }
          }
        }
        else {
          $sub_rule = $rule_name_or_rule;
          $alias = $alias || $sub_rule;
        }
        push @alias_list, $alias;
        push @any_one_of_list, $sub_rule;
        if (defined $alias) {
          if (exists $self->{rule}->{$rule_name}->{rule_count}->{$alias} &&
           $self->{rule}->{$rule_name}->{rule_count}->{$alias}==2)
          {
            croak ("Miscount 'or' rule; $rule_name, counting: $alias, ".
             "alias cannot occur multiple times in another 'or' option");
          }
          else {
            $self->{rule}->{$rule_name}->{rule_count}->{$alias}=1;
          }
        }
      }
      $self->{rule}->{$rule_name}->{any_one_of} = \@any_one_of_list;
      $self->{rule}->{$rule_name}->{alias_list} = \@alias_list;
    }
  }
  elsif ($rule_type eq 'and') {
    my $composed_of = $rule->{composed_of} || $rule->{and} || $rule->{a};
    if ($composed_of) {
      my @composed_of_list;
      my @alias_list;
      foreach my $rule_name_or_rule (@$composed_of) {
        my $alias;
        my $sub_rule;
        if (ref $rule_name_or_rule eq 'ARRAY') {
          $alias = $rule_name_or_rule->[1];
          $rule_name_or_rule = $rule_name_or_rule->[0];
        }
        if (ref $rule_name_or_rule eq 'HASH') {
          if (!exists $rule_name_or_rule->{rule_name}) {
            $rule_name_or_rule->{rule_name} =
             $rule_name.'__XX__'.$unique_name_counter++;
            if (!defined $alias) {
              $rule_name_or_rule->{generated} =
               $self->{rule}->{$rule_name}->{generated} || $rule_name;
            }
          }
          else {
            $alias = $alias || $rule_name_or_rule->{rule_name};
          }
          $self->add_rule($rule_name_or_rule);
          $sub_rule = $rule_name_or_rule->{rule_name};
          if (!defined $alias) {
            foreach my $counted_rule (keys 
             %{$self->{rule}->{$sub_rule}->{rule_count}}) {
              if (
               $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule}
              ) {
                $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule}=2;
              }
              else {
                $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} =
                 $self->{rule}->{$sub_rule}->{rule_count}->{$counted_rule};
              }
            }
          }
        }
        else {
          $sub_rule = $rule_name_or_rule;
          $alias = $alias || $sub_rule;
        }
        push @alias_list, $alias;
        push @composed_of_list, $sub_rule;
        if (defined $alias) {
          if ($self->{rule}->{$rule_name}->{rule_count}->{$alias}++) {
            $self->{rule}->{$rule_name}->{rule_count}->{$alias} = 2;
          }
        }
      }
      $self->{rule}->{$rule_name}->{composed_of} = \@composed_of_list;
      $self->{rule}->{$rule_name}->{alias_list} = \@alias_list;
    }
  }
  elsif ($rule_type eq 'leaf') {
    my $leaf_set_up = 0;
    my $regex_match = $rule->{regex_match} || $rule->{leaf} || $rule->{l};
    my $regex_not_match = $rule->{regex_not_match} || $rule->{leaf_not}
     || $rule->{ln};
    if (defined $regex_match) {
      $self->{rule}->{$rule_name}->{regex_match} = $regex_match;
      $leaf_set_up = 1;
    }
    if (defined $regex_not_match) {
      $self->{rule}->{$rule_name}->{regex_not_match} = $regex_not_match;
      $leaf_set_up = 1;
    }
    if (!$leaf_set_up) {
      croak ("cannot find leaf rule for $rule_name");
    }
  }
  elsif ($rule_type eq 'scan_leaf') {
    my $scan_leaf_match = $rule->{scan_leaf_match} || $rule->{scan_leaf};
    if (defined $scan_leaf_match) {
      $self->{rule}->{$rule_name}->{scan_leaf_match} = $scan_leaf_match;
    }
    else {
      croak ("cannot find scan leaf rule for $rule_name");
    }
  }
  elsif ($rule_type eq 'multiple') {
    my $repeating = $rule->{repeating} || $rule->{multiple} || $rule->{m};
    my $minimum = $rule->{minimum} || $rule->{min};
    my $maximum = $rule->{maximum} || $rule->{max};
    if (ref $repeating eq 'ARRAY') {
      ($repeating, $minimum, $maximum) = @$repeating;
    }
    if (defined $minimum) {
      $self->{rule}->{$rule_name}->{minimum} = $rule->{minimum};
    }
    if (defined $maximum) {
      $self->{rule}->{$rule_name}->{maximum} = $rule->{maximum};
    }
    if (defined $repeating) {
      if (ref $repeating eq 'HASH') {
        my $named_subrule;
        if (!defined $repeating->{rule_name}) {
          $repeating->{rule_name} =
           $rule_name.'__XW__'.$unique_name_counter++;
          $repeating->{generated} =
           $self->{rule}->{$rule_name}->{generated} || $rule_name;
          $named_subrule = 0;
        }
        else {
          $self->{rule}->{$rule_name}->{rule_count}->{$repeating->{rule_name}}
           = 2;
          $self->{rule}->{$rule_name}->{repeating_alias} =
           $repeating->{rule_name};
          $named_subrule = 1;
        }
        $self->add_rule($repeating);
        my $sub_rule_name = $repeating->{rule_name};
        $self->{rule}->{$rule_name}->{repeating} = $sub_rule_name;
        if (!$named_subrule) {
          foreach my $counted_rule (keys 
           %{$self->{rule}->{$sub_rule_name}->{rule_count}}) {
            $self->{rule}->{$rule_name}->{rule_count}->{$counted_rule} = 2;
          }
        }
      }
      else {
        $self->{rule}->{$rule_name}->{repeating} = $repeating;
        my $alias = $rule->{repeating_alias} || $repeating;
        $self->{rule}->{$rule_name}->{repeating_alias} = $alias;
        $self->{rule}->{$rule_name}->{rule_count}->{$alias}=2;
      }
    }
    else {
      croak ("No repeating item for rule $rule_name");
    }
  }
  else {
    croak ("Undefined rule type $rule_type");
  }
}

sub change_evaluation_for_rule {
  my $self = shift;
  my $parameters = shift;
  my $rule_name = $parameters->{rule_name};
  if (!defined $self->{rule}->{$rule_name}) {
    croak "Undefined rule $rule_name";
  }
  my $evaluation = $parameters->{evaluation};
  $self->{rule}->{$rule_name}->{evaluation} = $evaluation;
}

sub return_rule_hash_ref {
  my $self = shift;
  return $self->{rule};
}

sub make_sure_all_rules_reachable {
  my $self = shift;
  my $parameters = shift;
  my $start_rule = $parameters->{start_rule};
  my @rules_to_check = ($start_rule);
  my %rules_checked;
  $rules_checked{$start_rule} = 1;
  my $rule_to_check;
  while ($rule_to_check = shift @rules_to_check) {
    my $rule_type = $self->{rule}->{$rule_to_check}->{rule_type};
    if ('or' eq $rule_type) {
      foreach my $rule_name (@{$self->{rule}->{$rule_to_check}->{any_one_of}}) {
        if (!$rules_checked{$rule_name}) {
          push @rules_to_check, $rule_name;
          $rules_checked{$rule_name} = 1;
        }
      }
    }
    elsif ($rule_type eq 'and') {
      foreach my $rule_name
       (@{$self->{rule}->{$rule_to_check}->{composed_of}}) {
        if (!$rules_checked{$rule_name}) {
          push @rules_to_check, $rule_name;
          $rules_checked{$rule_name} = 1;
        }
      }
    }
    elsif ($rule_type eq 'multiple') {
      my $rule_name = $self->{rule}->{$rule_to_check}->{repeating};
      if (!$rules_checked{$rule_name}) {
        push @rules_to_check, $rule_name;
        $rules_checked{$rule_name} = 1;
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
    my $rule_type = $self->{rule}->{$rule}->{rule_type};
    if ('or' eq $rule_type) {
      foreach my $rule_name (@{$self->{rule}->{$rule}->{any_one_of}}) {
        if (!$self->{rule}->{$rule_name}) {
          if ($return_list) {
            push @list, "Rule $rule missing option $rule_name";
          }
          else {
            croak ("Rule $rule has undefined option of $rule_name");
          }
        }
      }
    }
    elsif ($rule_type eq 'and') {
      foreach my $rule_name (@{$self->{rule}->{$rule}->{composed_of}}) {
        if (!$self->{rule}->{$rule_name}) {
          if ($return_list) {
            push @list, "Rule $rule missing composition $rule_name";
          }
          else {
            croak ("Rule $rule has undefined composition of $rule_name");
          }
        }
      }
    }
    elsif ($rule_type eq 'multiple') {
      my $rule_name = $self->{rule}->{$rule}->{repeating};
      if (!$self->{rule}->{$rule_name}) {
        if ($return_list) {
          push @list, "Rule $rule missing repeating $rule_name";
        }
        else {
          croak ("Rule $rule has undefined repeating of $rule_name");
        }
      }
    }
  }
  return @list;
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
    if (!$self->{rule}->{$rule}->{generated} ||
     $self->{rule}->{$rule}->{evaluation}) {
      if (!$self->{rule}->{$rule}->{evaluation}) {
        $self->{rule}->{$rule}->{evaluation} = \&new_generic_routine;
      }
      if ($self->{do_evaluation_in_parsing}) {
        if (!$self->{rule}->{$rule}->{parsing_evaluation}) {
          $self->{rule}->{$rule}->{parsing_evaluation} =
           \&new_generic_routine;
        }
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

  foreach my $rule (@$rules_to_set_up_array) {
    my ($rule_name) = keys %$rule;
    $self->add_rule({rule_name => $rule_name, %{$rule->{$rule_name}}},);
  }

  foreach my $rule_name (keys %$rules_to_set_up_hash) {
    $self->add_rule({rule_name => $rule_name,
     %{$rules_to_set_up_hash->{$rule_name}}});
  }

  $self->default_start_rule({default_starting_rule=>$start_rule});

  my @missing_rules = $self->make_sure_all_names_covered({return_list=>1});
  if ($#missing_rules > -1) {
    croak "Missing rules: ".join("\n",@missing_rules)."\n";
  }
 
  my @unreachable_rules = $self->make_sure_all_rules_reachable({
   start_rule=>$start_rule});
  if ($#unreachable_rules > -1) {
    croak "Unreachable rules: ".join("\n",@unreachable_rules)."\n";
  }

  $self->generate_evaluate_subroutines;
}

sub default_start_rule {
  my $self = shift;
  my $parameters = shift;
  my $default_starting_rule = $parameters->{default_starting_rule};
  $self->{default_starting_rule} = $default_starting_rule;
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
  if (exists $self->{results}->{parsing_evaluation}) {
   return $self->{results}->{parsing_evaluation}};
#print STDERR "doing tree evaluation\n";
  my $tree = $parameters->{tree};
  my $rules_details = $self->{rule};
  my $result;
  foreach my $node ($tree->bottom_up_depth_first_search) {
    my $rule_name = $node->{values}->{name};
    my $rule_type = $rules_details->{$rule_name}->{rule_type};
#print STDERR "rule is $rule_name and type is $rule_type\n";
#print STDERR "evaluation ".$rules_details->{$rule_name}->{evaluation}."\n";
     if (my $subroutine_to_run = $rules_details->{$rule_name}->{evaluation}) {
      my $alias = $node->{values}->{alias};
      my $parameters;
      if (($rule_type eq 'leaf') || ($rule_type eq 'scan_leaf')) {
        $parameters = $node->{values}->{pvalue};
#print STDERR "leaf pvalue is '$parameters'\n";
      }
      else {
        $parameters = $node->{child_values};
#NEED: Can below be applied to or/multiple nodes?
        if ($rule_type eq 'and') {
          foreach my $child
           (keys %{$rules_details->{$rule_name}->{rule_count}}) {
            if (!exists $parameters->{$child}) {
              if (
               (!exists $rules_details->{$rule_name}->{rule_count}->{$child})
               ||
               ($rules_details->{$rule_name}->{rule_count}->{$child} <= 1)) {
                $parameters->{$child} = undef;
              }
              else {
                $parameters->{$child} = [];
              }
            }
          }
        }
      }
      ($result) = &$subroutine_to_run($parameters);
#print STDERR "rule result is $result\n";
      my $parent = $node->parent;
      my $parent_name = undef;
      if (defined $parent) {$parent_name = $parent->{values}->{name};}
      while (defined $parent &&
       ! $rules_details->{$parent->{values}->{name}}->{evaluation}) {
        $parent = $parent->parent;
        if (defined $parent) {
          $parent_name = $parent->{values}->{name};
        }
      }
      $node->{values}->{computed_value} = $result;
      if (defined $parent_name) {
        if (!defined $alias) {$alias = ''};
        if (!defined $rules_details->{$parent_name}->{rule_count}->{$alias}) {
          $parent->{child_values}->{$alias} = $result;
        }
        elsif ($rules_details->{$parent_name}->{rule_count}->{$alias} > 1) {
          push @{$parent->{child_values}->{$alias}}, $result;
        }
        else {
          #push @{$parent->{child_values}->{$alias}}, $result;
          $parent->{child_values}->{$alias} = $result;
        }
      }
    }
  }
  return $result;
}

sub remove_non_evaluated_nodes {
  my $self = shift;
  my $parameters = shift;
  my $tree = $parameters->{tree};
  my $rules_details = $self->{rule};
  foreach my $node ($tree->bottom_up_depth_first_search) {
    my $rule_name = $node->{values}->{name};
    if (!defined $rules_details->{$rule_name}->{evaluation}) {
      my $parent = $node->parent;
      foreach my $child ($node->children) {
        $child->{parent} = $parent;
      }
      $node->remove_node_from_parent({replace_with => $node->children_ref});
    }
  }
}

sub set_handle_object {
  my $self = shift;
  my $parameters = shift;
  if (defined $parameters->{parse_forward}) {
    $leaf_parse_forward = $parameters->{parse_forward};
  }
  if (defined $parameters->{parse_backtrack}) {
    $leaf_parse_backtrack = $parameters->{parse_backtrack};
  }
  if (defined $parameters->{increasing_value_function}) {
    $increasing_value = $parameters->{increasing_value_function};
  }
  if (defined $parameters->{display_value_function}) {
    $display_value = $parameters->{display_value_function};
  }
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
    start_rule => 'rule_name_1',
    do_evaluation_in_parsing => 0, #default is 0
    croak_on_failing => 1, #default is 0
    keep_white_space => 1, #default is 0
  });

  my $result =
   eval {$stallion->parse_and_evaluate({parse_this=>$given_string})};

  if ($@) {
    if ($stallion->parse_failed) {#parse failed};
  }

Rule Definitions:

  {and => ['child_rule_1', 'child_rule_2', ...], evaluation => sub{...}}

  {or => ['child_rule_1', 'child_rule_2', ...], evaluation => sub{...}}

  {multiple => 'child_rule_1', evaluation => sub{...}}

  {leaf => qr/regex/, evaluation => sub{...}}

=head1 DESCRIPTION

Stallion parses a string into a parse tree using entered grammar rules.
The parsing is done top-down via an initial start rule,
in a depth first search.
When a rule does not match the parser backtracks to a node that has another
option.

If successfully parsed, the tree may then be evaluated in bottom up,
left to right order,
by calling each tree node's rule's subroutine.
The subroutine is given one parameter: a reference to a hash representing
the returned values of the named sub-nodes.

The evaluation subroutine for each node may be done
while creating the parse tree and reject a match.
This allows complex grammars, with the caveat that backtracking needs
to be taken into account.

Some familiarity is assumed with parsing, the grammars recognized are
context free and essentially correspond to Extended Backus Normal Form.

The object being parsed does not need to be a string.  Except for
the section on non-strings, the documentation assumes strings are being parsed.

=head2 COMPLETE EXAMPLES

There is an example directory in addition to the examples presented here.

The following examples read in two unsigned integers and adds them.

  use Parse::Stallion;

   my %basic_grammar = (
    expression => {
     and => ['number',
       {regex_match => qr/\s*\+\s*/},
      'number'],
      evaluation => sub {return $_[0]->{number}->[0] + $_[0]->{number}->[1]}
    },
    number => {regex_match => qr/\d+/,
      evaluation => sub{return 0 + $_[0];}}
     #0 + $_[0] converts the matched string into a number
   );

   my $parser = new Parse::Stallion(
   {rules_to_set_up_hash => \%basic_grammar, start_rule => 'expression'});

   my $result = $parser->parse_and_evaluate({parse_this=>'7+4'});
   #$result should contain 11

   my %basic_grammar_2 = (
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
   {rules_to_set_up_hash => \%basic_grammar_2, start_rule => 'expression'});

   my $result_2 = $parser_2->parse_and_evaluate({parse_this=>'8+5'});
   #$result_2 should contain 13


=head2 RULES

There are 4 rule types: B<'leaf'>, B<'and'>, B<'or'>, and B<'multiple'>.

One rule is the designated start rule from which parsing begins.  The
start rule can be of any type, though if the start rule is a B<'leaf'>,
the grammar is essentially just a regular expression.

After a successful parse,
the external parse tree nodes correspond to the B<'leaf'>
rules.
The external nodes correspond to the substrings that the B<'leaf'> rules
matched.
The other rule types are matched with the internal nodes.

=head3 LEAF

A B<'leaf'> rule contains a regular expression that must match the
beginning part of the remaining input string.
During parsing,
when a B<'leaf'> is matched, the matched substring is removed from
the input string, though reattached if backtracking occurs.

Optionally, a B<'leaf'> rule can also contain a regular expression for which it
must not match.

Examples:

  {rule_type => 'leaf', regex_match => qr/xx\w+/}

and, using a different notation,

  {'leaf' => qr/xx\w+/}

would match any perl word (\w+) starting with "xx".

  {rule_type => 'leaf', regex_match => qr/\w+/,
    regex_not_match => qr/qwerty/}

would match any perl word (\w+) except for those that begin with the string
"qwerty".

=head3 AND

An B<'and'> rule contains a list of child rules that must be completely matched,
from left to right, for the 'and' rule to match.

Examples (all are equivalent):

  {rule_type => 'and', composed_of => ['rule_1', 'rule_2', 'rule_3']}

  {composed_of => ['rule_1', 'rule_2', 'rule_3']}

  {and => ['rule_1', 'rule_2', 'rule_3']}

  {a => ['rule_1', 'rule_2', 'rule_3']}

Would verify that when the rule is first applied to the parse string
that the 3rd character is 'Q'.

=head3 OR

An B<'or'> rule contains a list of child rules, one of which must be matched
for the B<'or'> rule to match.

During parsing, the child
rules are attempted to be matched left to right.
If a child rule matches and then is
subsequently backtracked, the parser will try to match the next child.
If there is no next child,
the rule is removed from the potential parse tree and
the parser backtracks to the B<'or'> rule's parent.

Examples (equivalent):

  {rule_type => 'or', any_one_of => ['rule_1', 'rule_2', 'rule_3']};

  {any_one_of => ['rule_1', 'rule_2', 'rule_3']};

  {or => ['rule_1', 'rule_2', 'rule_3']};

  {o => ['rule_1', 'rule_2', 'rule_3']};

=head3 MULTIPLE (and OPTIONAL)

A B<'multiple'> rule contains one single child rule which must be matched
repeatedly between a minimum and maximum number of times.
The default minimum is 0 and the default maximum is unspecified, "infinite".

If the maximum is
undef or 0 then there is no limit to how often the rule can be
repeated.  However, for there to be another repetition,
the input string must have been shortened, else it would be
considered a form of "left recursion".

Examples (equivalent):

  {rule_type => 'multiple', repeating => 'rule_1'};

  {repeating => 'rule_1'};

  {multiple => 'rule_1'};

  {m => 'rule_1', min=> 0, max => 0};

Examples (equivalent):

  {rule_type => 'multiple', repeating => 'rule_1',
   maximum => 10, minimum => 2};

  {repeating => 'rule_1', maximum => 10, minimum => 2};

  {multiple => 'rule_1', max => 10, minimum => 2};

  {repeating => ['rule_1', 2, 10]};

  {multiple => ['rule_1', 2, 10]};

  {m => ['rule_1', 2, 10]};

One can label a rule with the value B<'optional'> that maps
to a B<'multiple'> rule with minimum 0 and maximum 1.

Examples (equivalent):

  {optional => 'rule_1'};

  {p => 'rule_1'};

  {rule_type => 'multiple', repeating => 'rule_1',
   min => 0, maximum => 1};

  {m => ['rule_1',0,1]};

In parsing, the child rule being matched is matched as many times
as possible up to the maximum. If the parsing backtracks a
child node is removed;
if the number of child nodes falls below the minimum,
all child nodes are removed and the
B<'multiple'> rule node is removed from the parse tree.

=head3 SIMILARITY BETWEEN RULE TYPES.

The following rules all parse tree-wise equivalently.

  {rule_type => 'and', composed_of => ['sub_rule']};

  {a => ['sub_rule']};

  {rule_type => 'or', any_one_of => ['sub_rule']};

  {o => ['sub_rule']};

  {rule_type => 'multiple', repeating => ['sub_rule'], min => 1, max => 1};

  {m => ['sub_rule', 1, 1]};

=head3 NESTED RULES

Rules can be nested inside of other rules, cutting down on the code required.
See the section B<EVALUATION> for how nested rules affect tree
evaluations.

To nest a rule, place it inside of a reference to a hash.
Example:

  sum => {composed_of => ['number',
    {repeating => {composed_of => ['plus', 'number']}}]}

is equivalent parsing-wise to

  sum => {rule_type => 'and',
   composed_of => ['number', 'plus_numbers']};
  plus_numbers = {rule_type => 'multiple',
    repeating => 'plus_number'};
  plus_number => {rule_type => 'and',
   composed_of => ['plus', 'number']};

One can also use an alias for a rule.  This does not affect the parsing,
but does affect the names on the parse tree as well as evaluating the
parse tree. Example:

  adding =  {rule_type => 'and',
   composed_of => ['number', {regex_match => qr/\s*[+]\s*/},
     ['number', 'right_number']};

=head3 RULE NAMES

Avoid naming rules with the substrings '__XX__', '__XY__',
or '__XZ__', to avoid confliciting with the derived nested rules' names.

=head3 ENSURING RULES FORM COMPLETE GRAMMAR

Stallion ensures that a grammar is complete and 'croak's if
the given grammar has any rules not reachable from the start rule
or if within any rule a child rule does not exist.

=head2 PARSING

After a grammar has been set up, a string can be passed in to
be parsed into a parse tree.

Parsing consists of copying the given string into an input string.
Then a depth first search is performed following the grammar.

When a B<'Leaf'> rule is encountered, if the input string matches
the rule, a substring is removed and the parsing continues forward;
else, backtracking occurs.

It is expected that one will want to parse and evaluate a string
but one may just generate a parse tree:

  my $stallion = new Parse::Stallion({
    rules_to_set_up_hash => \%rules,
    start_rule => 'rule_name_1'
  });

  my $results = $stallion->parse({parse_this=>$string_to_parse});

  $results->{parse_succeeded} is 1 if the string parses.
  $results->{parse_failed} is 1 if the string does not parse.
  $results->{tree} contains the parse tree if the string parses.

The tree is an internal object, Parse::Stallion::Talon,
which has a function, that converts the parse tree into
a string, each node consisting of one line:

  $results->{tree}->stringify({values=>['parse_match'],show_parent=>1});


=head3 NUMBER OF PARSE STEPS

One can set the maximum number of steps when parsing. 
If the parsing reaches the maximum number of steps without completing a
parse tree, the parse fails.

A step is
an action on a node, roughly speaking matching a
regex for a B<'leaf'> rule, moving forward to check the next
 rule in and B<'and'>
or B<'or'> rule, attempting to repeat the specified
 rule in a B<'multiple'> rule,
or backtracking from a rule.

By default, the maximum number of steps is set to 20,000.
The maximum number of steps is set by the max_steps parameter when
calling parse or parse_and_evaluate:

  $stallion->parse_and_evaluate({max_steps=>100000, parse_this=>$string});

=head3 "LEFT RECURSION"

Stallion does not determine if a grammar is "left
recursive" when creating the grammar.
It may encounter "left recursiveness"
during parsing in which case the parsing stops and a message is 'croak'ed.

"Left recursion" occurs
during parsing when the same non-leaf rule shows up a next time
on the parse tree
and the input string has not changed when it showed up previously.

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
match.

If during the evaluation 2 'or' nodes are encountered with the
the same rule and the same string, the 2nd 'or' node starts
its evaluation with the any_one_of choice after the 1st 'or' node..
Brief example:,

     'or_rule' => {'or' => ['a', 'b']};
     'a' => {'and' => ['or_rule', 'x']};

the first time the or_rule is encountered, it first tries child 'a'.
When parsing 'a', the 'or_rule' is encountered again, since the
parsed string is the same when first encountered, the second 'or_rule'
starts its evaluation at 'b'.  QUESTION: should the parse grammar
be illegal?

=head3 PARSE_TRACE

One of the results returned from the parse function is an array of
each step performed, returned in {parse_trace}.
Each array entry is a hash with elements such as the name of the
rule being parsed, the direction of the trace, the current
value of the parse object; for a string, that is the position within
the string.

=head2 EVALUATION

Evaluation can occur during or after parsing.

After parsing, Stallion can evaluate the parse tree
in a bottom up left to right order traversal.
When each node is encountered in the traversal, its subroutine
is called with the parameters and the returned value of that
subroutine will be used as a parameter to its parent
subroutine, or in the case of a nested rule, up to the named rule
containing the nested rule.

When setting up a rule, one can specify a subroutine to be
executed during the evaluation, specified by the parameter
'evaluation' or 'e'.

The parameter to a leaf node's routine
is the string
the node matched with beginning and trailing white space removed.
This removal can be overridden by setting the parameter keep_white_space
when creating the object:

  $parser = new Parse::Stallion({keep_white_space => 1});

The parameter to an internal node is a hash consisting
of named parameters corresponding to the child rules of
a node's rule.  If a child rule only occurs once in the definition of
its parent rule, the hash parameter is a single value, else
the hash parameter corresponds to a reference to an array of
all the child values.

By nesting a rule with an alias,
the alias is used for the name of the hash parameter instead of
the rule name.

=head3 EVALUATION DURING PARSING

If the parameter do_evaluation_in_parsing is set when a Parse::Stallion
object is created the evalatuion occurs during the parsing instead of
afterwards.

Every time a node is matched, its evaluation routine is called as
it would be during evaluation after parsing.  This is possible because
a node cannot be matched until all of its children are matched.

The evaluation routine may return a second parameter that tells
Parse::Stallion to reject or not reject the match.  This allows more
control over what can be parsed.

When backtracking to a matched node, the node's unevaluation routine
is called.

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
  
  $result = $how_many_parser->parse_and_evaluate({
    parse_this=>"there are 5 elements in 5,4,3,2,1. that is the truth."});
  
  print "$result should be 1\n";
  
  $result = $how_many_parser->parse_and_evaluate({
    parse_this=>"there are 5 elements in 5,4,3,1. that is not the truth."});
  
  print "$result should be 1\n";
  
  $result = $how_many_parser->parse_and_evaluate({
    parse_this=>"there are 5 elements in 5,4,3,1. that is the truth."});
  
  print "$result should be undef\n";


=head3 DEFAULT EVALUATION ROUTINE

If a rule does not have an evaluation routine specified,
a default subroutine is used
which does one of two things:

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
       {repeating => {composed_of => ['plus_or_minus', 'term'],},},],
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
      composed_of => ['number', 
       {repeating => {composed_of => ['times_or_divide', 'number']}}],
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

   my $result = $calculator_parser->parse_and_evaluate({parse_this=>"3+7*4"});
   # $result should contain 31

  my $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'term'});
  # $array_p would be {number => 'Array', times_or_divide => 'Array'}

  $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'start_expression'});
  # $array_p would be {expression => 'Single Value'}

=head2 PARSING NON-STRINGS

In order to parse something other than a string, three subroutines
must be provided: an increasing_value function for ensuring
parsing is proceeding correctly, a B<leaf>
rule matcher/modifier for when the parser is moving forward,
and a B<'leaf'> rule unmodifier for when the parser is backtracking.

  $stallion->set_handle_object({
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
       my ($object_ref, $value_stored_in_leaf_node) = @_;
       ...
      },
    increasing_value_function =>
     sub {
       my $object = shift;
       ...
       return $value_of_object;
     }
  })

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
the state before being matched by the B<'leaf'> rule.

In parsing a string, substrings are removed from the beginning of the
string and reattached to the beginning when backtracked.

=head3 INCREASING_VALUE FUNCTION

A function, called 'increasing_value', must be provided that takes
the object being parsed and returns a numeric value that either is
unchanged or increases after the B<'leaf'> rule's
match_and_modify_input_object is called.

This function is used to
detect and prevent "left recursion" by not allowing a non-leaf rule to
repeat at the same value.
B<'Multiple'> rules are prevented from
repeating more than once at the same value.

The function also speeds up parsing, cutting down on the number
of steps by not repeating dead-end parses.  If during the parse,
the same rule is attempted a second time on the parse object with
the same increasing_value, and the first parse did not succeed, then
Stallion will note that the parsing was blocked before and begin
backtracking.

In parsing a input string, the negative of the length of the input
string is used as the increasing function.

=head3 STRINGS

By default, strings are matched, which is similar to

  $calculator_stallion->set_handle_object({
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
      my $stored_value = shift;
      if (defined $stored_value) {
        $$input_string_ref = $stored_value.$$input_string_ref;
      }
     },

    increasing_value_function => sub {
      my $string = shift;
      return 0 - length($string);
    }
  });


=head3 SCANNED ARRAYS

The following lexical analyzer/parser combination illustrates parsing
a non-string.
The lexical analyzer may "parse" the input string using grammar rules
that identify tokens, resulting in a list.
The list/array of tokens would then be "parsed".
This second parsing would be of an array, not a string.

Parse::Stallion has built in support for parsing a scanned array.
This is done by setting the parameter 'scanner' to true when creating the
Parse::Stallion object.  In addition, B<'leaf'> rules should be
created with 'scan_leaf' instead of 'leaf'.

In parsing a scanned array, the first element of the array is shift'ed
off.  When backtracking, the element is unshift'ed back onto the array.
In parsing a scanned array, the negative of the number of
items (0-$#array) is used as the increasing_value function.

=head1 AUTHOR

Arthur Goldstein, E<lt>arthur@acm.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007-8 by Arthur Goldstein

=head1 BUGS

Please email in bug reports.

=head1 TO DO AND FUTURE POSSIBLE CHANGES

Determine if 'or' rules should have behavior that they cannot be repeated on
the same string or they should just not repeat the chosen child on the
same string (current behavior).

Document or remove other %results returned.

The code uses global variables, this is done deliberately in order
to speed up the search, though not clear if this is really need.

Parse::Stallion requires Test::More and Time::Local and perl 5.6 or higher.
This is due to the installation test cases and the way the
 makefile is set up.  Parse::Stallion should
work with earlier versions of perl and neither of those modules is
really required.

The test cases that come with the module include some interesting
code, such as parsing dates and compiling/running a program.  Should expand
these out into an examples directory.

Are scan_array's so important as to warrant a separate parameter?  Are
they important enough to be part of the module?

Should multiple rules be matched in a lazy method in addition to
the currently implemented greedy method?  If assuming only one match
this doesn't matter but there may be other cases.

Is it desirable to shrink the notation used to express rules more akin
to perl regex'es?  I.e.: have array references always be and nodes,
 hashes be or's, have an * next to a field refer to multiple, ....

Should it be easy to automate parsing repeatedly (similar to the
g option in regex's)?  Should other "functionalities" of regex's
be incorporated, i.e. substitutions, matching into $1, $2, ...

In evaluating nodes, should there be other parameters?  Such as
the position in the string being parsed.

Have some evaluations/subroutines done during the parsing but
do the majority of them aferwards?  This would allow fewer subroutines
to be called.  An example would be to have a routine that verifies
that a leaf is a correct value, similar to the current regex_not_match,
but not have the tree parsed until afterwards.

What should the default behavior on white space be around leaves?

=head1 SEE ALSO

Look up Extended Backus-Naur Form notation and trace back from there.

Parse::Stallion::CSV and Parse::Stallion::CSVFH, examples
 of how to use Parse::Stallion.

Perl 6 grammars.

Please send suggestions.
What comes to mind is lex, yacc, Parse::RecDescent, ..., other parsers.

=cut
