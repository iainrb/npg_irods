package WTSI::NPG::HTS::Annotator;

use Data::Dump qw[pp];
use DateTime;
use Moose::Role;

use WTSI::NPG::HTS::Metadata;
use WTSI::NPG::iRODS::Metadata;

our $VERSION = '';

our @GENERAL_PURPOSE_SUFFIXES = qw[bin csv h5 tgz tif tsv txt xls xlsx xml];
our @GENO_DATA_SUFFIXES       = qw[gtc idat];
our @HTS_DATA_SUFFIXES        = qw[bam cram bai crai];
our @HTS_ANCILLARY_SUFFIXES   = qw[bamcheck bed flagstat json seqchksum
                                   stats xml];

our @DEFAULT_FILE_SUFFIXES = (@GENERAL_PURPOSE_SUFFIXES,
                              @GENO_DATA_SUFFIXES,
                              @HTS_DATA_SUFFIXES,
                              @HTS_ANCILLARY_SUFFIXES);

with qw[
         WTSI::DNAP::Utilities::Loggable
         WTSI::NPG::iRODS::Utilities
       ];

# See http://dublincore.org/documents/dcmi-terms/

=head2 make_creation_metadata

  Arg [1]    : Creating person, organization, or service, URI.
  Arg [2]    : Creation time, DateTime
  Arg [3]    : Publishing person, organization, or service, URI.

  Example    : my @avus = $ann->make_creation_metadata($time, $publisher)
  Description: Return a list of metadata AVUs describing the creation of
               an item.
  Returntype : Array[HashRef]

=cut

sub make_creation_metadata {
  my ($self, $creator, $creation_time, $publisher) = @_;

  defined $creator or
    $self->logconfess('A defined creator argument is required');
  defined $creation_time or
    $self->logconfess('A defined creation_time argument is required');
  defined $publisher or
    $self->logconfess('A defined publisher argument is required');

  return
    ($self->make_avu($DCTERMS_CREATOR,   $creator->as_string),
     $self->make_avu($DCTERMS_CREATED,   $creation_time->iso8601),
     $self->make_avu($DCTERMS_PUBLISHER, $publisher->as_string));
}

=head2 make_modification_metadata

  Arg [1]    : Modification time, DateTime.

  Example    : my @avus = $ann->make_modification_metadata($time)
  Description: Return an array of of metadata AVUs describing the
               modification of an item.
  Returntype : Array[HashRef]

=cut

sub make_modification_metadata {
  my ($self, $modification_time) = @_;

  defined $modification_time or
    $self->logconfess('A defined modification_time argument is required');

  return ($self->make_avu($DCTERMS_MODIFIED, $modification_time->iso8601));
}

=head2 make_study_metadata

  Arg [1]    : DBIx::Class::Manual::ResultClass MLWH Study record
  Example    : @study_meta = $p->make_secondary_metadata($study_record);
  Description: Generate study metadata AVUs for use in iRODS.
  Returntype : Array[HashRef] AVUs to be used as metadata

=cut

sub make_study_metadata {
  my ($self, $study) = @_;

  defined $study or
    $self->logconfess('A defined study argument is required');

  my $method_attr = {id_study_lims    => $STUDY_ID,
                     accession_number => $STUDY_ACCESSION_NUMBER,
                     name             => $STUDY_NAME,
                     study_title      => $STUDY_TITLE};

  return $self->_make_single_value_metadata($study, $method_attr);
}

=head2 make_sample_metadata

  Arg [1]    : DBIx::Class::Manual::ResultClass MLWH Sample record
  Example    : @sample_meta = $p->make_secondary_metadata($sample_record);
  Description: Generate sample metadata AVUs for use in iRODS.
  Returntype : Array[HashRef] AVUs to be used as metadata

=cut

sub make_sample_metadata {
  my ($self, $sample) = @_;

  defined $sample or
    $self->logconfess('A defined sample argument is required');

  my $method_attr = {accession_number => $SAMPLE_ACCESSION_NUMBER,
                     id_sample_lims   => $SAMPLE_ID,
                     name             => $SAMPLE_NAME,
                     public_name      => $SAMPLE_PUBLIC_NAME,
                     common_name      => $SAMPLE_COMMON_NAME,
                     supplier_name    => $SAMPLE_SUPPLIER_NAME,
                     cohort           => $SAMPLE_COHORT,
                     donor_id         => $SAMPLE_DONOR_ID};

  return $self->_make_single_value_metadata($sample, $method_attr);
}

=head2 make_type_metadata

  Arg [1]    : File name, Str.
  Arg [2]    : Array of valid file suffix strings, Str. Optional

  Example    : my @avus = $ann->make_type_metadata($sample, '.txt', '.csv')
  Description: Return an array of metadata AVUs describing the file 'type'
               (represented by its suffix).
  Returntype : Array[HashRef]

=cut

sub make_type_metadata {
  my ($self, $file, @suffixes) = @_;

  defined $file or $self->logconfess('A defined file argument is required');
  $file eq q[] and $self->logconfess('A non-empty file argument is required');

  if (not @suffixes) {
    @suffixes = @DEFAULT_FILE_SUFFIXES;
  }
  my $suffix_pattern = join q[|], @suffixes;
  my $suffix_regex = qr{[.]($suffix_pattern)$}msx;
  my ($suffix) = $file =~ $suffix_regex;

  my @avus;
  if ($suffix) {
    my ($base_suffix) = $suffix =~ m{^[.]?(.*)}msx;
    $self->debug("Parsed base suffix of '$file' as '$base_suffix'");
    push @avus, $self->make_avu($FILE_TYPE, $base_suffix);
  }
  else {
    $self->debug("Did not parse a suffix from '$file'");
  }

  return @avus;
}

=head2 make_md5_metadata

  Arg [1]    : Checksum, Str.

  Example    : my @avus = $ann->make_md5_metadata($checksum)
  Description: Return an array of metadata AVUs describing the
               file MD5 checksum.
  Returntype : Array[HashRef]

=cut

sub make_md5_metadata {
  my ($self, $md5) = @_;

  defined $md5 or $self->logconfess('A defined md5 argument is required');
  $md5 eq q[] and $self->logconfess('A non-empty md5 argument is required');

  return ($self->make_avu($FILE_MD5, $md5));
}

=head2 make_ticket_metadata

  Arg [1]    : string filename

  Example    : my @avus = $ann->make_ticket_metadata($ticket_number)
  Description: Return an array of metadata AVUs describing an RT ticket
               relating to the file.
  Returntype : Array[HashRef]

=cut

sub make_ticket_metadata {
  my ($self, $ticket_number) = @_;

  defined $ticket_number or
    $self->logconfess('A defined ticket_number argument is required');
  $ticket_number eq q[] and
    $self->logconfess('A non-empty ticket_number argument is required');

  return ($self->make_avu($RT_TICKET, $ticket_number));
}

sub _make_single_value_metadata {
  my ($self, $obj, $method_attr) = @_;
  # The method_attr argument is a map of method name to attribute name
  # under which the result will be stored.

  my @avus;
  foreach my $method_name (sort keys %{$method_attr}) {
    my $attr  = $method_attr->{$method_name};
    my $value = $obj->$method_name;

    if (defined $value) {
      $self->debug($obj, "::$method_name returned ", $value);
      push @avus, $self->make_avu($attr, $value);
    }
    else {
      $self->debug($obj, "::$method_name returned undef");
    }
  }

  return @avus;
}

no Moose::Role;

1;

__END__

=head1 NAME

WTSI::NPG::HTS::Annotator

=head1 DESCRIPTION

A role providing methods to calculate metadata for WTSI HTS runs. This
is used to create all the metadata for the WTSI::NPG::HTS
package. Please add new methods as required to create metadata, rather
than creating it inline in your own package.

=head1 AUTHOR

Keith James <kdj@sanger.ac.uk>, Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2015, 2016 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
