#!/usr/bin/perl -w
#
# (c) vir
#
# Last modified: 2012-12-05 13:07:12 +0400
#

package YateLog::Entry;
use utf8;
use Data::Dumper;

our $id_counter = 'aaaaaa';

sub new
{
	my $class = shift;
	return bless {@_, eid => ++$id_counter}, $class;
}

sub want_more
{
	my $self = shift;
	return $self->{_PARSING};
}

sub append_line
{
	my $self = shift;
}

sub debug_print
{
	my $self = shift;
	print "$self @_\n";
}

sub to_html
{
	my $self = shift;
	my $t = lc ref($self);
	$t =~ s/.*:://;
	my @classes = ($t, 'logmsg');
	my $headattrs = '';
	unshift @classes, 'collapsable' if defined $self->to_html_collapse_body();
	unshift @classes, 'collapsed' if $self->to_html_collapse_body();
	$headattrs = ' onClick="on_click_log_message(this)"' if defined $self->to_html_collapse_body();
	my $r = qq{<div class="@classes">\n};
	$r .= qq#<a name="$self->{eid}" />#;
	my $tag = $self->{tag};
	$tag ||= $self->{call}->tag() if $self->{call};
	$r .= qq#<h2 class="tag_$tag tag">$tag</h2># if $tag;
	$r .= qq{<div class="msghead"$headattrs>}.$self->to_html_head().qq{</div>\n};
	$r .= qq{<div class="msgbody">}.$self->to_html_body().qq{</div>} if defined $self->to_html_collapse_body();
	$r .= qq{</div>\n};
	return $r;
}

sub to_html_head
{
	my $self = shift;
	return ref $self;
}

sub to_html_body
{
	my $self = shift;
	return '<pre>'.Dumper($self).'<pre>';
}

sub to_html_collapse_body
{
	return 1;
}

sub quote_xml
{
	my $self = shift;
	my($t) = @_;
	$t =~ s/\&/&amp;/sg;
	$t =~ s/\</&lt;/sg;
	$t =~ s/\>/&gt;/sg;
	$t =~ s/\"/&quot;/sg;
	return $t;
}

package YateLog::Entry::Message;
use base qw( YateLog::Entry );
use Carp;

sub new
{
	my $class= shift;
	return $class->SUPER::new(@_, _PARSING=>1);
}

sub append_line
{
	my $self = shift;
	croak "Already parsed" unless $self->{_PARSING};
	local($_) = @_;
	if(/^  thread=(0x[0-9a-zA-Z]+)\s+'(.*)'/) {
		$self->{thread} = $1;
		$self->{thrname} = $2;
	} elsif(/^  (\w+)=(.*)$/) {
		$self->{$1} = $2;
	} elsif(/^  param\['(.*?)'\] = '(.*)'/) {
		$self->{params}{$1} = $2;
		push @{ $self->{porder} }, $1;
	} elsif(/^\S/) {
		delete $self->{_PARSING};
	} else {
		warn ref($self).": Can't parse line <<$_>>\n";
	}
}

sub to_html_head
{
	my $self = shift;
	my $r = 'MSG';
	my $c1 = $self->{type};
	if(my $resp = $self->{response}) {
		$c1 .= qq@ <a href="#$resp->{eid}" onclick="event.cancelBubble=true;if (event.stopPropagation) event.stopPropagation();">[↓]</a>@;
		$c1 .= qq# <span class="response" onClick="return false">(#.$resp->{type};
		$c1 .= ' '.$resp->{retval} if $resp->{retval};
		$c1 .= qq#)</span>#;
	}
	if(my $reqid = $self->{reqid}) {
		$c1 .= qq@ <a href="#$reqid" onclick="event.cancelBubble=true;if (event.stopPropagation) event.stopPropagation();">[↑]</a>@;
	}
	$r .= qq#<div class="col1 col">$c1</div>#;

	my $c2 = $self->{name};
	$c2 .= qq# <span class="brief">$self->{brief}</span># if $self->{brief};
	$r .= qq#<div class="col2 col">$c2</div>#;
	$r .= q#<div class="col3 col">#.$self->format_time($self->{ts}).q#</div># if $self->{ts};
	return $r;
}

sub format_time
{
	my $self = shift;
	my $ts = shift;
	my $micros = ($ts =~ /^.*?\.(.*)/) ? '0.'.$1 : 0;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
	$sec += $micros;
	return sprintf "%4d-%02d-%02d %02d:%02d:%02.4f",
				 1900+$year, 1+$mon, $mday, $hour, $min, $sec, $micros;
}

sub to_html_body
{
	my $self = shift;
	my $r = '';
	foreach my $k(qw( thread thrname retval data time delay )) {
		$r .= "$k: ".$self->quote_xml($self->{$k})."<br />" if defined $self->{$k};
	}
	$r .= "<dl>";
	foreach my $k(@{ $self->{porder} }) {
		$r .= qq#<dt>$k</dt><dd>#;
		if(defined($self->{params}{$k}) && length($self->{params}{$k})) {
			$r .= $self->quote_xml($self->{params}{$k});
		} else {
			$r .= qq#<span class="emptyvalue">«»</span>#;
		}
		$r .= qq#</dd>#;
	}
	$r .= "</dl>";
	$r .= qq@ Go to <a href="#$self->{response}{eid}">Response ↓</a>@ if $self->{response} && $self->{response}{eid};
	$r .= qq@ <a href="#$self->{reqid}">Request ↑</a>@ if $self->{reqid};
	return $r;
}

package YateLog::Entry::Generic;
use base qw( YateLog::Entry );
use Carp;

sub new
{
	my $class= shift;
	return $class->SUPER::new(@_, _PARSING=>1);
}

sub append_line
{
	my $self = shift;
	local($_) = @_;
	if(delete $self->{_FINAL}) {
		delete $self->{_PARSING};
		return;
	}
	if($_ =~ /^------?$/) {
		if(defined $self->{text}) {
			$self->{_FINAL} = 1;
		} else {
			$self->{text} = '';
		}
	} elsif(defined $self->{text}) {
		$self->{text} .= "$_\n";
	} else {
		delete $self->{_PARSING};
	}
}

sub to_html_head
{
	my $self = shift;
	my $r = $self->{level} || '?';
	$r .= qq#<div class="col1 col">$self->{src}</div>#;
	$r .= qq#<div class="col2 col">$self->{head}</div>#;
	return $r;
}

sub to_html_body
{
	my $self = shift;
	return '<pre>'.$self->quote_xml($self->{text}).'<pre>';
}

sub to_html_collapse_body
{
	my $self = shift;
	return $self->{text} ? 1 : undef;
}

package YateLog::Entry::SipMessage;
use base qw( YateLog::Entry::Generic );
use Carp;

sub append_line
{
	my $self = shift;
#	$self->debug_print("append_line(@_)");
	$self->SUPER::append_line(@_);
}

sub to_html_head
{
	my $self = shift;
	my $r = $self->{level} || '?';
	$r .= qq#<div class="col1 col">$self->{listener} <strong>#;
	if($self->{dir} eq 'send') {
		$r .= '=&gt;';
	} else {
		$r .= '&lt;=';
	}
	$r .= qq#</strong> $self->{peer}</div>#;

	$r .= qq#<div class="col2 col">#;
	if($self->{text} =~ m/^(.*?)[\r\n]/s) {
		$r .= $self->quote_xml($1);
	} else {
		$r .= $self->{text};
	}
	$r .= qq#</div>\n#;
	return $r;
}

sub to_html_body
{
	my $self = shift;
	return '<pre>'.$self->quote_xml($self->{text}).'<pre>';
}

package YateLog::Analizer::Call;

sub new
{
	my $class = shift;
	return bless { @_ }, $class;
}

sub tag
{
	return shift->{tag};
}

sub merge
{
	my $self = shift;
	my($other) = @_;
	push @{ $self->{messages} }, @{ $other->{messages} };
}

sub add_message
{
	my $self = shift;
	my($e) = @_;
	push @{ $self->{messages} }, $e->{eid};
	foreach my $p(qw( caller called )) {
		my $n = $e->{params}{$p};
		next unless defined $n;
		push @{ $self->{numbers} }, $n unless $self->{tmp}{nums}{$n}++;
	}
}

package YateLog::Analizer;
use strict;
use warnings;
use Data::Dumper;

our %brief_fields = (
	'user.auth' => [qw( protocol username domain address )],
);

sub new
{
	my $class = shift;
	return bless {@_}, $class;
}

sub run
{
	my $self = shift;
	my($log) = @_;
	$self->{sum} = { timestamp => time() };
	my $c = { log => $log, lasttag => '00000' };
	$self->{cur} = $c;
	for($c->{index} = 0; $c->{index} < @$log; ++$c->{index}) {
		my $e = $log->[$c->{index}];
		++$self->{sum}{count}{ref($e)};
		if($e->{ts}) {
			$c->{ts} = $e->{ts};
			$self->{sum}{tsmin} = $e->{ts} unless $self->{sum}{tsmin};
			$self->{sum}{tsmax} = $e->{ts};
		}

		next if $e->{call};

		my $curtag;
		if(my $p = $e->{params}) {
			my $call = $self->get_call_for_current_message();
			$call->add_message($e);
			$e->{call} = $call if $call;
			if($e->{response}) {
				$e->{response}{call} = $call;
				$e->{response}{reqid} = $e->{eid};
			}

			if(my $br = $brief_fields{$e->{name}}) {
				$e->{brief} = '';
				foreach my $f(@$br) {
					$e->{brief} .= ' '.substr($f, 0, 1).'='.$p->{$f} if defined $p->{$f};
				}
			}
		} # end message
	}
	$self->renumber_calls;
	delete $self->{cur};
}

sub renumber_calls
{
	my $self = shift;
	my @keys = sort keys %{ $self->{calls} };
	my %calls;
#	my $counter = ('0' x int(1+(log(scalar(@keys))/log(10))));
	my $counter = 0;
	foreach my $k(@keys) {
		my $c = delete $self->{calls}{$k};
#		my $t = ++$counter;
		my $t = sprintf "%04d", ++$counter;
		$c->{tag} = $t;
		$calls{$t} = $c;
	}
	$self->{calls} = \%calls;
}

sub get_call_for_current_message
{
	my $self = shift;
	my $e = $self->{cur}{log}[$self->{cur}{index}];
	my $call;
	if($e->{params} && $e->{type} !~ /^returned/i) {
		my $response = $self->find_response();
		if($response) {
			$call = $self->get_call_for_message($response);
			$e->{response} = $response;
		}
	}
	return $self->get_call_for_message($e, $call);
}

sub get_call_for_message
{
	my $self = shift;
	my($e, $call) = @_;
	my $chans = $self->get_affected_channels($e);
	foreach my $c(@$chans) {
		my $old = $self->{cur}{chans}{$c};
		$call = $self->merge_calls($call, $old) if $old;
		$self->{cur}{chans}{$c} = $call if $call;
	}
	unless($call) {
		my $tag = $self->newtag;
		$call = new YateLog::Analizer::Call(tag => $tag);
		$self->{calls}{$tag} = $call;
		foreach my $c(@$chans) {
			$self->{cur}{chans}{$c} = $call;
		}
	}
	return $call;
}

sub merge_calls
{
	my $self = shift;
	my($c1, $c2) = @_;
#warn "merge_calls(".($c1||'undef').', '.($c2||'undef').")\n";
	return $c2 unless $c1;
	if($c1 != $c2) {
		$c1->merge($c2);
		delete $self->{calls}{$c2->{tag}}
	}
	foreach my $chan(keys %{ $self->{cur}{chans} }) {
		$self->{cur}{chans}{$chan} = $c1 if $self->{cur}{chans}{$chan} == $c2;
	}
	foreach my $e(@{ $self->{cur}{log} }) {
		$e->{call} = $c1 if $e->{call} && $e->{call} == $c2;
	}
	return $c1;
}

sub get_affected_channels
{
	my $self = shift;
	my($e) = @_;
	my @r;
	my $p = $e->{params};
	foreach my $param(qw( id targetid peerid lastpeerid )) {
		push @r, $p->{$param} if $p->{$param};
	}
	if($self->{ForkSameCall}) {
		foreach my $param(qw( fork.master fork.origid newid )) {
			push @r, $p->{$param} if $p->{$param};
		}
	}
	if(wantarray) { return @r; } else { return \@r; }
}

sub check_channels
{
	my $self = shift;
	my($entry, $curtag) = @_;
#warn "check_channels(".Dumper($entry).", ".($curtag||'undef')."\n";
	foreach my $chan($self->get_affected_channels($entry)) {
		$curtag = $self->tag_by_channel($chan, $curtag);
	}
	return $curtag;
}

sub find_response
{
	my $self = shift;
	my $index = $self->{cur}{index};
	my $thread = $self->{cur}{log}[$index]{thread};
	my $name = $self->{cur}{log}[$index]{name};
	my $id = $self->{cur}{log}[$index]{params}{id};
	for(;;) {
		++$index;
		my $e =  $self->{cur}{log}[$index];
		return undef unless $e;
		if($e->{params} && $e->{type} =~ /^returned/i) {
			return $e if $e->{thread} eq $thread && $e->{name} eq $name && (
				(!defined($e->{params}{id}) && !defined($id)) || (defined($e->{params}{id}) && defined($id) && $e->{params}{id} eq $id)
			);
		}
	}
}

=c

sub tag_by_channel
{
	my $self = shift;
	my($id, $curtag) = @_;
#warn "tag_by_channel(".($id||'undef').', '.($curtag||'undef')."): ".Dumper($self->{cur}{channels});
	my $tag = $self->{cur}{channels}{$id};
	if($tag) {
		$tag = $self->replace_tag($tag, $curtag) if $curtag && $curtag ne $tag;
	} elsif($curtag) {
		$tag = $curtag;
	} else {
		$tag = $self->newtag();
#		$self->{calls}{$tag} = new YateLog::Analizer::Call(tag => $tag);
	}
	$self->{cur}{channels}{$id} = $tag;
	return $tag;
}

sub replace_tag
{
	my $self = shift;
	my($oldtag, $newtag) = @_;

	foreach my $c(keys %{ $self->{cur}{channels} }) {
		$self->{cur}{channels}{$c} = $newtag if $self->{cur}{channels}{$c} eq $oldtag;
	}
	for(my $i = 0; $i < @{ $self->{cur}{log} }; ++$i) {
		$self->{cur}{log}[$i]{tag} = $newtag if $oldtag eq ($self->{cur}{log}[$i]{tag}||'');
	}

	warn "replace_tag($oldtag, $newtag)\n";
	return $oldtag;
}

=cut

sub newtag
{
	return ++shift->{cur}{lasttag};
}

sub summary
{
	my $self = shift;
	return Dumper($self);
}

package main;
use utf8;
use strict;
use warnings FATAL => 'uninitialized';
use Data::Dumper;

my $log = read_log($ARGV[0]);
#print Dumper($log);

my $a = new YateLog::Analizer(ForkSameCall => 1);
$a->run($log);

binmode(STDOUT, ':utf8');
print qq{<html><head>\n};
print qq{<meta http-equiv="Content-type" content="text/html;charset=UTF-8">\n};
print qq{<link rel="stylesheet" type="text/css" href="style.css" />\n};
print qq{<script type="text/javascript" src="script.js"></script>\n};
print qq{</head><body>\n};
print qq#<div id="summary"><pre>#.$a->summary().qq#</pre></div>\n#;
foreach my $e(@$log) {
	print $e->to_html if $e;
}
print qq{</body></html>\n};

sub make_object
{
	my($line) = @_;
	if($line =~ /^(Sniffed|Returned .*?) '([\w\.]+?)'(?: time=([\d\.]+))?(?: delay=([\d\.]+))?/) {
		return new YateLog::Entry::Message(type => $1, name => $2, ts => $3, delay => $4);
	} elsif(/^<sip:(.*?)> '(.*?)' received (\d+) bytes SIP message from (\S+)/) {
		return new YateLog::Entry::SipMessage(level => $1, listener => $2, size => $3, peer => $4, dir => 'recv');
	} elsif(/^<sip:(.*?)> '(.*?)' sending ('.*?'|code \d+) \w* to (\S+)/) {
		return new YateLog::Entry::SipMessage(level => $1, listener => $2, msg => $3, peer => $4,  dir => 'send');
	} elsif(/^<([\w\/]+):(.*?)> (.*)/) {
		return new YateLog::Entry::Generic(src => $1, level => $2, head => $3);
	} else {
		warn "Can't parse line <<$line>>\n";
		return undef;
	}
}

sub need_this_message
{
	my($msg) = @_;
	return 0 unless $msg;
#	return 0 if( ($msg->{src} || '') =~ /^link1\//);
	return 1 unless $msg->{name};
	return 0 if grep { $msg->{name} eq $_ } qw( database call.cdr module.update );
	return 1;
}

sub read_log
{
	my($fn) = @_;
	local $_;
	my @log;
	open F, '<:utf8', $fn or die "Can't open $fn: $!\n";
	my $current;
	while(<F>) {
		s/\s+$//s;
		if($current) {
			$current->append_line($_);
			next if $current->want_more();
		}
		$current = make_object($_);
		push @log, $current if need_this_message($current);
		undef $current unless $current && $current->want_more();
	}
	close F;
	return \@log;
}


