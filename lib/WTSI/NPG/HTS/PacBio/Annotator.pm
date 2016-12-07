package WTSI::NPG::HTS::PacBio::Annotator;

use List::AllUtils qw[uniq];
use Moose::Role;
use WTSI::NPG::iRODS::Metadata;

our $VERSION = '';

our $CELL_INDEX        = 'cell_index';
our $COLLECTION_NUMBER = 'collection_number';
our $INSTRUMENT_NAME   = 'instrument_name';
our $RUN               = 'run';
our $SAMPLE_LOAD_NAME  = 'sample_load_name';
our $SET_NUMBER        = 'set_number';
our $SOURCE            = 'source';
our $WELL              = 'well';

our $PRODUCTION_SOURCE = 'production';

with qw[
         WTSI::NPG::HTS::Annotator
       ];

sub make_primary_metadata {
  my ($self, $metadata) = @_;

  defined $metadata or
    $self->logconfess('A defined metadata argument is required');

  my @avus;
  push @avus, $self->make_avu($CELL_INDEX,        $metadata->cell_index);
  push @avus, $self->make_avu($COLLECTION_NUMBER, $metadata->collection_number);
  push @avus, $self->make_avu($INSTRUMENT_NAME,   $metadata->instrument_name);
  push @avus, $self->make_avu($RUN,               $metadata->run_name);
  push @avus, $self->make_avu($SET_NUMBER,        $metadata->set_number);

  return @avus;
}

sub make_secondary_metadata {
  my ($self, $metadata, @run_records) = @_;

  defined $metadata or
    $self->logconfess('A defined metadata argument is required');

  my @avus;

  if (@run_records) {
    # Production data
    push @avus, $self->make_avu($SAMPLE_LOAD_NAME, $metadata->sample_name);
    push @avus, $self->make_avu($SOURCE,           $PRODUCTION_SOURCE);
    push @avus, $self->make_library_metadata(@run_records);

    foreach my $run_record (@run_records) {
      push @avus, $self->make_study_metadata($run_record->study);
      push @avus, $self->make_sample_metadata($run_record->sample);
    }
  }
  else {
    # R & D data
    push @avus, $self->make_avu($SAMPLE_NAME, $metadata->sample_name);
  }

  return @avus;
}

sub make_library_metadata {
  my ($self, @run_records) = @_;

  my @avus;
  my @library_ids =
    uniq map { $_->pac_bio_library_tube_legacy_id } @run_records;

  foreach my $library_id (@library_ids) {
    push @avus, $self->make_avu($LIBRARY_ID, $library_id);
  }

  my $num_libraries = scalar @library_ids;
  if ($num_libraries > 1) {
    push @avus, 'multiplex', q[1];
    push @avus, 'library_id_composite', (join q[;], @library_ids);
  }

  return @avus;
}

no Moose::Role;

1;

__END__

=head1 NAME

WTSI::NPG::HTS::PacBio::Annotator

=head1 DESCRIPTION

A role providing methods to calculate metadata for WTSI PacBio
runs.

=head1 AUTHOR

Keith James <kdj@sanger.ac.uk>

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
