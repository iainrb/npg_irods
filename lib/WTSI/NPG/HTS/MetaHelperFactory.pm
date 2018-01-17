package WTSI::NPG::HTS::MetaHelperFactory;

use strict;
use warnings;
use Moose;

use WTSI::NPG::HTS::MetaHelper;

with qw [WTSI::NPG::iRODS::Reportable::ConfigurableForRabbitMQ
         WTSI::DNAP::Utilities::Loggable
    ];

our $VERSION = '';

has 'irods' =>
  (isa           => 'WTSI::NPG::iRODS',
   is            => 'ro',
   required      => 1,
   documentation => 'An iRODS handle to run searches and perform updates');

=head2 make_meta_helper

  Example    : my $helper = $factory->make_meta_helper();

  Description: Factory for creating MetaHelper objects of an appropriate
               class, depending if RabbitMQ messaging is enabled.

  Returntype : WTSI::NPG::HTS::MetaHelper or
               WTSI::NPG::HTS::MetaHelperWithReporting

=cut

sub make_meta_helper {
    my ($self, ) = @_;
    my @args;
    if ($self->enable_rmq) {
        push @args, 'enable_rmq'         => 1;
        push @args, 'channel'            => $self->channel;
        push @args, 'exchange'           => $self->exchange;
        push @args, 'routing_key_prefix' => $self->routing_key_prefix;
    }
    push @args, 'irods'                  => $self->irods;
    my $helper;
     if ($self->enable_rmq) {
        # 'require' ensures MetaHelperWithReporting not used unless wanted
        # eg. prerequisite module Net::AMQP::RabbitMQ may not be installed
        require WTSI::NPG::HTS::MetaHelperWithReporting;
        $helper = WTSI::NPG::HTS::MetaHelperWithReporting->new(@args);
    } else {
        $helper = WTSI::NPG::HTS::MetaHelper->new(@args);
    }
    return $helper;
}



__END__

=head1 NAME

WTSI::NPG::HTS::MetaHelperFactory

=head1 DESCRIPTION

A Role for creating MetaHelper objects of an appropriate class:

=over

=item

WTSI::NPG::HTS::MetaHelperWithReporting if RabbitMQ is enabled;

=item

WTSI::NPG::HTS::MetaHelper otherwise.

=back


RabbitMQ is enabled if the attribute enable_rmq is true; disabled otherwise.


=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2018 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
