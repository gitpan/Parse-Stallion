#Copyright 2009 Arthur S Goldstein

# Since there are other features one can implement, most debugging code
# has been left in.

package Parse::Stallion::RD::Thisline;
use Parse::Stallion;
require Tie::Scalar;
our @ISA = (Tie::StdScalar);
sub FETCH {
  my ($loc) = LOCATION($Parse::Stallion::RD::__parse_this_ref,
   $Parse::Stallion::RD::__previous_position);
  return $loc;
}

package Parse::Stallion::RD::Text;
use Parse::Stallion;
require Tie::Scalar;
our @ISA = (Tie::StdScalar);
sub FETCH {
  my $ptr = $Parse::Stallion::RD::__parse_this_ref;
  my $to_return = substr($$ptr, $Parse::Stallion::RD::__previous_position);
  return $to_return;
}
sub STORE {
  my $self = shift;
  my $store = shift;
  substr(${$Parse::Stallion::RD::__parse_this_ref},
   $Parse::Stallion::RD::__previous_position) = $store;
}

package Parse::Stallion::RD;
# Read in grammars similar to those used for Parse::RecDescent
use Carp;
use strict;
use warnings;
use Parse::Stallion;
use Text::Balanced qw (extract_codeblock);
our $VERSION='0.35';
our $skip = qr/\s*/;
our $__default_skip;
our @arg;
our %arg;
our $commit;
our @__skip;
our $__thisparser;
our $__error_message;
our @__delay;
our $__trace;
our $__rule_has_commit;
our $__rule_has_error;
our $__previous_position;
our $__parse_this_ref;
our $__max_steps;
our $__rule_info;
our $__current_package_number = 0;
our $__current_package_name;
our $__sub_count = 0;
our @__package_list;
our $__package_text;
our %__package_temp_names;
our %__package_subs;
our @__package_sub_names;
tie our $thisline, "Parse::Stallion::RD::Thisline";
tie our $text, "Parse::Stallion::RD::Text";

sub compute_node_value {
  my $node_with_value = shift;
  my $item_value = $node_with_value->{parse_match};
  if (defined $item_value) {return $item_value}
  my $item_type =
   $__rule_info->{$node_with_value->{name}}->{rule_type} || "";
  if ($item_type eq "straight") {
    $item_value = [];
    if ($node_with_value->{child_count}) {
      foreach my $node_child (@{$node_with_value->{children}}) {
        push @{$item_value}, $node_child->{parse_match};
      }
    }
  }
  elsif ($item_type eq "straight_separator" ||
   $item_type eq "leftop_two") {
    $item_value = [$node_with_value->{children}->[0]->{parse_match}];
    my $other_children = $node_with_value->{children}->[1];
    foreach my $child (@{$other_children->{children}}) {
      push @$item_value,
       $child->{children}->[1]->{parse_match};
    }
  }
  elsif ($item_type eq "leftop_one") {
    $item_value = [$node_with_value->{children}->[0]->{parse_match}];
    my $other_children = $node_with_value->{children}->[1];
    foreach my $other_child (@{$other_children->{children}}) {
      push @$item_value, $other_child->{children}->[0]->{parse_match};
      push @$item_value, $other_child->{children}->[1]->{parse_match};
    }
  }
  elsif ($item_type eq "rightop_one") {
    my $other_children = $node_with_value->{children}->[0];
    foreach my $other_child (@{$other_children->{children}}) {
      push @$item_value, $other_child->{children}->[0]->{parse_match};
      push @$item_value, $other_child->{children}->[1]->{parse_match};
    }
    push @$item_value,
     $node_with_value->{children}->[1]->{parse_match};
  }
  elsif ($item_type eq "rightop_two") {
    my $other_children = $node_with_value->{children}->[0];
    foreach my $other_child (@{$other_children->{children}}) {
      push @$item_value, $other_child->{children}->[0]->{parse_match};
    }
    push @$item_value,
     $node_with_value->{children}->[1]->{parse_match};
  }
  elsif ($item_type eq "straight_z_separator") {
    my $z_node = $node_with_value->{children}->[0];
    if ($z_node) {
      $item_value = [];
      push @$item_value, $z_node->{children}->[0]->{parse_match};
      foreach my $child (@{$z_node->{children}}) {
        push @$item_value,
         $child->{children}->[1]->{parse_match};
      }
    }
  }
  $node_with_value->{parse_match} = $item_value;
  return $item_value;
}

sub mctr {
  my $code = shift;
  my $__current_rule = shift;
#  my $safe_code = $code;
#  $safe_code =~ s/\'//g;
#  $safe_code =~ s/\"//g;
#  $safe_code =~ s/\$//g;
  my $sub_text = "
    sub sub".$__sub_count.' {
#delete $_[0]->{parser};use Data::Dumper;print  "actode in ".Dumper(\@_)."\n";
          my $in = $_[0]->{parent_node};
          my $__current_position = $_[0]->{current_position};
          my $return;
          my $__updated_position;
          $__previous_position = $in->{position_when_entered};
          my $thisparser = $__thisparser; #?
          $__parse_this_ref = $_[0]->{parse_this_ref};
          my $child_number = 1;
          my @item = ("'.$__current_rule.'");
          my %item = (__RULE__ => "'.$__current_rule.'");
          while ($child_number <= $#{$in->{children}}) {
            my $node_with_value = $in->{children}->[$child_number];
            my $item_name = $node_with_value->{alias} ||
             $__rule_info->{$node_with_value->{name}}->{rd_name} || "";
            my $item_value = Parse::Stallion::RD::compute_node_value($node_with_value);
            $child_number++;
            if ($item_name ne "") {
              push @item, $item_value;
              $item{$item_name} = $item_value;
            }
          }
#use Data::Dumper;print "item is ".Dumper(\@item)."\n";
          my $match = do {'.  $code.'};
          if (defined $return) {$match = $return};
          if (!defined $match) {
            return 0;
          }
          if (defined $__updated_position) {
            return 1, $match, $__updated_position;
          }
          return 1, $match;}';
#print "subtext is $sub_text\n";
       push @__package_list, $sub_text;
       sub k{my $t; return sub {$t}}; #force perl to generate different subs
       my $return_sub = k;
#print "return sub is $return_sub\n";
       $__package_temp_names{$return_sub} = 
        $__current_package_name.'::sub'.$__sub_count;
#       eval $sub_text;
#    if ($@) {print "err $@";croak  "Error is $@\n"};
#       my $mcsub;
#        eval "\$mcsub = \\\&{".$__current_package_name.'::sub'.$__sub_count."}";
#    if ($@) {print "krr $@";croak  "Error is $@\n"};
    $__sub_count++;
#    my $i = $__mct; #comment out this line and parse test fails.
#    $i = '';
#print "mct $__mct Error is $@\n";
  return $return_sub;
}

my $move_to_parent = L(PF(
 sub {
   my $parameters = shift;
#use Data::Dumper; print "mtp params ".Dumper($parameters)."\n";
   my $parent_node = $parameters->{parent_node};
   my $previous_node_count = $parent_node->{child_count} - 1;
   my $previous_node = $parent_node->{children}->[$previous_node_count];
   my $value = compute_node_value($previous_node);
   $parent_node->{parse_match} = $value;
   return 1;
  }), LEAF_DISPLAY('move to parent')
);
our $__counts = [];
our $__current_rule_count = 0;
#print  "set orig\n";
#print  "done set orig\n";

my $__start_rule = L(PF(
  sub {
    my $parameters = shift;
    $parameters->{parent_node}->{previous_commit} = $commit;
    unshift @__skip, $skip = $__default_skip;
    $commit = 0;
    return 1;
  }),
   PB( sub {
    my $parent = $_[0]->{parent_node};
    pop @__skip;
    $skip = $__skip[0];
#use Data::Dumper;print "in sr pn e ".Dumper($parent->{error_messages})."\n";
    $commit = $parent->{previous_commit};
    if ($parent->{error_messages} && !($parent->{completed})) {
      $__error_message .= join("\n", @{$parent->{error_messages}})."\n";
    }
    return 0;
   }
 ), LEAF_DISPLAY('start rule'));

my $__end_rule = L(PB(
  sub {
    my $parent = $_[0]->{parent_node};
#    my $parent = $current_node->{parent};
    unshift @__skip, $skip = $parent->{skip};
    $commit = $parent->{commit_on_exit};
    return 0;
  }),
   PF( sub {
#delete $_[0]->{parser};use Data::Dumper;print "end rule args ".Dumper(\@_)."\n";
    my $parent_node = $_[0]->{parent_node};
    $parent_node->{commit_on_exit} = $commit;
    $parent_node->{completed} = 1;
    $commit = $parent_node->{previous_commit};
    my $parent_last_child = $parent_node->{child_count}-1;
    my $previous_node = $parent_node->{children}->[$parent_last_child];
    my $previous_last_child = $previous_node->{child_count}-1;
    my $pre_previous_node = $previous_node->{children}->[$previous_last_child];
    my $last_previous_node_count = $pre_previous_node->{child_count}-1;
    my $last_previous_node =
     $pre_previous_node->{children}->[$last_previous_node_count];
    my $value = compute_node_value($last_previous_node);
    $parent_node->{parse_match} = $value;
    $parent_node->{skip} = shift @__skip;
    $skip = $__skip[0];
    return 1;
   }
 ), LEAF_DISPLAY('end rule'));

my $__check_commit = L(PF(
  sub {
#print "checking commit which is $commit\n";
    if ($commit) {return 0;}
    return 1;
  }
), LEAF_DISPLAY('check commit'));

sub __rule_def {
return $_[0]->{the_productions}->{''};}
sub __xrule_def {
return $_[0]->{x};}
my $__current_rule;
my $__look_ahead_count=0;
our $any_deferred;
our @other_rules;
my %rd_rules = (
   rd_rule_list => A(M(O(qr/\s*/,'comment')),
    'initial_actions',
    M(A('rule',A(M(O(qr/\s*/,'comment'))))),
    E(sub {return $_[0]->{rule};})),
   rule =>
    A('set_rule_name', qr/\s*\:\s*/, 'rule_def', qr/\s*\n/,
     E(sub {
         return {rule_name => $_[0]->{set_rule_name},
          rule_definition => $_[0]->{rule_def}};})),
   rule_def => A('production', M(A(qr/\s*\|\s*/, 'production')),
      E(sub {my $in = shift; return $in->{production};}
     )),
   comment => qr/\s*\#.*?\n/,
   set_counts => L(PF(sub {return 1;}),
    E(sub {unshift @$__counts, {}})),
   production => A('set_counts', 'item', M(A(qr/\s\s*/, 'item')),
    E(sub {my $in = shift;
#use Data::Dumper; print "production in shift reveals ".Dumper($in);
        return $in->{item};
      })),
   reject => O(qr/\<reject\>/, A(qr/\<reject:\s*/, 'def_perl_code'),
     E( sub {
       my $condition = $_[0]->{def_perl_code};
       my $code;
       if ($condition) {
         $condition =~ s/^.//;
         $condition =~ s/.$//;
         $code = "($condition)?undef:1";
       }
       else {
         $code = 'undef';
       }
       my $sub = mctr($code, $__current_rule);
       my $count = ++$__counts->[0]->{directive}->{$__current_rule};
       my $latest_name = '__DIRECTIVE'.$count.'__';
#print "error is $@\n";
#print "ln $latest_name sub is $sub\n";
       my $dcode = $_[0]->{def_perl_code} || '';
       return {name => $latest_name, operation => {$latest_name => L(PF($sub),
        LEAF_DISPLAY('reject '.$dcode)
         ,RULE_INFO({rule_type => 'reject'})
       )}};
      }
   )),
   commit => A( qr/\<commit\>/,
    E(sub {
        my $count = ++$__counts->[0]->{directives}->{$__current_rule};
        my $latest_name = '__DIRECTIVE'.$count.'__';
        $__rule_has_commit->{$__current_rule} = 1;
        my $sub = sub {$commit = 1; return 1;};
        return {name => $latest_name, operation => {$latest_name => L(PF($sub)
         ,RULE_INFO({rule_type => 'commit'})
         ,LEAF_DISPLAY('commit'))}};
         }
    )),
   uncommit => A( qr/\<uncommit\>/,
    E(sub {
        my $count = ++$__counts->[0]->{directives}->{$__current_rule};
        my $latest_name = '__DIRECTIVE'.$count.'__';
        my $sub = sub { $commit = 0; return 1;};
        return {name => $latest_name, operation => {$latest_name => L(PF($sub)
         ,RULE_INFO({rule_type => 'uncommit'})
         ,LEAF_DISPLAY('uncommit'))}};
         }
    )),
   leftop => A(
     qr/\<leftop\:\s*/, 
    {item1=>'item'},
    qr/\s*/,
    {item2=>'item'},
    qr/\s*/,
    {item3=>'item'},
    qr/\s*\>/,
    ,E(sub {
      my $parameters = shift;
      my $secondary = shift;
      my $item1 = $parameters->{item1};
      my $item2 = $parameters->{item2};
      my $item3 = $parameters->{item3};
      my $count = ++$__counts->[0]->{directives}->{$__current_rule};
      my $latest_name = '__DIRECTIVE'.$count.'__';
      my $nv;
      my $val;
#print "cr $__current_rule litem 2 type is ".$item2->{item_type}."\n";
      if ($item2->{item_type} eq 'mtoken' ||
       $item2->{item_type} eq 'token' ||
       $item2->{item_type} eq 'subrule' ||
       $item2->{item_type} eq 'rule_name') {
        $val = {$latest_name => A($item1->{operation},
         M(A($item2->{operation},
         $item3->{operation} ))
         ,RULE_INFO({rule_type => 'leftop_one'})
         , MATCH_ONCE()
         )};
      }
      else {
        $val = {$latest_name => A($item1->{operation},
         M(A($item2->{operation},
         $item3->{operation}))
         ,RULE_INFO({rule_type => 'leftop_two'})
         , MATCH_ONCE())};
      }
#use Data::Dumper;print "leftope valpar ".Dumper($parameters)."\n";
#print "nv is ".Dumper($nv)."\n";
      return {name => $latest_name, operation => $val};
     })
     ),
   rightop => A( qr/\<rightop\:\s*/, 
    {item1=>'item'},
    qr/\s*/,
    {item2=>'item'},
    qr/\s*/,
    {item3=>'item'},
    qr/\s*\>/,
    ,E(sub {
      my $parameters = shift;
      my $secondary = shift;
      my $item1 = $parameters->{item1};
      my $item2 = $parameters->{item2};
      my $item3 = $parameters->{item3};
       my $count = ++$__counts->[0]->{directives}->{$__current_rule};
       my $latest_name = '__DIRECTIVE'.$count.'__';
      my $nv;
      my $val;
#print "item 2 type is ".$item2->{item_type}."\n";
      my $rule_type;
      if ($item2->{item_type} eq 'mtoken' ||
       $item2->{item_type} eq 'token' ||
       $item2->{item_type} eq 'subrule' ||
       $item2->{item_type} eq 'rule_name') {
        $rule_type = 'rightop_one';
      }
      else {
        $rule_type = 'rightop_two';
       }
      $val = {$latest_name => A(M(A($item1->{operation},
       $item2->{operation})), $item3->{operation}
       ,RULE_INFO({rule_type => $rule_type})
      , MATCH_ONCE())};
#use Data::Dumper;print "rightope valpar ".Dumper($parameters)."\n";
#print "nv is ".Dumper($nv)."\n";
      return {name => $latest_name, operation => $val};
     })
     ),
   defer => A(qr/\<defer\:\s*/, 'def_perl_code',
    E( sub { my $parameters = shift;
      $any_deferred = 1;
      my $code = $parameters->{def_perl_code};
      $code =~ s/^.//;
      $code =~ s/.$//;
      my $count = ++$__counts->[0]->{directives}->{$__current_rule};
      my $latest_name = '__DIRECTIVE'.$count.'__';
      my $cr = $__current_rule;
      my $sub = mctr($code, $cr);
      push @__package_sub_names, $sub;
      my $leaf = {$latest_name => L(PF(sub {
#use Data::Dumper;print "defer params are ".Dumper(\@_);
        my $parent_node = $_[0]->{parent_node};
        my $stored_params = {current_position => $_[0]->{current_position},
         parent_node => $parent_node,
         parse_this_ref => $_[0]->{parse_this_ref}};
#print "storing for sub $sub\n";
        push @__delay, {sub => $__package_subs{$sub},
          parameters => $stored_params};
         return 1, scalar(@__delay);}
        ),
        PB(sub {
           pop @__delay;
           return 0;
         }
       )
       ,LEAF_DISPLAY('defer '.$code)
         ,RULE_INFO({rule_type => 'deferred action'})
      )};
      return {name => $latest_name, operation => $leaf };
    })),
   def_perl_code => L(PF(
    sub { my $parameters = shift;
       my $in_ref = $parameters->{parse_this_ref};
       my $pos = $parameters->{current_position};
       my $find_code = substr($$in_ref, $pos);
       if (my $code = Text::Balanced::extract_codeblock('<'.$find_code,'<>')) {
         return 1, $code, $pos + length($code) - 1;
       }
       return 0;
      })),
   initial_actions => M(A({actions => L(PF(
    sub {my $parameters = shift;
      my $in_ref = $parameters->{parse_this_ref};
      my $pos = $parameters->{current_position};
      if (substr($$in_ref, $pos, 1) eq '{') { # '}'
        my $find_code = substr($$in_ref, $pos);
        if (my $code = Text::Balanced::extract_codeblock($find_code)) {
          return 1, $code, $pos + length($code);
        }
      }
      return 0;
    }))}, qr/\s*/),
     E( sub {
       my $actions = $_[0]->{actions};
       my $the_code;
       foreach my $code (@$actions) {
         $code =~ s/^\s*.//;
         $code =~ s/.\s*$//;
         $the_code .= $code.";\n";
       }
       if ($the_code) {
          $__package_text .= "$the_code\n\n";
#         my $np = "package $__current_package_name;
#              $the_code";
#print "np is $np\n";
#          eval $np;
#         my $sub = $init1a.$the_code.$init2;
#         $sub = $the_code.';'.$init1a.$init2;
#print "iasub is $sub\n";
#         my $ns = eval $sub;
#print "mct is $__mct\n";
#         $__mct = &{$ns}();
#print "mct now is $__mct\n";
       }
     })),
   action => L(PF(
    sub {my $parameters = shift;
      my $in_ref = $parameters->{parse_this_ref};
      my $pos = $parameters->{current_position};
      if (substr($$in_ref, $pos, 1) eq '{') { # '}'
        my $find_code = substr($$in_ref, $pos);
        if (my $code = Text::Balanced::extract_codeblock($find_code)) {
          return 1, $code, $pos + length($code);
        }
      }
      return 0;
    }),
     E( sub {
       my $code = shift;
       my $sub = mctr($code, $__current_rule);
       my $count = ++$__counts->[0]->{actions}->{$__current_rule};
       my $latest_name = '__ACTION'.$count.'__';
#print "error is $@\n";
#print "ln $latest_name sub is $sub\n";
       return {name => $latest_name, operation => {$latest_name => L(PF($sub),
          PB(sub {shift; my $parameters = shift;
           $parameters->{parentt_node}->{parse_match} = undef}),
         ,RULE_INFO({rule_type => 'action'})
        ,LEAF_DISPLAY("$latest_name: $code"))}};
     })),
   subrule => A(qr/\(\s*/, 'rule_def', qr/\s*\)/,
    E( sub {
      my $new_rule = $__current_rule.':'.$__current_rule_count++;
#use Data::Dumper;print "new rule $new_rule def is ".Dumper($_[0]->{rule_def})."\n";
        push @other_rules,
         {rule_name => $new_rule,
          rule_definition => $_[0]->{rule_def}
         };
         return {name => $new_rule, operation => $new_rule}
       })),
   item => A({the_item=>O('token', 'rule_name', 'mtoken', 'dquoted_string',
      'squoted_string', 'action', 'look_ahead', 'leftop', 'rightop',
      'skip',
      'subrule', 'reject', 'commit', 'uncommit', 'error', 'defer')},
     Z('repetition'),
    E(sub {my $in = shift;
#use Data::Dumper;print "iteminis ".Dumper($in)."\n";
       my %to_return;
       my ($item) = keys %{$in->{the_item}};
       $to_return{name} = $in->{the_item}->{$item}->{name};
       $to_return{error_text} = $in->{the_item}->{$item}->{error_text};
       $to_return{item_type} = $item;
       my $operation = $in->{the_item}->{$item}->{operation};
       if (defined $in->{repetition}) {
         $to_return{name} .= $in->{repetition}->{name_extra};
         $to_return{item_type} = 'leftop';
         my $up_from = $in->{repetition}->{cardinality}->{low} || 0;
         my $up_to = $in->{repetition}->{cardinality}->{high} || 0;
         if (my $separator = $in->{repetition}->{separator}) {
           if ($up_to) {
             $up_to--;
           }
           if ($up_from) {
             $to_return{operation} = {$to_return{name} => A($operation,
              M(A($separator->{operation}, $operation),
              $up_from-1, $up_to)
              ,RULE_INFO({ rule_type => 'straight_separator'})
             , MATCH_ONCE())};
           }
           else {
             $to_return{operation} = {$to_return{name} => Z(A($operation,
              M(A($separator->{operation}, $operation),
              0, $up_to))
              ,RULE_INFO({rule_type => 'straight_z_separator'})
             , MATCH_ONCE())};
           }
          }
         else {
#print "has repetition ptgp\n";
           $to_return{operation} = {$to_return{name} => 
            M($operation, $up_from, $up_to
              ,RULE_INFO({rule_type => 'straight'})
             , MATCH_ONCE())};
         }
       }
       else {
         $to_return{operation} = $operation;
       }
#use Data::Dumper;print "item $item itemin is ".Dumper($in)."\n";
#use Data::Dumper;print "toreturning ".Dumper(\%to_return)."\n";
       return \%to_return;
      })),
   look_ahead => A(qr/\.\.\./, Z({not=>qr/\!/}), 'item',
    E(sub {
#use Data::Dumper;print "lookahed e val parms are ".Dumper(\@_)."\n";
       my $item = $_[0]->{item};
       my $new_rule;
       if (ref $item->{operation} eq '') {
         $new_rule = $item->{operation};
       }
       else {
         $new_rule = $__current_rule.':'.$__current_rule_count++;
         push @other_rules,
          {rule_name => $new_rule,
           rule_definition => [[$item]]
          };
       }
#print "name set up is $new_rule\n";
#use Data::Dumper;print "other rules now ".Dumper(\@other_rules)."\n";
       my $la_sub;
       if ($_[0]->{not}) {
          $la_sub = sub {
#use Data::Dumper;print "la parms (not) are ".Dumper(\@_)."\n";
          my $current_position = $_[0]->{current_position};
#print "new rule of la is $new_rule p $parser rt is $remaining_text\n";
          my $pi = {};
#use Data::Dumper;print Dumper($__thisparser);exit;
          my $result = $_[0]->{the_parser}->parse_and_evaluate(
           undef,
           {start_rule=> $new_rule, parse_info => $pi,
            max_steps => $__max_steps || 1000000,
            parse_this_ref => $_[0]->{parse_this_ref},
            parse_hash => $_[0],
            start_position => $current_position});
#use Data::Dumper;print "pi is ".Dumper($pi)."\n";
          if ($pi->{parse_succeeded}) {
            return 0;
          }
          else {
            return 1, $pi->{tree}->{parse_match};
          }
         };
       }
       else {
          $la_sub = sub {
          my $ref = $_[0]->{parse_this_ref};
          my $current_position = $_[0]->{current_position};
#use Data::Dumper;print "la parms (not) are ".Dumper(\@_)."\n";
#          my $parser = $_[0]->{parser};
          my $pi = {};
          my $result = $_[0]->{the_parser}->parse_and_evaluate(
           undef,
           {start_rule=> $new_rule, parse_info => $pi,
            max_steps => $__max_steps || 1000000,
            parse_hash => $_[0],
            parse_this_ref => $_[0]->{parse_this_ref},
            start_position => $current_position});
#use Data::Dumper;print "pinow is ".Dumper($pi)."\n";
          if ($pi->{parse_succeeded}) {
            return 1, $pi->{tree}->{parse_match};
          }
          else {
            return 0;
          }
         };
       }
       return {name => $item->{name}, operation => {$item->{name} => L(
           PF($la_sub),
        LEAF_DISPLAY('look ahead on:'.$item->{name})
              ,RULE_INFO({ rule_type => 'look_ahead'})
          )}};
     }
   )),
   skip => L(qr/(\<skip:([^<>]*)?\>)/, E( sub {
      my $skip_string = shift;
      $skip_string =~ qr/(\<skip:([^<>]*)?\>)/;
      my $the_skip = $2;
      my $count = ++$__counts->[0]->{directives}->{$__current_rule};
      my $latest_name = '__DIRECTIVE'.$count.'__';
      my $code = 'my $to_match = '.$the_skip.';
         my $previous = $__skip[0];
         $skip = qr/$to_match/;
         $__skip[0] = $skip;
         pos $$__parse_this_ref = $__current_position;
         $$__parse_this_ref =~ /\G$skip/cg;
         $__updated_position = pos $$__parse_this_ref;
         $previous;
      ';
       my $sub = mctr($code, $__current_rule);
        my $subb = sub {
#           my $current_node = $_[0]->{current_node};
           my $parse_match = $_[0]->{parse_match};
           $__skip[0] = $parse_match;
           $skip = $parse_match;
#print "skip nnow $skip\n";
           return;
         };
       return {name => $latest_name, operation => {$latest_name =>
          L(PF($sub),PB($subb),
              ,RULE_INFO({rule_type => 'skip directive'}),
        LEAF_DISPLAY("skip to be $the_skip"))}};
   })),
   error => L(qr/(\<error(\?)?(:[^<>]*)?\>)/, E( sub {
     my $error_string = shift;
     my $parameters = shift;
     $error_string =~ /\<error(\?)?(:\s*([^<>]*))?\>/;
     my $only_on_commit = $1;
     my $message = $3;
     my $the_rule = $__current_rule;
     $__rule_has_error->{$__current_rule} = 1;
     my $the_message = $message || '';
     return {name => 'error', operation => {'error' => L(PF(
       sub {
         my $parameters = shift;
         my $parent_node = $parameters->{parent_node};
         my $grand_parent = $parent_node->{parent};
         my $great_grand_parent = $grand_parent->{parent};
         if ($only_on_commit && !$commit) {
           return 1;
         }
         my $error_message;
         $__parse_this_ref = $parameters->{parse_this_ref};
         $__previous_position = $parameters->{current_position}; #sets $thisline
         my $error_start .=
          "       ERROR (line $thisline): ";
         $error_message .=
          "       ERROR (line $thisline): Invalid $the_rule: Was expecting ";
         if (defined $grand_parent->{first_max}) {
           $error_message .= $grand_parent->{first_max};
           my $fat = $grand_parent->{first_max_at};
           my $remaining_text = substr(${$parameters->{parse_this_ref}}, $fat);
           $remaining_text =~ s/^$skip//;
           if (length($remaining_text) > 0) {
             $error_message .= " but found \"$remaining_text\" instead";
           }
           else {
             $error_message .= " not found";
           }
         }
         else {
           my @productions = @{$grand_parent->{productions}};
           pop @productions;
           $error_message .= join (", or ",@productions);
         }
         if ($message) {
#print "using $error_start and $message\n";
           unshift @{$great_grand_parent->{error_messages}}, $error_start.$message;
         }
         else {
#print "using $error_message only \n";
           unshift @{$great_grand_parent->{error_messages}}, $error_message;
         }
       return 0;
    })
              ,RULE_INFO({rule_type => 'error directive'})
     , LEAF_DISPLAY("error $the_message"))}};
   })),
   set_rule_name => A('rule_name', E(sub {
     $__current_rule = $_[0]->{rule_name}->{name};
     return $__current_rule;
    })),
   rule_name => L(qr/\w+/,
     E(sub {
#use Data::Dumper;print "rulnam ".Dumper(\@_);
       my $rule_name = $_[0];
       return {name => $_[0], operation => {$_[0] => $_[0]}};
       })),
   mtoken => O(qr/m(\([^()]*\))/, qr/m(\{[^{}]*\})/,
    E(sub {my $token = $_[0]->{''};
#use Data::Dumper;print "got mttok ".Dumper($token)."\n";
      my $count = ++$__counts->[0]->{patterns}->{$__current_rule};
      my $latest_name = '__PATTERN'.$count.'__';
      my $et = $token;
      substr($token, 1, 0) = '\G';
      my $regex = eval 'qr'.$token;
      if ($@) {print "regex is $@"};
       my $sub = sub {
          my $current_position = $_[0]->{current_position};
          my $inref = $_[0]->{parse_this_ref};
          pos $$inref = $current_position;
          if ($$inref =~ /($regex)/cg) {
            my $to_match = $1;
#print "to match is $to_match\n";
            $$inref =~ /\G$skip/cg;
            return 1, $to_match, pos $$inref;
          }
#print "did not match on $regex at ".$_[0]->{current_position}."\n";
          return 0;
        };
      return {name => $latest_name,
        operation => {$latest_name => L(PF($sub),LEAF_DISPLAY($et)
              ,RULE_INFO({rule_type => 'mtoken'}))}
        ,error_text => $et};
       })),
   token => L(qr{\G\s*(/(\\\\/|[^/])*/([cgimsox]*))},
    E(sub {my $token = shift;
#print "got t $token\n";
      my $count = ++$__counts->[0]->{patterns}->{$__current_rule};
      my $latest_name = '__PATTERN'.$count.'__';
      my $et = $token;
      substr($token, 1, 0) = '\G';
      my $regex = eval 'qr'.$token;
      if ($@) {print "ReGex is $@"};
       my $sub = sub {
          my $current_position = $_[0]->{current_position};
          my $inref = $_[0]->{parse_this_ref};
          pos $$inref = $current_position;
          if ($$inref =~ /($regex)/cg) {
            my $to_match = $1;
#print "tto match is $to_match\n";
            $$inref =~ /\G$skip/cg;
            return 1, $to_match, pos $$inref;
          }
#print "tdid not match on $regex at ".$_[0]->{current_position}."\n";
          return 0;
        };
      return {name => $latest_name,
        operation => {$latest_name => L(PF($sub),LEAF_DISPLAY($et)
              ,RULE_INFO({rule_type => 'token'}))}
        ,error_text => $et};
       })),
   dquoted_string => L(qr/\"[^"]*\"/,
     E( sub {
#use Data::Dumper;print "dqparamas are ".Dumper(\@_)."\n";
       my $qs = shift;
       my $code = '
          my $to_match = '.$qs.';
          my $l = length($to_match);
          my $result;
          if (substr($$__parse_this_ref, $__current_position, $l)
           eq $to_match) {
             pos $$__parse_this_ref = $__current_position + $l;
             $$__parse_this_ref =~ /\G$skip/cg;
             $__updated_position = pos $$__parse_this_ref;
             $result = $to_match;
          }
          $result;
       ';
       my $sub = mctr($code, $__current_rule);
       my $count = ++$__counts->[0]->{strings}->{$__current_rule};
       my $latest_name = '__STRING'.$count.'__';
#print  "dqerror is $@\n";
#print  "ln $latest_name sub is $sub\n";
       return {name => $latest_name,
        operation => {$latest_name => L(PF($sub),LEAF_DISPLAY('"'.$qs.'"')
              ,RULE_INFO({rule_type => 'dquote'}))}
        ,error_text => '"'.$qs.'"'};
     })),
   squoted_string => L(qr/\'[^']*\'/,
     E( sub {
#use Data::Dumper;print "sqparamas are ".Dumper(\@_)."\n";
       my $qs = shift;
       my $to_match = substr($qs, 1, -1);
       my $l = length($to_match);
#       my $rule_name = $__current_rule;
       my $sub = sub {
#delete $_[0]->{parser};use Data::Dumper;print "sqtode in ".Dumper(\@_)."\n";
          my $current_position = $_[0]->{current_position};
          my $inref = $_[0]->{parse_this_ref};
          if (substr($$inref, $current_position, $l)
           eq $to_match) {
#print  "returning matching of $to_match\n";
             pos $$inref = $current_position + $l;
#print "sqskip now $skip\n";
             $$inref =~ /\G$skip/cg;
             return 1, $to_match, pos $$inref;
          }
#print  "returning no match\n";
          return 0;
        };
       my $count = ++$__counts->[0]->{strings}->{$__current_rule};
       my $latest_name = '__STRING'.$count.'__';
#print  "sqerror is $@\n";
#print  "ln $latest_name sub is $sub\n";
       return {name => $latest_name,
        operation => {$latest_name => L(PF($sub),LEAF_DISPLAY($qs)
              ,RULE_INFO({rule_type => 'squote'}))}
        ,error_text => $qs};
     })),
   repetition => A(qr/\(/, 'repetition_cardinality', Z(A(qr/\s\s*/,
    {separator => 'item'})), qr/\)/, E(
     sub {my $in = shift;
#use Data::Dumper;print  "rep in is ".Dumper($in);
      my $others = shift;
      my $current_node = $others->{current_node};
#use Data::Dumper; print "others is ".Dumper($others)."\n";
      my $string_match = substr(${$others->{parse_this_ref}},
       $current_node->{position_when_entered},
       ($current_node->{position_when_completed} -
        $current_node->{position_when_entered}));
#      my $name_extra = '('. $string_match.')';
      my $rx = '';
      return {separator => $in->{separator},
       cardinality => $in->{repetition_cardinality},
       name_extra => $string_match};
     })),
   repetition_cardinality => O({'qm'=>qr/\?/}, {'sqm' => qr/s\?/},
    {'s'=>qr/s/}, {'nm'=>qr/((\d+)\.\.(\d+))/}, {'m0' => qr/(\.\.(\d+))/},
    {'n0'=> qr/((\d+)\.\.)/},E(
       sub {
        my $in = shift;
#use Data::Dumper;print  "rp is ".Dumper(\$in)."\n";
        if ($in->{qm}) {
          return {low=> 0, high => 1}
        }
        if ($in->{sqm}) {
          return {low=> 0, high => 0}
        }
        if ($in->{s}) {
          return {low=> 1, high => 0}
        }
        if (defined $in->{nm}) {
          my ($low, $high);
          $in->{nm} =~ /(\d+)\.\.(\d+)/;
          if ($1 > $2) {
            $low = $2;
            $high = $1;
          }
          else {
            $low = $1;
            $high = $2;
          }
#print  "low is $low and high is $high\n";
          return {low=> $low, high => $high}
        }
        if (defined $in->{m0}) {
          $in->{m0} =~ /\.\.(\d+)/;
          return {low=> 1, high => $1}
        }
        if (defined $in->{n0}) {
          $in->{n0} =~ /(\d+)\.\./;
          return {low=> $1, high => 0}
        }
     })),
);

our $rd_parser = new Parse::Stallion(\%rd_rules);
#use Data::Dumper;print  Dumper($rd_parser)."\nis rd parser\n";


sub pre_production {
  my $parameters = shift;
  my $error_text = $parameters->{error_text};
  my $name = $parameters->{name};
  my $pf_sub = sub {
    my $parameters = shift;
    my $parent_node = $parameters->{parent_node};
    my $grand_parent = $parent_node->{parent};
    push @{$grand_parent->{productions}}, $error_text;
    return 1;
  };
  return L(PF($pf_sub),LEAF_DISPLAY("pre rule name $name and et $error_text"));
}

sub skipsub {
  my $parameters = shift;
  my $node_name = $parameters->{node_name};
  my $error_text = $parameters->{error_text};
  my $pf_sub = sub {
#delete $_[0]->{parser};use Data::Dumper;print "skipsub pfparameters are ".Dumper(\@_)."\n";
    my $parameters = shift;
    my $parent_node = $parameters->{parent_node};
    my $previous_node =
     $parent_node->{children}->[$#{$parent_node->{children}}];
    my $previous_node_value = $previous_node->{parse_match};
#use Data::Dumper;print "in skipsub pnv is ".Dumper($previous_node_value)."\n";
#print " skipsubnode name $node_name and et $error_text\n";
    my $current_value;
    return 1, $current_value;
  };
  my $pb_sub = sub {
    my $parameters = shift;
    my $parent_node = $parameters->{parent_node};
    my $grand_parent = $parent_node->{parent};
    if (!(defined $grand_parent->{first_max})) {
      $grand_parent->{first_max} = $error_text;
      $grand_parent->{first_max_at} = $parameters->{current_position};
    }
    return;
  };
  $error_text = $error_text || '';
  return {'' => L(PF($pf_sub), PB($pb_sub),
   LEAF_DISPLAY("skip $node_name followed by $error_text"))};
}

sub error_name {
  return s/\_/ /g;
}

sub __rd_new {
  my $type = shift;
  my $rules_string = shift;
  my $trace = shift;
#print  "rule string is $rules_string\n";
  my @pt;
  my $parse_info = {};
  my $rules_out;
  $__current_package_name = 'rd_package_'.$__current_package_number++;
  $__package_text = "package $__current_package_name;\n";
  @__package_list = ();
  @other_rules = ();
  $any_deferred = 0;
  if ($trace) {
    my $rules_out = eval {$rd_parser->parse_and_evaluate(
        $rules_string, {parse_info=>$parse_info
      , parse_trace => \@pt, no_evaluation => 1
       }
       )};
      use Data::Dumper;print  " pt ".Dumper(\@pt);
    if ($@) {
      use Data::Dumper;print  "tracefailurefailure pt ".Dumper(\@pt);
    }
  }
  else {
    $rules_out = eval {$rd_parser->parse_and_evaluate(
        $rules_string, {parse_info=>$parse_info, no_evaluation => 1
#        , parse_trace => \@pt
       }
       )};
    if ($@) {
      use Data::Dumper;print  "failurefailure pt ".Dumper(\@pt);
    }
  }
#use Data::Dumper;print  "pt is ".Dumper(\@pt)."\n";
#delete $parse_info->{bottom_up_left_to_right};
#use Data::Dumper;print  "pi is ".Dumper($parse_info)."\n";
#  if ($@) {croak "\nUnable to create parser due to the following:\n$@\n"};
  if (!$parse_info->{parse_succeeded}) {
    croak("Unable to parse behind line ".$parse_info->{max_line}.", position: ".
     $parse_info->{max_line_position});
  }
#use Data::Dumper;print  "ro is ".Dumper($rules_out)."\n";
  my %raw_rules;
  foreach my $rule (@$rules_out, @other_rules) {
    my $rule_name = $rule->{rule_name};
    push @{$raw_rules{$rule_name}}, @{$rule->{rule_definition}};
  }
  my %other_rule;
  foreach my $rule (@other_rules) {
    $other_rule{$rule->{rule_name}}=1;
  }
  my %rule_productions;
  foreach my $rule (keys %raw_rules) {
    my @o_args;
    my $single_o_arg;
    my $single_operation;
    my $not_first_production = 0;
    my $item_count;
    foreach my $production (@{$raw_rules{$rule}}) {
      if ($::RD_AUTOACTION &&
#       !$other_rule{$rule} &&
       ($production->[$#{$production}]->{item_type} ne 'action')) {
        my $sub = mctr($::RD_AUTOACTION, $rule);
        my $count = ++$__counts->[0]->{actions}->{$rule};
        my $latest_name = '__ACTION'.$count.'__';
        push @{$production}, {item_type => 'action', name => $latest_name,
         operation => {$latest_name => L(PF($sub),
           LEAF_DISPLAY($::RD_AUTOACTION)
         ,RULE_INFO({rule_type => 'action'})
        )}};
      }
      my @a_args;
      $item_count = scalar @{$production};
      foreach my $i (0..$#{$production}-1) {
        my $item = $production->[$i];
        push @a_args, $item->{operation};
        if ($__rule_has_error->{$rule}) {
          my $next_item = $production->[$i+1];
          my $error_text;
          if (defined $next_item->{error_text}) {
            $error_text = $next_item->{error_text};
          }
          else {
            $error_text = $next_item->{name};
            $error_text =~ s/\_/ /g;
          }
          push @a_args, skipsub({node_name=>$item->{name},
           error_text => $error_text});
        }
      }
      my $last_item = $production->[$#{$production}];
#use Data::Dumper; print "last item is ".Dumper($last_item)."\n";
      if ($last_item->{item_type} eq 'token' ||
       $last_item->{item_type} eq 'squoted_string' ||
#       $last_item->{item_type} eq 'rule_name' ||
       $last_item->{item_type} eq 'mtoken') {
        ($single_operation) = values %{$last_item->{operation}};
      }
      push @a_args, $last_item->{operation};
#      if ($__rule_has_error->{$rule}) {
#        push @a_args, skipsub({node_name=>$last_item->{name}});
#      }
      my $first_item = $production->[0];
      unshift @a_args,
       pre_production({error_text => $first_item->{error_text} ||
        $first_item->{name}, name => $rule});
      if ($__rule_has_commit->{$rule} && $first_item->{item_type} ne 'error' &&
       $first_item->{item_type} ne 'uncommit' && $not_first_production) {
        unshift @a_args, $__check_commit;
      }
      push @o_args, A(@a_args, MATCH_ONCE());
      $single_o_arg = A(@a_args, $move_to_parent,
       RULE_INFO({rule_type => 'rule'}), MATCH_ONCE());
      $not_first_production = 1;
    }
    if ($#o_args > 0) {
      $rule_productions{$rule} = A($__start_rule, O(@o_args),
         $__end_rule, RULE_INFO({rule_type => 'rule'}),
           MATCH_ONCE());
    }
    else {
      if ($single_operation && $item_count == 1 && !($other_rule{$rule})) {
        $rule_productions{$rule} = $single_operation;
      }
      else {
        $rule_productions{$rule} = $single_o_arg;
      }
    }
  }
#use Data::Dumper;print  "therules is ".Dumper(\%rule_productions)."\n";
  my $new_parser = eval {new Parse::Stallion(\%rule_productions,
    {separator => '.', final_position_routine => sub {return $_[1]},
     traversal_only => 1, fast_move_back => !$any_deferred,
     unreachable_rules_allowed => 1}
  )};
  if ($@) {print "errff $@";croak $@}
  $__package_text .= join("", @__package_list);
#print "pt is $__package_text\n";
  eval $__package_text; #for lexicals in the name space to work
  if ($@) {print "package text error $@"; croak $@}
  my $parser_rules = $new_parser->{rule};
  foreach my $parse_rule_key (keys %{$parser_rules}) {
    my $parse_rule = $parser_rules->{$parse_rule_key};
#use Data::Dumper;print "looking at ".Dumper($parse_rule)."\n";
    if (defined $parse_rule->{parse_forward}) {
      if ($__package_temp_names{$parse_rule->{parse_forward}}) {
        my $new_sub = "\\\&".
         $__package_temp_names{$parse_rule->{parse_forward}};
#print "new sub is $new_sub\n";
        $parse_rule->{parse_forward} =
         eval $new_sub;
         if ($@) {print "error on ptm $@";croak $@};
#print "updated pf\n";
      }
    }
  }
#print "count delay\n";
  while (my $subname = pop @__package_sub_names) {
    my $new_sub = "\\\&".  $__package_temp_names{$subname};
#print "nsp is $new_sub\n";
    $__package_subs{$subname} = eval $new_sub;
    if ($@) {print "deneror on ptm $@";croak $@};
  }
#use Parse::Stallion::EBNF;
#print ebnf Parse::Stallion::EBNF($new_parser)."\n";
  return $new_parser;
}

sub new {
  my $type = shift;
  my $grammar = shift;
  my $trace = shift;
  my $class = ref($type) || $type;
  my $parsing_info = {};
  $parsing_info->{parser} = __rd_new($type, $grammar, $trace);
  return bless $parsing_info, $class;
}

sub AUTOLOAD {
  our $AUTOLOAD;
  my $self = shift;
  my $string = shift;
  my $old_parse = shift;
  if (!$old_parse) {
    @arg = ();
    %arg = ();
  }
  my $reference;
  if (ref $string) {
    $reference = $string;
    $string = $$string;
  }
  $string =~ /\A$skip/cg;
  my $start_position = pos $string;
  @__skip=();
  push @__skip, $__default_skip = $skip;
  $__error_message = '';
  my $start_rule = $AUTOLOAD;
#print "start rule is $start_rule\n";
#print  "found mct\n";
  @__delay = ();
  $__rule_has_commit = {};
  $__rule_has_error = {};
  $start_rule =~ s/.*:://;
  $commit = 0;
  my $previous_parser = $__thisparser;
  $__thisparser = $self;
  my $pi = {};
#print  "String is $string\n";
  my @pt;
  my $results;
  $__rule_info = $self->{parser}->rule_info_hash_ref;
  if ($__trace) {
    eval {$results = $self->{parser}->parse_and_evaluate($string,
     {start_rule => $start_rule, parse_info => $pi
       ,parse_hash =>
       {
        the_parser => $self->{parser}}
            ,max_steps => $__max_steps || 1000000
     , start_position => $start_position
     , parse_trace=>\@pt
     });
       foreach my $action (@__delay) {
          &{$action->{sub}}($action->{parameters});
       }
     };
use Data::Dumper; print  "bigtracept ".Dumper(\@pt)."\n";
  }
  else {
    eval {$results = $self->{parser}->parse_and_evaluate($string,
     {start_rule => $start_rule, parse_info => $pi
       ,parse_hash =>
       {
        the_parser => $self->{parser}
       }
            ,max_steps => $__max_steps || 1000000
     , start_position => $start_position
#   , parse_trace=>\@pt
     });
#print "done with er\n";
       foreach my $action (@__delay) {
          &{$action->{sub}}($action->{parameters});
       }
     };
  }
  $__thisparser = $previous_parser;
#use Data::Dumper; print  "pt ".Dumper(\@pt)."\n";
  $skip = $__default_skip;
  if ($@) {
print "em $@\n";
#use Data::Dumper; print  "pt ".Dumper(\@pt)."\n";
croak $@}
#use Data::Dumper;print  "resulsts are ".Dumper($results)."\n";
#use Data::Dumper;print  "pi is ".Dumper($pi)."\n";
  if ($pi->{parse_succeeded}) {
    if ($reference) {
      substr($$reference, 0, $pi->{final_position}) = '';
    }
    return $pi->{tree}->{parse_match};
  }
  else {
    if (length($__error_message) > 0) {print STDERR $__error_message}
    return undef;
  }
}

sub DESTROY {
}

1;

__END__

=head1 NAME

Parse::Stallion::RD - Parser for subset of grammars written
for Parse::RecDescent

=head1 NOTE

This is an exercise to show how to use Parse::Stallion, the module
Parse::Stallion::RD runs atop of.
On some test cases, Parse::Stallion::RD runs faster than Parse::RecDescent.
Rewriting a grammar for Parse::Stallion should be even faster.

There are differences in 
behaviors of a parser generated with Parse::Stallion::RD and a
parser from Parse::RecDescent.
If behavior is missing here that is desired, please report to
arthur\@acm.org .
The implemented features with differences are listed below, other features
were not put in for this release.


=head1 VERSION

0.2

=head1 SYNOPSIS

  use Parse::Stallion::RD;
  $parser = new Parse::Stallion::RD($grammar);
  $parser->startrule($text);

  compared with:

  use Parse::RecDescent;
  $parser = new Parse::RecDescent($grammar);
  $parser->startrule($text);


=head1 DESCRIPTION

See Parse::RecDescent's documentation.  This section lists what is
similar to Parse::RecDescent and what is not.

=head2 Features implemented with noted differences

and rules

or rules (|)

rules defined on different lines

single quotes

double quotes (with interpolation)

repetition specifier (with separator,
 Parse::Stallion::RD allows non-raw patterns as separators)

tokens

$skip

actions

@item and %item (the set of values in %item are the same values in @item
 which is different than Parse::RecDescent for some directives, i.e.
 leftop and rightop)

$return

$skip

$thisline and $prevline

$thisparser (set for within an action but not following the action)

start-up actions

autoactions   ($::RD_AUTOACTION)

look-ahead

<leftop>

<rightop>

<reject> (no conditions with < or >)

alternations  (though the naming of alternations is not consistent with %item

<commit>, <uncommit>

<error>, <error?>, <error: message>, <error?: message>
 (error messages are not split across lines the same way, if
 an <error> directive is not the last or clause in a production, then
 only the or-clauses that occured before will show up)

<defer>

$text (does not reset the text back if modified)

=head2 Differences between Parse::RecDescent and Parse::Stallion

Here are some noteworthy differences between Parse::Stallion and
Parse::RecDescent that come up while developing this module.

=head3 String/Code

Parse::RecDescent takes a grammar from a string, Parse::Stallion
is set up via perl code.  Parse::Stallion::EBNF has a string
oriented interface for Parse::Stallion.

=head3 Actions/Evaluation/Parse Forward/Parse Backtrack

Deferred actions somewhat correspond to
the evaluation phase of Parse::Stallion.

In Parse::Stallion, if the evaluation is done after the parsing, 
the evaluation routine does get the results of other 'sub' evaluation
routines within its parameters.  In Parse::RecDescent a delayed action
just returns the number of delayed actions to that point and not
the result of the delayed action, an undelayed action returns either
$return or the value of the last line.

In Parse::RecDescent, items in actions are similar to the
parameters passed in the evaluation phase of Parse::Stallion.

Parse::Stallion also has Leaf nodes with subroutines that
execute during the parsing phase: parse_forward
and parse_backtrack.  Those are used to mimic the actions in Parse::RecDescent.

In Parse::Stallion, if a parameter occurs more than once, it
is passed in as an array reference, instead of being overwritten
as is done in Parse::RecDescent.  The parameters passed in
during the evaluation phase correspond to all the subrules
in a possibly complex rule, not just the latest items in an
and clause, as is in Parse::RecDescent.

=head3 Error

<error> messages in Parse::RecDescent provide useful information,
such as where an error occured, what else was expected.  This can
clearly be duplicated as was done in this module, but it requires
making use of recording the position with Leaf rules.  Though the
returned parameters max_position and max_position_at may help.

=head3 MATCH_ONCE

Parse::Stallion has the option of a rule matching once and if failing,
not to attempt 'variations'.  That is, if a multiple rule matches
the string 5 times, the Parse::RecDescent will not backtrack to
try it 4 times.  Parse::Stallion by default will try to backtrack, which
may prove slower, but one can create a rule with the MATCH_ONCE 
option to allow this, as is done in Parse::Stallion::RD.

=head3 LEFTOP, RIGHTOP, REPITITION, AND ALIASES

Parse::RecDescent's leftop operation can include the separator in the
directive's return value or not depending on how it is set up.

   <leftop: 'a' 'b' 'c'>

will return an array ('a','c','c,'....'c').  Whereas

   <leftop: 'a' b 'c'>
   b: 'b'

will return an array ('a','b','c','b','c',...,'b','c').

In Parse::Stallion, on can specify the aliases of subrules and those
that share the same name, end up in an array ref.

  A({thelist => qr/a/}, M(A(qr/b/, {thelist => qr/c/})))

will result in the evaluation routine having a parameter:

  $_[0]->{thelist} = ['a','c', ..., 'c']

The above cases also affect rightop's and repetition in Parse::RecDescent.


=head2 OTHER ITEMS

This module requires Text::Balanced to work but since Parse::Stallion
does not require Text::Balanced and this is part of Parse::Stallion it
is not part of the dependencies.

One can increase $Parse::Stallion::RD::__max_steps in case one runs
into the 'Not enough steps to do parse...' error.

=head1 AUTHOR

Arthur Goldstein, E<lt>arthur@acm.orgE<gt>

=head1 ACKNOWLEDGEMENTS

Damian Conway, Christopher Frenze, and Rene Nyffenegger.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Arthur Goldstein.  All Rights Reserved.

This module is free software. It may be used, redistributed and/or modified
under the terms of the Perl Artistic License
(see http://www.perl.com/perl/misc/Artistic.html)

=head1 BUGS

Please email in bug reports.

=head1 TO DO AND FUTURE POSSIBLE CHANGES

Implement missing items from Parse::RecDescent.  Email priorities.

=head1 SEE ALSO

t/rd.t    Test file that comes with installation and has many examples.

Parse::RecDescent

Parse::Stallion

=cut
