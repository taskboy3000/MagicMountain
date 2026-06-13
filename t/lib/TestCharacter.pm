package TestCharacter;
use Modern::Perl;

sub new {
    my ($class, %data) = @_;
    bless { %data } => $class;
}

1;
