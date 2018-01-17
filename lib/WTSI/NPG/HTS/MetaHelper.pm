package WTSI::NPG::HTS::MetaHelper;

use namespace::autoclean;
use File::Basename;
use Moose;
use MooseX::StrictConstructor;

with qw[
         WTSI::DNAP::Utilities::Loggable
       ];

our $VERSION = '';

has 'irods' =>
  (isa           => 'WTSI::NPG::iRODS',
   is            => 'ro',
   required      => 1,
   documentation => 'An iRODS handle to run searches and perform updates; '.
                    'needed if RabbitMQ messaging is enabled.');

sub update_object_secondary_metadata {
    my ($self, $obj, $avus) = @_;
    $obj->update_secondary_metadata(@{$avus});
    return $obj;
}


__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

WTSI::NPG::HTS::MetaHelper

=head1 DESCRIPTION

Class to provide a wrapper for the update_secondary_metadata method of
WTSI::NPG::HTS::DataObject.

The MetaHelperWithReporting subclass applies method modifiers to the
wrapper, to enable RabbitMQ messaging. The MetaHelperFactory class allows
instances of either the base or subclass to be created; this enables
RabbitMQ prerequisites to be imported at runtime, if and only if they are
needed.

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
