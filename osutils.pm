# Copyright 2017-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package osutils;

require 5.002;
use Mojo::Base -strict;

use Carp;
use base 'Exporter';
use Mojo::File 'path';
use bmwqemu;
use Mojo::IOLoop::ReadWriteProcess 'process';

our @EXPORT_OK = qw(
  dd_gen_params
  find_bin
  gen_params
  qv
  quote
  runcmd
  run
  run_diag
  attempt
);

# An helper to lookup into a folder and find an executable file between given candidates
# First argument is the directory, the remainining are the candidates.
sub find_bin {
    my ($dir, @candidates) = @_;

    foreach my $t_bin (map { path($dir, $_) } @candidates) {
        return $t_bin if -e $t_bin && -x $t_bin;
    }
    return;
}

# An helper to full a parameter list, typically used to build option arguments for executing external programs.
# mimics perl's push, this why it's a prototype: first argument is the array, second is the argument option and the third is the parameter.
# the (optional) hash argument which can include the prefix argument for the array, if not specified '-' (dash) is assumed by default
# and if parameter should not be quoted, for that one can use no_quotes. NOTE: this is applicable for string parameters only.
# if the parameter is equal to "", the value is not pushed to the array.
# For example: gen_params \@params, 'device', 'scsi', prefix => '--', no_quotes => 1;
sub gen_params(\@$$;%) {
    my ($array, $argument, $parameter, %args) = @_;

    return unless ($parameter);
    $args{prefix} = "-" unless $args{prefix};

    if (ref($parameter) eq "") {
        $parameter = quote($parameter) if $parameter =~ /\s+/ && !$args{no_quotes};
        push(@$array, $args{prefix} . "${argument}", $parameter);
    }
    elsif (ref($parameter) eq "ARRAY") {
        push(@$array, $args{prefix} . "${argument}", join(',', @$parameter));
    }

}

# doubledash shortcut version. Same can be achieved with gen_params.
sub dd_gen_params(\@$$) {
    my ($array, $argument, $parameter) = @_;
    gen_params(@{$array}, $argument, $parameter, prefix => "--");
}

# It merely splits a string into pieces interpolating variables inside it.
# e.g.  gen_params @params, 'drive', "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}" can be rewritten as
#       gen_params @params, 'drive', [qv "file=$basedir/l$i cache=unsafe if=none id=hd$i format=$vars->{HDDFORMAT}"]
sub qv($) {
    split /\s+|\h+|\r+/, $_[0];
}

# Add single quote mark to string
# Mainly use in the case of multiple kernel parameters to be passed to the -append option
# and they need to be quoted using single or double quotes
sub quote {
    "\'" . $_[0] . "\'";
}

sub run {
    my @cmd = @_;

    bmwqemu::diag "running `@cmd`";
    my $p = process(execute => shift @cmd, args => [@cmd]);
    $p->quirkiness(1)->separate_err(0)->start()->wait_stop();

    my $stdout = join('', $p->read_stream->getlines());
    chomp $stdout;

    close($p->$_ ? $p->$_ : ()) for qw(read_stream write_stream error_stream);

    return $p->exit_status, $stdout;
}

# Do not check for anything - just execute and print
sub run_diag {
    my ($exit_status, $output);
    eval {
        local $SIG{__DIE__} = undef;
        ($exit_status, $output) = run(@_);
        bmwqemu::diag("Command `@_` terminated with $exit_status" . (length($output) ? "\n$output" : ''));
    };
    bmwqemu::diag("Fatal error in command `@_`: $@") if ($@);
    return $output;
}

# Open a process to run external program and check its return status
sub runcmd {
    my (@cmd) = @_;
    my ($e, $out) = run(@cmd);
    bmwqemu::diag $out if $out && length($out) > 0;
    die "runcmd '" . join(' ', @cmd) . "' failed with exit code $e" . ($out ? ": '$out'" : '') unless $e == 0;
    return $e;
}

## use critic

sub wait_attempt {
    sleep($ENV{OSUTILS_WAIT_ATTEMPT_INTERVAL} // 1);
}

sub attempt {
    my $attempts = 0;
    my ($total_attempts, $condition, $cb, $or) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(attempts condition cb or)}) : @_;
    until ($condition->() || $attempts >= $total_attempts) {
        bmwqemu::diag "Waiting for $attempts attempts";
        $cb->();
        wait_attempt;
        $attempts++;
    }
    $or->() if $or && !$condition->();
    bmwqemu::diag "Finished after $attempts attempts";
}

1;
