package WTSI::NPG::OM::BioNano::Annotator;

use DateTime;
use Moose::Role;
use UUID;

use WTSI::NPG::OM::Metadata;

our $VERSION = '';

with qw[WTSI::NPG::HTS::Annotator]; # TODO better location for "parent" role

has 'uuid' =>
  (is       => 'ro',
   isa      => 'Str',
   required => 1,
   lazy     => 1,
   builder  => '_build_uuid',
   documentation => 'UUID generated for the publication to iRODS');

=head2 make_bnx_metadata

  Arg [1]    : WTSI::NPG::OM::BioNano::ResultSet
  Example    : @bnx_meta = $publisher->get_bnx_metadata();
  Description: Find metadata AVUs from the BNX file header, to be applied
               to a BioNano collection in iRODS.
  Returntype : ArrayRef[HashRef] AVUs to be used as metadata

=cut

sub make_bnx_metadata {
    my ($self, $resultset) = @_;
    my $bnx = $resultset->bnx_file;
    my @bnx_meta = (
        $self->make_avu($BIONANO_CHIP_ID, $bnx->chip_id),
        $self->make_avu($BIONANO_FLOWCELL, $bnx->flowcell),
        $self->make_avu($BIONANO_INSTRUMENT, $bnx->instrument),
    );
    return \@bnx_meta;
}


=head2 make_primary_metadata

  Arg [1]    : [WTSI::NPG::OM::BioNano::ResultSet] ResultSet object. Required.
  Example    : @primary_meta = $publisher->get_primary_metadata($rs, $uuid);
  Description: Generate primary metadata AVUs, to be applied
               to a BioNano collection in iRODS.
  Returntype : ArrayRef[HashRef] AVUs to be used as metadata

=cut

sub make_primary_metadata {
    my ($self, $resultset) = @_;
    if (! defined $resultset) {
        $self->logcroak('BioNano ResultSet argument is required');
    }
    my @metadata;
    push @metadata, @{$self->make_bnx_metadata($resultset)};
    push @metadata, @{$self->make_uuid_metadata($self->uuid)};
    return \@metadata;
}


=head2 make_secondary_metadata

  Arg [1]    : db handle
  Example    : @secondary_meta = $publisher->get_secondary_metadata($dbh);
  Description: Generate secondary metadata AVUs, including sample and
               study information from the ML Warehouse database, to be
               applied to a BioNano collection in iRODS.
  Returntype : ArrayRef[HashRef] AVUs to be used as metadata

=cut

sub make_secondary_metadata {
    my ($self, $mlwh_schema) = @_;
    if (! defined $mlwh_schema) {
        $self->logcroak('ML Warehouse schema argument is required');
    }
    my @metadata;
    # FIXME placeholder; need to add metadata terms
    return \@metadata;
}


=head2 make_uuid_metadata

  Arg [1]    : None
  Example    : @uuid_meta = $publisher->get_uuid_metadata();
  Description: Generate a UUID metadata AVU, to be applied
               to a BioNano collection in iRODS.
  Returntype : ArrayRef[HashRef] AVUs to be used as metadata

=cut

sub make_uuid_metadata {
    my ($self) = @_;
    my @uuid_meta = (
        $self->make_avu($BIONANO_UUID, $self->uuid),
    );
    return \@uuid_meta;
}


sub _build_uuid {
    my ($self,) = @_;
    my $uuid_bin;
    my $uuid_str;
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_str);
    return $uuid_str;
}

no Moose::Role;

1;

__END__

=head1 NAME

WTSI::NPG::OM::BioNano::Annotator

=head1 DESCRIPTION

A role providing methods to generate metadata for WTSI Optical Mapping
runs.

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2016 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
