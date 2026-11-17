#!/bin/bash
# Lessons cycle, deterministic (no model): reads <vault>/memory/mistakes.md and applies the date rules.
#   observed --(count reaches 2)--> trial --(LESSON_TRIAL_DAYS without a repeat)--> rule
#   rule --(LESSON_RETIRE_DAYS without a repeat)--> retired into archive/mistakes-retired.md
#   more than LESSON_MAX_RULES active rules: the one unused longest is retired.
# Usage: lessons.sh <vault_dir>      (today's date: MP_TODAY or the system date)
# Counting (adding 1 per correction) is the maintainer model's job; this script only moves statuses by date.
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
v="${1:-$VAULT}"; f="$v/memory/mistakes.md"
[ -f "$f" ] || exit 0
mkdir -p "$v/archive"
LP_TODAY=$(mp_today) LP_TRIAL="$LESSON_TRIAL_DAYS" LP_RETIRE="$LESSON_RETIRE_DAYS" LP_MAX="$LESSON_MAX_RULES" \
LP_FILE="$f" LP_ARCHIVE="$v/archive/mistakes-retired.md" perl -MTime::Local -e '
use strict; use warnings;
my ($file,$arch,$today)=($ENV{LP_FILE},$ENV{LP_ARCHIVE},$ENV{LP_TODAY});
my ($trial,$retire,$max)=($ENV{LP_TRIAL},$ENV{LP_RETIRE},$ENV{LP_MAX});
sub ep { my @p=split /-/,$_[0]; return timegm(0,0,12,$p[2],$p[1]-1,$p[0]); }
sub age { return int((ep($today)-ep($_[0]))/86400); }
open my $in,"<",$file or exit 0; my @L=<$in>; close $in; chomp @L;
my ($ai,$ri)=(-1,-1);
for my $i (0..$#L) { $ai=$i if $L[$i]=~/^## Active rules\s*$/ && $ai<0; $ri=$i if $L[$i]=~/^## Records\s*$/ && $ri<0; }
exit 0 if $ai<0 || $ri<0 || $ri<$ai;
my @head=@L[0..$ai]; my @act=@L[$ai+1..$ri-1]; my @rec=@L[$ri+1..$#L];
# split records into a preamble and ### blocks
my @pre; my @blocks; my $cur;
for my $l (@rec) {
  if ($l=~/^### (.+?)\s*$/) { $cur={topic=>$1,lines=>[$l]}; push @blocks,$cur; }
  elsif ($cur) { push @{$cur->{lines}},$l; } else { push @pre,$l; }
}
my %bul;   # topic => index in @act
for my $i (0..$#act) { $bul{$1}=$i if $act[$i]=~/^- \[([^\]]+)\] \((?:trial|rule)\)/; }
my ($promoted,$retired,$changed)=(0,0,0);
for my $b (@blocks) {
  $b->{ok}=0;
  for my $i (1..$#{$b->{lines}}) {
    if ($b->{lines}[$i]=~/^(\d+) · (\w+) · (\d{4}-\d\d-\d\d)\s*$/) { @$b{qw(ci count status last)}=($i,$1,$2,$3); $b->{ok}=1; last; }
  }
}
sub setstatus { my ($b,$st)=@_; $b->{status}=$st; $b->{lines}[$b->{ci}]="$b->{count} · $st · $b->{last}";
  if (defined $bul{$b->{topic}}) { $act[$bul{$b->{topic}}]=~s/\((?:trial|rule)\)/($st)/; } $changed=1; }
for my $b (@blocks) {
  next unless $b->{ok};
  if ($b->{status} eq "observed" && $b->{count}>=2) {
    setstatus($b,"trial"); $promoted++;
    unless (defined $bul{$b->{topic}}) { push @act,"- [$b->{topic}] (trial) (rule text pending: describe the rule in one sentence)"; $bul{$b->{topic}}=$#act; }
  }
  if ($b->{status} eq "trial" && age($b->{last})>=$trial) { setstatus($b,"rule"); $promoted++; }
}
sub retire_block {
  my $b=shift; my $rule="";
  if (defined $bul{$b->{topic}}) { $rule=$act[$bul{$b->{topic}}]; $act[$bul{$b->{topic}}]=undef; delete $bul{$b->{topic}}; }
  $rule=~s/^- \[[^\]]+\] \((?:trial|rule)\)\s*//;
  open my $o,">>",$arch or die; 
  if (-z $arch) { print $o "---\ntype: decision\ndescription: lessons retired by the maintainer (nothing is deleted)\nstatus: active\ndate: $today\n---\n# Retired lessons\n"; }
  print $o "\n### $b->{topic}\n$b->{count} · retired · $b->{last} (retired $today)\n".($rule ne "" ? "Rule was: $rule\n" : "");
  close $o; $b->{gone}=1; $retired++; $changed=1;
}
for my $b (@blocks) { next unless $b->{ok}; retire_block($b) if $b->{status} eq "rule" && age($b->{last})>=$retire; }
# cap on active rules: retire the one unused longest
for (;;) {
  my @active=grep { $_->{ok} && !$_->{gone} && $_->{status}=~/^(trial|rule)$/ } @blocks;
  last if @active<=$max;
  my ($old)=sort { $a->{last} cmp $b->{last} } @active; retire_block($old);
}
if ($changed) {
  my @outrec=@pre; for my $b (@blocks) { push @outrec,@{$b->{lines}} unless $b->{gone}; }
  my @outact=grep { defined } @act;
  open my $o,">",$file or die; print $o join("\n",@head,@outact,"## Records",@outrec),"\n"; close $o;
}
print "lessons: $promoted promoted, $retired retired\n";
'
