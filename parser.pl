#!/usr/bin/perl -w
#
# (c) vir
#
# Last modified: 2012-12-03 16:56:13 +0400
#

package YateLog::Entry;
use utf8;
use Data::Dumper;

sub new
{
	my $class = shift;
	return bless {@_}, $class;
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
	unshift @classes, 'collapsed';
	return qq{<div class="@classes"><h2>$t</h2>\n}
		. qq{<div class="msghead" onClick="on_click_log_message(this)">}.$self->to_html_head().qq{</div>\n<div class="msgbody">}.$self->to_html_body().qq{</div></div>\n};
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
	if(/^  (\w+)=(.*)$/) {
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
	$r .= qq#<div class="col1">$self->{type}</div>#;
	$r .= qq#<div class="col2">$self->{name}</div>#;
	return $r;
}

sub to_html_body
{
	my $self = shift;
	my $r = '';
	foreach my $k(qw( thread retval data )) {
		$r .= "$k: ".$self->quote_xml($self->{$k})."<br />";
	}
	$r .= "<dl>";
	foreach my $k(@{ $self->{porder} }) {
		$r .= qq#<dt>$k</dt><dd>#;
		if(defined($self->{params}{$k}) && length($self->{params}{$k})) {
			$r .= $self->quote_xml($self->{params}{$k});
		} else {
			$r .= qq#<span style="color:blue;">«»</span>#;
		}
		$r .= qq#</dd>#;
	}
	$r .= "</dl>";
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
	$r .= qq#<div class="col1">$self->{src}</div>#;
	$r .= qq#<div class="col2">$self->{head}</div>#;
	return $r;
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
	$r .= qq#<div class="col1">$self->{listener} <strong>#;
	if($self->{dir} eq 'send') {
		$r .= '=&gt;';
	} else {
		$r .= '&lt;=';
	}
	$r .= qq#</strong> $self->{peer}</div>#;

	$r .= qq#<div class="col2">#;
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
	return '<pre>'.$self->{text}.'<pre>';
}

package main;
use utf8;
use strict;
use warnings FATAL => 'uninitialized';
use Data::Dumper;

my $log = read_log($ARGV[0]);
#print Dumper($log);

binmode(STDOUT, ':utf8');
print qq{<html><head>\n};
print qq{<meta http-equiv="Content-type" content="text/html;charset=UTF-8">\n};
print qq{<link rel="stylesheet" type="text/css" href="style.css" />\n};
print qq{<script type="text/javascript" src="script.js"></script>\n};
print qq{</head><body>\n};
foreach my $e(@$log) {
	print $e->to_html if $e;
}
print qq{</body></html>\n};

sub make_object
{
	my($line) = @_;
	if($line =~ /^(Sniffed|Returned .*?) '([\w\.]+?)'/) {
		return new YateLog::Entry::Message(type => $1, name => $2);
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


