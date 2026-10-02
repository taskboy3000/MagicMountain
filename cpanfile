requires 'Modern::Perl';
requires 'Mojolicious', '8.67';
requires 'JSON';
requires 'YAML::XS';
requires 'File::Slurp';
requires 'UUID::Tiny';
requires 'Perl::Tidy';
requires 'Cpanel::JSON::XS';
requires 'Crypt::Bcrypt';
requires 'PPI';

on 'develop' => sub {
    requires 'Perl::Tidy';
    requires 'Perl::Critic';
    requires 'Test2::V0';
    requires 'Test::More';
    requires 'Test::Mojo';
    requires 'Test::Exception';
    requires 'Test::Simple';
    requires 'File::Temp';
    requires 'IPC::Run3';
};
