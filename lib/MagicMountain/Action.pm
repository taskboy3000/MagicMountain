package MagicMountain::Action;
use Mojo::Base -base, -signatures;
use overload q("") => sub { shift->id }, fallback => 1;

has 'id';
has 'ap_cost'      => 0;
has 'requirements' => undef;
has 'executor'     => undef;
has 'logger'       => undef;
has 'description'  => undef;

1;
