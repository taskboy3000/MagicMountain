package TestCharacter;
use Modern::Perl;

sub new {
    my ($class, %data) = @_;
    bless { %data } => $class;
}

sub getCol {
    my ($self, $col) = @_;
    $self->{$col};
}
sub setCol {
    my ($self, $col, $val) = @_;
    $self->{$col} = $val;
}
sub save { 1 }  # stub — TestCharacter records are transient

1;
