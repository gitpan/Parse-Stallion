#Copyright 2007-8 Arthur S Goldstein

package Parse::Stallion::Talon;
use Carp;
use strict;
use warnings;
use 5.006;
our $VERSION = '0.11';

sub new {
  my $type = shift;
  my $class = ref($type) || $type;
  my $parameters = shift;
  my $parent = $parameters->{parent};
  my $self = {};
  bless $self, $class;

  if ($self->{parent} = $parent) {
    push @{$parent->{children}}, $self;
  }
  $self->{values} = $parameters->{values};
  $self->{children} = [];

  return $self;
}

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
    if (defined $self->{values}->{$value}) {
      $line .= $self->{values}->{$value}.$value_separator;
    }
    else {
      $line .= $value_separator;
    }
  }

  $line .= "\n";
  foreach my $child (@{$self->{children}}) {
    $parameters->{spaces} = $spaces.' ';
    $line .= $child->stringify($parameters);
  }

  return $line;
}

sub bottom_up_depth_first_search {
  my $self = shift;
  my @qresults;
  my @queue = ($self);
  while (my $node = pop @queue) {
    unshift @qresults, $node;
    foreach my $child (@{$node->{children}}) {
      push @queue, $child;
    }
  }
  return @qresults;
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
  my $max_steps = $parameters->{max_steps} || 20000;

  my $first_alias = 'b'.$parsing_info->{separator}.$parsing_info->{separator};
  my $tree = new Parse::Stallion::Talon({
   values => {name => $start_node,
     steps => 0,
     value_when_entered =>
      &{$parsing_info->{increasing_value}}($object_being_parsed),
     alias => $first_alias,
   },
  });
  $tree->{current_subrule_number} = 0;
  $tree->{subrule_counts}->[0] = 0;

  $parsing_info->{results}->{tree} = $parsing_info->{current_node} = $tree;
  $parsing_info->{moving_forward} = 1;
  $parsing_info->{moving_down} = 1;
  $parsing_info->{results}->{parse_trace} = $parsing_info->{parse_trace} = [];
  $parsing_info->{steps} = 0;
  $parsing_info->{active_rules_values} = {};
  $parsing_info->{object_being_parsed} = $object_being_parsed;
  $parsing_info->{current_value} =
   &{$parsing_info->{increasing_value}}($object_being_parsed);
  $parsing_info->{message} = 'Start of Parse';

  while (($parsing_info->{steps} < $max_steps) &&
   $parsing_info->{current_node}) {
    while ($parsing_info->{current_node} &&
     (++$parsing_info->{steps} < $max_steps)) {
      $parsing_info->parse_step;
    }
    if (!$parsing_info->{current_node} &&
      $parsing_info->{moving_forward} &&
     (!(!(defined $parsing_info->{object_being_parsed}) ||
       ($parsing_info->{object_being_parsed} eq ''))) ) {
       $parsing_info->{moving_forward} = 0;
       $parsing_info->{moving_down} = 1;
       $parsing_info->{current_node} = $tree;
    }
  }
  $parsing_info->{results}->{start_rule} = $parsing_info->{start_rule};
  $parsing_info->{results}->{number_of_steps} = $parsing_info->{steps};
  if ($parsing_info->{moving_forward} && $parsing_info->{steps} < $max_steps) {
    $parsing_info->{results}->{parse_succeeded} = 1;
    if ($parsing_info->{do_evaluation_in_parsing}) {
      $parsing_info->{results}->{parsing_evaluation} =
       $tree->{values}->{computed_value};
    }
  }
  else {
    $parsing_info->{results}->{parse_succeeded} = 0;
  }
}

sub parse_step {
  my $parsing_info = shift;

  $parsing_info->{object_being_parsed} =
   &{$parsing_info->{parse_function}}($parsing_info->{object_being_parsed});
  my $current_node_name = $parsing_info->{current_node_name} =
   $parsing_info->{current_node}->{values}->{name};
  my $current_rule = $parsing_info->{current_rule} =
   $parsing_info->{rule}->{$current_node_name};
  my $parent_step = 0;
  if ($parsing_info->{current_node}->{parent}) {
    $parent_step = $parsing_info->{current_node}->{parent}->{values}->{steps};
  }
  push @{$parsing_info->{parse_trace}}, {
   rule_name => $current_node_name,
   moving_forward => $parsing_info->{moving_forward},
   moving_down => $parsing_info->{moving_down},
   value =>
    &{$parsing_info->{display_value}}($parsing_info->{object_being_parsed}),
   node_creation_step => $parsing_info->{current_node}->{values}->{steps},
   parent_node_creation_step => $parent_step,
   message => $parsing_info->{message},
  };
  $parsing_info->{message} = '';
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
    croak ("Change of increasing_value_function on backtrack.");
  }
  delete $parsing_info->{active_rules_values}->
   {$parsing_info->{current_node_name}.$parsing_info->{separator}.
    $parsing_info->{separator}.$parsing_info->{current_value}};
  $parsing_info->{message} = "Removed node created on step ".
   $parsing_info->{current_node}->{values}->{steps};
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
  if (($parsing_info->{current_rule}->{rule_type} eq 'OR') &&
   (!scalar(@{$parsing_info->{current_node}->{children}}))) {
    return 0;
  }

  my $subrule_number = $parsing_info->{current_node}->{current_subrule_number};

  if ($parsing_info->{current_rule}->{minimum_child} &&
   (($parsing_info->{current_rule}->{minimum_child} >
     $parsing_info->{current_node}->{subrule_counts}->[$subrule_number]) ||
    ($subrule_number < $#{$parsing_info->{current_rule}->{subrule_list}}))) {
    return 0;
  }

  return 1;
}

sub inner_create_child {
  my $parsing_info = shift;

  my $subrule_number = $parsing_info->{current_node}->{current_subrule_number};
  if ($parsing_info->{current_rule}->{rule_type} eq 'OR' &&
   (scalar(@{$parsing_info->{current_node}->{children}}))) {
    $parsing_info->{moving_forward} = 0;
    $parsing_info->{moving_down} = 0;
    $parsing_info->{message} = "On subrule $subrule_number, cannot create ".
     "more children for node created on step ".
     $parsing_info->{current_node}->{values}->{steps};
    return;
  }

  $parsing_info->{message} = "Cannot create child for node created on step ".
   $parsing_info->{current_node}->{values}->{steps}." subrule $subrule_number";
  my $subrule_max = $parsing_info->{current_rule}->{maximum_child};
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
    if ($parsing_info->{active_rules_values}->{$child_rule_name.
     $parsing_info->{separator}.$parsing_info->{separator}.
     $parsing_info->{current_value}}++) {
      croak ("$child_rule_name duplicated in parse on same string");
    }
  }

  $parsing_info->{message} = "Created child on step ".$parsing_info->{steps}.
   " for node created on step ".
   $parsing_info->{current_node}->{values}->{steps};
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
    my $reject;
    if ($parsing_info->{do_evaluation_in_parsing}) {
      (undef, $reject) = $parsing_info->{self}->new_evaluate_tree_node(
       {node => $parsing_info->{current_node},
        object => $parsing_info->{object_being_parsed}});
    }
    if (defined $reject && $reject) {
      $parsing_info->{moving_forward} = 0;
      $parsing_info->{moving_down} = 1;
      $parsing_info->{rejected} = 1;
    }
    else { # !$reject
      $parsing_info->{current_node}->{values}->{'beyond'} = 1;

      $parsing_info->{message} = "Completed node created on step ".
       $parsing_info->{current_node}->{values}->{steps};
      $parsing_info->{moving_down} = 0;
      $parsing_info->{moving_forward} = 1;
      $parsing_info->{current_node} = $parsing_info->{current_node}->{parent};
    }
  }
}

sub continue_on_to_parent {
  my $parsing_info = shift;
  $parsing_info->{message} = "Rejected node created on step ".
   $parsing_info->{current_node}->{values}->{steps};
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
    $parsing_info->{message} = "Backwards to youngest child";
    $parsing_info->{moving_down} = 1;
    $parsing_info->{moving_forward} = 0;

    my $current_node = $parsing_info->{current_node} =
     $parsing_info->{current_node}->{children}->[
      $#{$parsing_info->{current_node}->{children}}];
    if ($parsing_info->{do_evaluation_in_parsing}) {
      $parsing_info->{self}->new_unevaluate_tree_node(
       {node => $parsing_info->{current_node},
        object => $parsing_info->{object_being_parsed}});
    }
  }
  else {
    $parsing_info->remove_node_from_parse;
  }
}

sub handle_inner_rule_moving_down {
  my $parsing_info = shift;
  if ($parsing_info->{moving_forward}) {
    if (defined $parsing_info->{current_rule}->{leaf_info}) {
      $parsing_info->{message} = 'Leaf not matched';
      my ($able_to_modify, $match) =
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
        $parsing_info->{current_node}->{values}->{parse_match} = $match;
        $parsing_info->mark_node_satisfied;
        $parsing_info->{message} = 'Leaf matched';
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
    if ($parsing_info->{current_rule}->{leaf_info}) {
      &{$parsing_info->{leaf_parse_backtrack}}
       (\$parsing_info->{object_being_parsed},
        $parsing_info->{current_rule}->{leaf_info},
        $parsing_info->{current_node}->{values}->{parse_match}
       );
      $parsing_info->{current_value} = &{$parsing_info->{increasing_value}}
       ($parsing_info->{object_being_parsed});
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
      >= $parsing_info->{current_rule}->{minimum_child}
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
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT =
 qw(A AND O OR LEAF L M MULTIPLE NON_STRING_LEAF N OPTIONAL ZERO_OR_ONE Z
    E EVALUATION U UNEVALUATION MATCH_MIN_FIRST USE_PARSE_MATCH);
use strict;
use warnings;
use Carp;
use File::Spec;

sub increasing_value {
  my $value = shift;
  if (!defined $value) {return 0};
  return 0 - length($value);
}

sub match_with_remove {
  my $object_being_parsed_ref = shift;
  my $rule = shift;
  my $x = $rule->{regex_match};
  if ($$object_being_parsed_ref =~ s/\A$x//) {
    return 1, $&;
  }
  else {
    return 0, undef;
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

  bless $self, $class;
  $self->{leaf_parse_forward} = \&match_with_remove;
  $self->{leaf_parse_backtrack} = \&reverse_match_with_add;
  $self->{increasing_value} = \&increasing_value;
  $self->{display_value} = \&display_value;
  $self->{parse_function} = \&empty_parse_function;
  $self->{separator} = '__XZ__';
  $self->{self} = $self;
  if (!defined $parameters->{rules_to_set_up_hash}) {
    $self->set_up_full_rule_set({rules_to_set_up_hash=>$parameters});
  }
  else {
    $self->{remove_white_space} = $parameters->{remove_white_space};
    $self->{do_evaluation_in_parsing} = $parameters->{do_evaluation_in_parsing}
     || 0;
    $self->{do_not_compress_eval} = $parameters->{do_not_compress_eval} || 0;
    $self->{separator} = $parameters->{separator} || $self->{separator};
    $self->{not_string} = $parameters->{not_string};
    if (defined $parameters->{parse_forward}) {
      $self->{leaf_parse_forward} = $parameters->{parse_forward};
    }
    if (defined $parameters->{parse_backtrack}) {
      $self->{leaf_parse_backtrack} = $parameters->{parse_backtrack};
    }
    if (defined $parameters->{increasing_value_function}) {
      $self->{increasing_value} = $parameters->{increasing_value_function};
    }
    if (defined $parameters->{display_value_function}) {
      $self->{display_value} = $parameters->{display_value_function};
    }
    if (defined $parameters->{parse_function}) {
      $self->{parse_function} = $parameters->{parse_function};
    }
    $self->set_up_full_rule_set($parameters);
  }
  return $self;
}

sub empty_parse_function {
  return shift;
}

sub parse_and_evaluate {
  my $self = shift;
  my $parameters = shift;
  if (ref $parameters eq '') {
    $parameters = {parse_this => $parameters};
  }
  my $parser = new Parse::Stallion::Parser($self);
  $parser->parse($parameters);
  my $to_return;
  if (!($parser->{results}->{parse_succeeded})) {
    $to_return = undef;
  }
  elsif ($self->{do_evaluation_in_parsing}) {
    $to_return = $parser->{results}->{parsing_evaluation}
  }
  else {
    $to_return = $self->do_tree_evaluation({tree=>$parser->{results}->{tree}});
  }
  if (wantarray) {
    return $to_return, $parser->{results};
  }
  else {
    return $to_return;
  }
}

#package rules
sub eval_sub {
  return ['EVAL', @_];
}

sub E {eval_sub(@_)}
sub EVALUATION {eval_sub(@_)}

sub uneval_sub {
  return ['UNEVAL', @_];
}

sub U {uneval_sub(@_)}
sub UNEVALUATION {uneval_sub(@_)}

sub match_min_first {
  return ['MATCH_MIN_FIRST'];
}

sub MATCH_MIN_FIRST {match_min_first(@_)}

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

sub N {
  return ['LEAF', $_[0]];
}

sub NON_STRING_LEAF {
  return ['LEAF', $_[0]];
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
  return ['LEAF', {regex_match => $p[0]}, @q];
}

sub LEAF {leaf(@_)}
sub L {leaf(@_)}

sub multiple {
  my @p;
  my @q;
  foreach my $parm (@_) {
    if ((ref $parm eq 'ARRAY') &&
     ($parm->[0] eq 'EVAL' || $parm->[0] eq 'UNEVAL'
      || $parm->[0] eq 'MATCH_MIN_FIRST' || $parm->[0] eq 'USE_PARSE_MATCH')) {
      push @q, $parm;
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
  if ($rule_type eq 'MULTIPLE') {
    $rule_counts->{rule_count}->{$subrule_name} = 2;
  }
  elsif ($rule_type eq 'AND') {
    $rule_counts->{rule_count}->{$subrule_name} += $subrule_count;
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
  $self->{rule}->{$rule_name}->{parsing_unevaluation} =
   \&default_unevaluation_routine;
  if (ref $rule eq 'Regexp') {
    $rule = LEAF($rule);
  }
  elsif (ref $rule eq '') {
    $rule = AND($rule);
  }

  my $base_rule = $rule_name;
  if (defined $parameters->{generated_name}) {
    $self->{rule}->{$rule_name}->{generated} = 1;
    $base_rule = $parameters->{generated_name};
  }
  my $default_alias = '';
  my @copy_of_rule; #to prevent changing input
  foreach my $sub_rule (@$rule) {
    if (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'EVAL') {
      $self->{rule}->{$rule_name}->{parsing_evaluation} = $sub_rule->[1];
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'UNEVAL') {
      $self->{rule}->{$rule_name}->{parsing_unevaluation} = $sub_rule->[1];
      $self->{do_evaluation_in_parsing} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'MATCH_MIN_FIRST') {
      $self->{rule}->{$rule_name}->{minimize_children} = 1;
    }
    elsif (ref $sub_rule eq 'ARRAY' && $sub_rule->[0] eq 'USE_PARSE_MATCH') {
      $self->{rule}->{$rule_name}->{use_parse_match} = 1;
    }
    elsif (ref $sub_rule eq 'CODE') {
      $self->{rule}->{$rule_name}->{parsing_evaluation} = $sub_rule;
    }
    else {
      push @copy_of_rule, $sub_rule;
    }
  }
  my $rule_type = $self->{rule}->{$rule_name}->{rule_type} =
   shift @copy_of_rule;
  if ($rule_type eq 'LEAF') {
    $self->{rule}->{$rule_name}->{leaf_info} = shift @copy_of_rule;
    $self->{rule}->{$rule_name}->{use_parse_match} = 1;
  }
  else {
    if ($rule_type eq 'AND') {
      $self->{rule}->{$rule_name}->{minimum_child} = 1;
      $self->{rule}->{$rule_name}->{maximum_child} = 1;
    }
    elsif ($rule_type eq 'OR') {
      $self->{rule}->{$rule_name}->{minimum_child} = 0;
      $self->{rule}->{$rule_name}->{maximum_child} = 1;
    }
    elsif ($rule_type eq 'MULTIPLE') {
      $self->{rule}->{$rule_name}->{minimum_child} = shift @copy_of_rule;
      $self->{rule}->{$rule_name}->{maximum_child} = shift @copy_of_rule;
    }
    else {
      croak "Bad rule type $rule_type\n";
    }
    foreach my $current_rule (@copy_of_rule) {
      my ($alias, $name);
      if (ref $current_rule eq 'HASH') {
        my @hash_info = keys (%{$current_rule});
        if ($#hash_info != 0) {
          croak ("Too many keys in rule of rule $rule_name");
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
        $name = $base_rule.$self->{separator}.
          ++$self->{unique_name_counter}->{$base_rule};
        $self->add_rule({
         rule_name => $name, rule_definition => LEAF($current_rule),
         generated_name => $base_rule});
      }
      elsif (ref $current_rule eq 'ARRAY') {
        $name = $base_rule.$self->{separator}.
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
    }
  }
}

sub set_up_full_rule_set {
  my $self = shift;
  my $parameters = shift;
  my $rules_to_set_up_hash = $parameters->{rules_to_set_up_hash};
  my $start_rule = $parameters->{start_rule};

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
      $to_return{$child_rule_name} = 1;
    }
    else {
      $to_return{$child_rule_name} = 0;
    }
  }
  return \%to_return;
}

sub new_unevaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $node = $parameters->{node};
  my $object = $parameters->{object};
  my $rules_details = $self->{rule};
  my $rule_name = $node->{values}->{name};
  my $subroutine_to_run = $rules_details->{$rule_name}->{parsing_unevaluation};

  &$subroutine_to_run($node->{values}->{parameters}, $object);

  if (my $parent = $node->{parent}) {
    if (defined $node->{values}->{parse_match} &&
     (ref $node->{values}->{parse_match} eq '')) {
      $parent->{values}->{parse_match} = substr($parent->{values}->{parse_match}
       , 0, 0 - length($node->{values}->{parse_match}));
    }

    foreach my $param (keys %{$node->{values}->{passed_params}}) {
      if (my $count = $node->{values}->{passed_params}->{$param}) {
        if ($count > scalar(@{$parent->{values}->{parameters}->{$param}})) {
          croak("Unevaluation parameter miscount; routine in rule $rule_name");
        }
        splice(@{$parent->{values}->{parameters}->{$param}}, - $count);
      }
      else {
        delete $parent->{values}->{parameters}->{$param};
      }
    }
    delete $node->{values}->{passed_params};
  }
}

sub new_evaluate_tree_node {
  my $self = shift;
  my $parameters = shift;
  my $node = $parameters->{node};
  my $object = $parameters->{object};
  my $rules_details = $self->{rule};
  my @results;

  my $rule_name = $node->{values}->{name};
  my $params_to_eval = $node->{values}->{parameters};
  my $subroutine_to_run = $rules_details->{$rule_name}->{parsing_evaluation};

  if ($rules_details->{$rule_name}->{use_parse_match}) {
    $params_to_eval = $node->{values}->{parse_match};
    if ($self->{remove_white_space}) {
      $params_to_eval =~ s/^\s*//s;
      $params_to_eval =~ s/\s*$//s;
    }
  }
  my $alias = $node->{values}->{alias};

  my $cv;
  if ($subroutine_to_run) {
    @results = &$subroutine_to_run($params_to_eval, $object);
    $cv = $node->{values}->{computed_value} = $results[0];
  }
  else {
    $cv = $node->{values}->{computed_value} = $params_to_eval;
  }

  if (my $parent = $node->{parent}) {
    if (defined $node->{values}->{parse_match} &&
     (ref $node->{values}->{parse_match} eq '')) {
      $parent->{values}->{parse_match} .= $node->{values}->{parse_match};
    }
    my $parent_name = $parent->{values}->{name};
  
    if (defined $alias) {
      if ($rules_details->{$parent_name}->{rule_count}->{$alias} > 1) {
        push @{$parent->{values}->{parameters}->{$alias}}, $cv;
        $node->{values}->{passed_params}->{$alias} = 1;
      }
      else {
        $parent->{values}->{parameters}->{$alias} = $cv;
        $node->{values}->{passed_params}->{$alias} = 0;
      }
    }
    else { # !defined alias
      foreach my $key (keys %$cv) {
        if ($rules_details->{$rule_name}->{rule_count}->{$key} > 1) {
          if (scalar(@{$cv->{$key}})) {
            push @{$parent->{values}->{parameters}->{$key}}, @{$cv->{$key}};
            $node->{values}->{passed_params}->{$key} = scalar(@{$cv->{$key}});
          }
        }
        elsif ($rules_details->{$parent_name}->{rule_count}->{$key} > 1) {
          push @{$parent->{values}->{parameters}->{$key}}, $cv->{$key};
          $node->{values}->{passed_params}->{$key} = 1;
        }
        else {
          $parent->{values}->{parameters}->{$key} = $cv->{$key};
          $node->{values}->{passed_params}->{$key} = 0;
        }
      }
    }
  }

  return @results;
}

sub do_tree_evaluation {
  my $self = shift;
  my $parameters = shift;
  my $tree = $parameters->{tree};
  foreach my $node ($tree->bottom_up_depth_first_search) {
    $self->new_evaluate_tree_node({node=>$node});
  }
  return $tree->{values}->{computed_value};
}

1;

__END__

=head1 NAME

Parse::Stallion - Backtracking parser with during or after evaluation

=head1 SYNOPSIS

  use Parse::Stallion;

  my %rules = (rule_name_1 => ..rule_definition..,
   rule_name_2 => ..rule_definition..,
   ...);

  my $stallion = new Parse::Stallion({
    rules_to_set_up_hash => \%rules,
    start_rule => 'rule_name_1', #default is the rule which is not a subrule
    do_evaluation_in_parsing => 0, #default is 0
    remove_white_space => 1, #default is 0
  });

  my $result = $stallion->parse_and_evaluate($given_string);

  my ($value, $parse_info) =
   $stallion->parse_and_evaluate({parse_this => $s, max_steps => 10});

Rule Definitions:

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
Extended Backus-Naur Form.

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

   my $parser = new Parse::Stallion(
   {rules_to_set_up_hash => \%basic_grammar});

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
   {rules_to_set_up_hash => \%grammar_2, start_rule => 'expression'});

   my $result_2 = $parser_2->parse_and_evaluate('8+5');
   #$result_2 should contain 13

=head2 RULES

There are 4 rule types: B<'LEAF'>, B<'AND'>, B<'OR'>, and B<'MULTIPLE'>.

Parsing begins from the 'start_rule', if the 'start_rule' parameter
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

Examples (equivalent):

  LEAF(qr/xx\w+/)

  L(qr/xx\w+/)

  qr/xx\w+/

would match any perl word (\w+) starting with "xx".

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
If the parameter 'MATCH_MIN_FIRST' is passed in, the minimal number of matches
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

=head3 SIMILARITY BETWEEN RULE TYPES.

The following rules all parse tree-wise equivalently.

  AND('subrule')

  O('subrule')

  MULTIPLE('subrule', 1, 1)

  M('subrule', 1, 1, MATCH_MIN_FIRST)

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

Avoid naming rules with the 'separator' substring '__XZ__', to avoid
confliciting with internally generated names.  One can change this by
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

If parse_and_evaluate is called in wantarray context a two value array is
returned.  The first value is the result of the evaluation,
same as if in scalar.  The second value is information on the parse.

  my ($value, $parse_info) =
   $stallion->parse_and_evaluate($given_string);

  $parse_info->{parse_succeeded}; # is 1 if the string parses, else 0.
  $parse_info->{number_of_steps}; # number of steps parsing took
  $parse_info->{start_rule};

  $parse_info->{parse_trace};
  # reference to array of hashes showing each step, the hash keys are
  #  1) rule_name
  #  2) moving_forward (value 0 if backtracking),
  #  3) moving_down (value 0 if moving up parse tree)
  #  4) value (display_value_function of parsed object,
  #     by default the yet unparsed portion of the input string)
  #  5) node_creation_step, uniquely identifies node in parse tree
  #  6) parent_node_creation_step, parent in parse tree
  #  7) informative message of most recent parse step

  $parse_info->{tree}; # the parse tree if the string parses.

The tree is an Parse::Stallion object having a function, that converts a
tree into a string, each node consisting of one line:

  $parse_info->{tree}->stringify({values=>['name','parse_match']});

Internally generated node names, from rules generated by breaking up
the entered rules into subrules, will show up. The module
Parse::Stallion::EBNF shows the grammar with these generated subrules.

=head3 NUMBER OF PARSE STEPS

If the parsing reaches the maximum number of steps without completing a
parse tree, the parse fails.  Each step is listed in the parse_trace.

A step is an action on a node, roughly speaking matching a
regex for a B<'leaf'> node, or moving forward or backtracking from a node.

The maximum number of steps can be changed, default 20,000:

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

=head3 "LEFT RECURSION"

Parse::Stallion may encounter "left recursiveness"
during parsing in which case the parsing stops and a message is 'croak'ed.

"Left recursion" occurs during parsing when the same non-B<'leaf'> rule shows
up a second time on the parse tree with the "same" input string,
measured by the increasing_value_function.

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
When setting up a rule, one can specify the subroutine
by enclosing the subroutine in the parameter 'EVALUATION' or 'E'.

Each node has a computed value that is the result of calling its
evaluation routine.  The returned value of the parse is the
computed value of the root node.

There are two parameters to an evaluation routine. the second is the object
being parsed, which could be undef if evaluation occurs after parsing.

The first parameter is either the string matched by the nodes' descendants
or a hash.
The hash keys are the named subrules of the node's rule, the values are the
computed value of the corresponding child node.  If a key could repeat,
the value is an array reference.

For B<'leaf'> nodes, the parameter is the string matched and cannot
be a hash, there are no children.  For non-B<'leaf'>
nodes by default the parameter is the hash, this can be changed by
passing in 'USE_PARSE_MATCH' when creating the rule.

The beginning and trailing white space can be removed before being passed
to a B<'leaf'> or USE_PARSE_MATCH node's routine by setting the parameter
remove_white_space when creating the parser:

  $parser = new Parse::Stallion({remove_white_space => 1});

By nesting a rule with an alias, the alias is used for the name of the
hash parameter instead of the rule name.

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
   start_rule => A('term',
    M(A({plus=>qr/\s*\+\s*/}, 'term'))),
   term => A({left=>'number'},
    M(A({times=>qr/\s*\*\s*/},
     {right=>'number'}))),
   number => qr/\s*\d*\s*/
  );                               
                      
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

=head3 Parameter types to Evaluation Routines

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
    plus_or_minus => qr/\s*[\-+]\s*/,
    times_or_divide => qr/\s*[*\/]\s*/
   );

   $calculator_parser = new Parse::Stallion({
     rules_to_set_up_hash => \%calculator_rules,
     start_rule => 'start_expression'
   });

   my $result = $calculator_parser->parse_and_evaluate("3+7*4");
   # $result should contain 31

  my $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'term'});
  # $array_p would be {number => 1, times_or_divide => 1}

  $array_p = $calculator_parser->which_parameters_are_arrays({
    rule_name => 'start_expression'});
  # $array_p would be {expression => 0}

=head2 PARSING NON-STRINGS

In order to parse non-strings, use NON_LEAF_STRING (or N)
instead of LEAF (or L) for defining the leaves.

Four subroutines should be provided: an increasing_value function for ensuring
parsing is proceeding correctly, a B<'leaf'>
rule matcher/modifier for when the parser is moving forward,
a B<'leaf'> rule unmodifier for when the parser is backtracking,
an increasing_value_function to prevent "left recursion",
and a display_value function for the parse_trace.

Parsing is completed only if the object being parsed becomes undefined or
equal to ''.  The latter is the condition that parsing strings must match.

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

When evaluating the parse tree, the parameters to the B<'leaf'> nodes are
the values returned in parse_forward, $value_to_store_in_leaf_node.
These values are joined together for parse_match.

The script object_string.pl in the example directory shows how to use this.

=head3 B<'LEAF'> LEAF PARSE FORWARD/BACKTRACK

All B<'leaf'> rules need to be set up such that when the parser is moving
forward and reaches a B<'leaf'>, the
B<'leaf'> rule attempts to match the current input object.
If there is a match, then the input object is modified
to the object's next state and a value is stored to be called upon
later during tree evaluation.

When backtracking, the object being parsed should be reverted to
the state before being matched by the B<'leaf'> rule.

In parsing a string, substrings are removed from the beginning of the
string and reattached to the beginning when backtracked.

=head3 INCREASING_VALUE FUNCTION

A function, called 'increasing_value', must be provided that takes the object
being parsed and returns a numeric value that either is unchanged or
increases after the B<'leaf'> rule's match_and_modify_input_object is called.

This function is used to detect and prevent "left recursion" by not
allowing a non-B<'leaf'> rule to repeat at the same value.
B<'Multiple'> rules are prevented from repeating more than once at
the same value.

The function also cuts down on the number of steps by allowing the parser to
not repeat dead-end parses.  If during the parse, the same rule is
attempted a second time on the parse object with the same increasing_value,
and the first parse did not succeed, the parser will beging backtracking.

In parsing a string, the negative of the length of the input string is used
as the increasing function.

=head3 STRINGS

By default, strings are matched, which is similar to

  my $calculator_stallion = new Parse::Stallion({
    ...
    parse_forward =>
     sub {
      my $input_string_ref = shift;
      my $rule_definition = shift;
      my $m = $rule_definition->{regex_match}; #regex_match eq regexp of leaf
      if ($$input_string_ref =~ s/\A$m//) {
        return (1, $&);
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

=head2 EXPORT

The following are EXPORTED from this module:

A AND O OR LEAF L M MULTIPLE NON_STRING_LEAF N OPTIONAL ZERO_OR_ONE Z
E EVALUATION U UNEVALUATION MATCH_MIN_FIRST USE_PARSE_MATCH

=head1 PERL Requirements

Parse::Stallion's installation uses Test::More and Time::Local
requiring perl 5.6 or higher.
Parse::Stallion should work with earlier versions of perl, neither
of those modules is required outside of the test cases for installation.

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

Parsing texts, including references to Extended Backus-Naur Form notation.

Parse::Stallion::CSV, Parse::Stallion::CSVFH, Parse::Stallion::EBNF.

Perl 6 grammars.

lex, yacc, ..., other parsers.

=cut
