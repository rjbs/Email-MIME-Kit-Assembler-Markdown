use strict;
use warnings;
use Test::More tests => 3;
use Email::MIME::Kit;
use Email::MIME::Kit::Assembler::Markdown;

my $kit = Email::MIME::Kit->new({ source => 't/kit/sample.mkit' });

my $email = $kit->assemble;

my @parts = $email->subparts;

like($email->content_type,    qr{multipart/alternative});
like($parts[0]->content_type, qr{text/plain});
like($parts[1]->content_type, qr{text/html});
