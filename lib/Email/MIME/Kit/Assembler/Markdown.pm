package Email::MIME::Kit::Assembler::Markdown;
use Moose;
with 'Email::MIME::Kit::Role::Assembler';
# ABSTRACT: build multipart/alternative messages from Markdown alone

use Email::MIME::Creator;
use Moose::Util::TypeConstraints qw(maybe_type role_type);
use Text::Markdown;

=head1 SYNOPSIS

In your mkit's (JSON, here) manifest:

  {
    "renderer" : "TT",
    "assembler": [
      "Markdown",
      { "html_wrapper": "wrapper.html" }
    ],
    "path"  : "body.mkdn",
    "header": [
      { "Subject": "DynaWoop is now hiring!" },
      { "From"   : "[% from_addr  %]" }
      { "To"     : "[% user.email %]" }
    ]
  }

This kit will build a multipart/alternative message with a plaintext part
(containing the rendered contents of F<body.mkdn> ) and an HTML part
(containing F<body.mkdn> rendered into HTML using Markdown).

At present, attachments are not supported.  Actually, quite a few things found
in the standard assembler are not yet supported.  The standard assembler
desperately needs to be refactored to make its features easier to incorporate
into other assemblers.

The C<html_wrapper> parameter for the Markdown assembler is the path to a kit
entry.  If given, that kit entry will be used for the HTML part, and the
Markdown-produced HTML will be injected into it, replacing a comment containing
the C<marker> given in the Markdown assembler's configuration.  The default
marker is C<CONTENT>, so the F<wrapper.html> used above might read as follows:

  <h1>DynaWoop Dynamic Woopages</h1>
  <!-- CONTENT -->
  <p>Click to unsubscribe: <a href="[% unsub_url %]">here</a></p>

=cut

has manifest => (
  is       => 'ro',
  required => 1,
);

has html_wrapper => (
  is  => 'ro',
  isa => 'Str',
);

has renderer => (
  reader   => 'renderer',
  writer   => '_set_renderer',
  clearer  => '_unset_renderer',
  isa      => maybe_type(role_type('Email::MIME::Kit::Role::Renderer')),
  lazy     => 1,
  default  => sub { $_[0]->kit->default_renderer },
  init_arg => undef,
);

has marker => (is => 'ro', isa => 'Str', default => 'CONTENT');

has path => (
  is   => 'ro',
  isa  => 'Str',
  lazy => 1,
  default => sub { $_[0]->manifest->{path} },
);

sub BUILD {
  my ($self) = @_;
  my $class = ref $self;

  use Data::Dumper;
  warn Dumper($self->manifest);

  confess "$class does not support alternatives"
    if @{ $self->manifest->{alternatives} || [] };

  confess "$class does not support attachments"
    if @{ $self->manifest->{attachments} || [] };

  confess "$class does not support MIME content attributes"
    if %{ $self->manifest->{attributes} || {} };
}

sub _prep_header {
  my ($self, $header, $stash) = @_;

  my @done_header;
  for my $entry (@$header) {
    confess "no field name candidates"
      unless my (@hval) = grep { /^[^:]/ } keys %$entry;
    confess "multiple field name candidates: @hval" if @hval > 1;
    my $value = $entry->{ $hval[ 0 ] };

    if (ref $value) {
      my ($v, $p) = @$value;
      $value = join q{; }, $v, map { "$_=$p->{$_}" } keys %$p;
    } else {
      my $renderer = $self->renderer;
      if (exists $entry->{':renderer'}) {
        undef $renderer if ! defined $entry->{':renderer'};
        confess 'alternate renderers not supported';
      }

      $value = ${ $renderer->render(\$value, $stash) } if defined $renderer;
    }

    {
      use bytes;
      $value = Encode::encode('MIME-Q', $value) if $value =~ /[\x80-\xff]/;
    }
    push @done_header, $hval[0] => $value;
  }

  return \@done_header;
}

sub assemble {
  my ($self, $stash) = @_;
  
  my $markdown = ${ $self->kit->get_kit_entry( $self->path ) };
  if ($self->renderer) {
    my $output_ref = $self->renderer->render(\$markdown, $stash);
    $markdown = $$output_ref;
  }

  my $html_content = Text::Markdown->new(tab_width => 2)->markdown($markdown);
  my $wrapper_path = $self->html_wrapper;
  if ($wrapper_path) {
    my $wrapper = ${ $self->kit->get_kit_entry($wrapper_path) };
    my $marker  = $self->marker;
    my $marker_re = qr{<!--\s+\Q$marker\E\s+-->};

    confess 'html_wrapper content does not contain comment containing marker'
      unless $wrapper =~ $marker_re;

    $wrapper =~ s/$marker_re/$html_content/;
    $html_content = $wrapper;
  }

  my $header = $self->_prep_header(
    $self->manifest->{header},
    $stash,
  );

  my $html_part = Email::MIME->create(
    body   => $html_content,
    attributes => {
      content_type => "text/html",
      charset      => 'utf-8',
      encoding     => 'quoted-printable',
    },
  );

  my $text_part = Email::MIME->create(
    body   => $markdown,
    attributes => {
      content_type => "text/plain",
      charset      => 'utf-8',
      encoding     => 'quoted-printable',
    },
  );

  my $container = Email::MIME->create(
    header => $header,
    parts  => [ $text_part, $html_part ],
    attributes => { content_type => 'multipart/alternative' },
  );

  return $container; 
}

no Moose;
no Moose::Util::TypeConstraints;
1;
