#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw[$Bin];
use lib (-d "$Bin/../lib/perl5" ? "$Bin/../lib/perl5" : "$Bin/../lib");

use Getopt::Long;
use List::AllUtils qw[uniq];
use Log::Log4perl qw[:levels];
use Pod::Usage;

use WTSI::DNAP::Warehouse::Schema;
use WTSI::NPG::DriRODS;
use WTSI::NPG::HTS::ONT::GridIONMetaUpdater;
use WTSI::NPG::iRODS;

our $VERSION = '';
our $DEFAULT_ZONE = 'seq';

my $channel;
my $debug;
my $dry_run = 1;
my $enable_rmq;
my $exchange;
my @experiment_name;
my $log4perl_config;
my $routing_key_prefix;
my $stdio;
my $verbose;
my $zone;

GetOptions('channel=i'                               => \$channel,
           'debug'            => \$debug,
           'dry-run|dry_run!' => \$dry_run,
           'enable-rmq|enable_rmq'                   => \$enable_rmq,
           'exchange=s'                              => \$exchange,
           'experiment-name|experiment_name=s'       => \@experiment_name,
           'help'                                    => sub {
               pod2usage(-verbose => 2, -exitval => 0)
           },
           'logconf=s'                               => \$log4perl_config,
           'routing-key-prefix|routing_key_prefix=s' => \$routing_key_prefix,
           'verbose'                                 => \$verbose,
           'zone=s',                                 => \$zone,
           q[]                                       => \$stdio);

if ($log4perl_config) {
  Log::Log4perl::init($log4perl_config);
}
else {
  my $level = $debug ? $DEBUG : $verbose ? $INFO : $WARN;
  Log::Log4perl->easy_init({layout => '%d %-5p %c - %m%n',
                            level  => $level,
                            utf8   => 1});
}

my $log = Log::Log4perl->get_logger('main');
$log->level($ALL);
if ($log4perl_config) {
  $log->info("Using log config file '$log4perl_config'");
}

@experiment_name = uniq sort @experiment_name;

$zone ||= $DEFAULT_ZONE;

# Setup iRODS
my $irods;
if ($dry_run) {
  $irods = WTSI::NPG::DriRODS->new;
}
else {
  $irods = WTSI::NPG::iRODS->new;
}

# Find data objects
my @data_objs;
if ($stdio) {
  binmode \*STDIN, 'encoding(UTF-8)';

  $log->info('Reading iRODS paths from STDIN');
  while (my $line = <>) {
    chomp $line;
    push @data_objs, $line;
  }
}

foreach my $experiment_name (@experiment_name) {
  # Find one run's annotated objects by query
  my @query = ([experiment_name => $experiment_name],
               [device_id       => q[%], 'like']);
  push @data_objs, $irods->find_objects_by_meta("/$zone", @query);
}

@data_objs = uniq sort @data_objs;
$log->info('Processing ', scalar @data_objs, ' data objects');

# Update metadata
my $num_updated = 0;

if (@data_objs) {
  my $wh_schema = WTSI::DNAP::Warehouse::Schema->connect;

  my @updater_init_args = (irods       => $irods,
                           mlwh_schema => $wh_schema);
  if ($enable_rmq) {
    push @updater_init_args, enable_rmq => 1;
    if (defined $channel) {
      push @updater_init_args, channel => $channel;
    }
    if (defined $exchange) {
      push @updater_init_args, exchange => $exchange;
    }
    if (defined $routing_key_prefix) {
      push @updater_init_args, routing_key_prefix => $routing_key_prefix;
    }
  }
  $num_updated = WTSI::NPG::HTS::ONT::GridIONMetaUpdater->new(
      \@updater_init_args
  )->update_secondary_metadata(\@data_objs);
}

$log->info("Updated metadata on $num_updated files");

__END__

=head1 NAME

npg_update_gridion_metadata

=head1 SYNOPSIS

npg_update_gridion_metadata [--dry-run] --experiment-name name
  [--logconf file] [--verbose] [--zone name]

 Options:

  --debug            Enable debug level logging. Optional, defaults to
                     false.
  --dry-run
  --dry_run          Enable dry-run mode. Propose metadata changes, but
                     do not perform them. Optional, defaults to true.
  --experiment-name
  --experiment_name  The experiment name entered into MinKNOW.
  --help             Display help.
  --logconf          A log4perl configuration file. Optional.
  --verbose          Print messages while processing. Optional.
  --zone             The iRODS zone in which to work. Optional, defaults
                     to 'seq'.
  -                  Read iRODS paths from STDIN instead of finding them
                     by their run, lane and tag index.

 RabbitMQ options:

  --channel            A RabbitMQ channel number.
                       Optional; has no effect unless RabbitMQ is enabled.
  --enable-rmq
  --enable_rmq         Enable RabbitMQ messaging for metadata updates.
  --exchange           Name of a RabbitMQ exchange.
                       Optional; has no effect unless RabbitMQ is enabled.
  --routing-key-prefix
  --routing_key_prefix Prefix for a RabbitMQ routing key.
                       Optional; has no effect unless RabbitMQ is enabled.

=head1 DESCRIPTION

This script updates secondary metadata (i.e. LIMS-derived metadata,
not primary experimental metadata) on GridION data files in iRODS. The
files may be specified by run in which case either a specific run or
run range must be given. Additionally a list of iRODS paths may be piped
to STDIN.

In dry run mode, the proposed metadata changes will be written as INFO
notices to the log.

=head1 AUTHOR

Keith James <kdj@sanger.ac.uk>, Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2017, 2018 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
