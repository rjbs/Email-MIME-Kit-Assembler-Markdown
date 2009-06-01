use strict;
use warnings;
use Test::More 'no_plan';
use Email::MIME::Kit;
use Email::MIME::Kit::Assembler::Markdown;

my $kit = Email::MIME::Kit->new({ source => 't/kit/sample.mkit' });

my $email = $kit->assemble;

warn $email->as_string;
