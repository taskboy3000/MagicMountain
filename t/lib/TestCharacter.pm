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
sub add_scrap {
    my ($self, $n) = @_;
    my $scrap = ($self->{scrap} // 0) + $n;
    $scrap = 0 if $scrap < 0;
    $self->{scrap} = $scrap;
}
sub add_score {
    my ($self, $n) = @_;
    $self->{score} = ($self->{score} // 0) + $n;
}
sub save { 1 }  # stub — TestCharacter records are transient

1;
