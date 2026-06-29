requires 'Modern::Perl';
requires 'Mojolicious', '8.67';
requires 'JSON';
requires 'YAML::XS';
requires 'File::Slurp';
requires 'UUID::Tiny';
requires 'Perl::Tidy';
requires 'Cpanel::JSON::XS';
requires 'Perl::Critic';
requires 'Crypt::Bcrypt';


on 'test' => sub {
    requires 'Test::More';
    requires 'Test::Mojo';
    requires 'File::Temp';
};
