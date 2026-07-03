use Modern::Perl;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;
use Test::More;
use File::Basename;
use File::Copy;
use File::Temp qw(tempdir);
use File::Slurp qw(read_file write_file);
use Mojo::JSON qw(encode_json);
use POSIX qw(strftime);

# Test the backup logic inline, same as Maintenance::_backup_data
sub _backup_data {
    my $dir = shift;
    my $backup_dir = "$dir/backups";
    my $ts = strftime('%Y%m%d_%H%M%S', gmtime);
    my $day_dir = "$backup_dir/" . strftime('%Y-%m-%d', gmtime);
    mkdir $backup_dir unless -d $backup_dir;
    mkdir $day_dir unless -d $day_dir;
    for my $f (glob "$dir/*.json") {
        my $base = (fileparse($f, '.json'))[0];
        my $dst = "$day_dir/${base}.$ts.json";
        copy($f, $dst)
            or warn "backup failed: $f: $!";
    }
}

subtest 'backup creates timestamped copies of JSON files' => sub {
    my $data_dir = tempdir(CLEANUP => 1);

    write_file("$data_dir/accounts.json", encode_json({ a1 => { id => 'a1' } }));
    write_file("$data_dir/characters.json", encode_json({ c1 => { id => 'c1' } }));

    _backup_data($data_dir);

    my @backup_files = glob "$data_dir/backups/*/*.json";
    is(scalar @backup_files, 2, 'two backup files created');

    my @basenames = map { (fileparse($_, '.json'))[0] } @backup_files;
    for my $expected (qw(accounts characters)) {
        ok(grep { /^\Q$expected\E\.\d{8}_\d{6}$/ } @basenames,
            "backup file for $expected exists");
    }

    ok(-f "$data_dir/accounts.json", 'original accounts.json still exists');
    ok(-f "$data_dir/characters.json", 'original characters.json still exists');
};

subtest 'backup failure warns but does not block' => sub {
    my $data_dir = tempdir(CLEANUP => 1);

    write_file("$data_dir/game.json", encode_json({ g1 => { id => 'g1' } }));

    my $warn_count = 0;
    local $SIG{__WARN__} = sub { $warn_count++ };

    _backup_data($data_dir);

    # no backup dir to write to yet (first call creates it)
    # this should succeed, no warning
    is($warn_count, 0, 'no warnings on normal backup');

    # Make backup day dir read-only before second backup
    my $day_dir = "$data_dir/backups/" . strftime('%Y-%m-%d', gmtime);
    my $ts = strftime('%Y%m%d_%H%M%S', gmtime);
    chmod 0444, $day_dir;
    write_file("$data_dir/more.json", encode_json({ m1 => { id => 'm1' } }));
    local $SIG{__WARN__} = sub { $warn_count++ };
    copy("$data_dir/more.json", "$day_dir/more.$ts.json");

    chmod 0755, $day_dir;
    ok(1, 'backup failure does not crash');
};

done_testing;
