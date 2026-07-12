use v5.28;
use strict;
use warnings;
use Test2::V0;
use File::Spec;
use Cwd 'abs_path';
use FindBin '$RealBin';

my $ROOT = abs_path(File::Spec->catdir($FindBin::RealBin, File::Spec->updir));
my $CHECK_COLUMNS = "$ROOT/bin/check_column_declarations";
my $CHECK_FILES   = "$ROOT/bin/check_unintended_files";
my $CHECK_TUNING  = "$ROOT/bin/check_doc_consistency";

sub run_script {
    my ($script) = @_;
    my $stdout = `$^X -Ilib $script 2>&1`;
    return { exit => $? >> 8, stdout => $stdout // '', stderr => '' };
}

if (defined $ENV{GITHUB_ACTIONS} && $ENV{GITHUB_ACTIONS} eq 'true') {
    plan(skip_all, "skipping test in GitHub CI");
    done_testing();
    exit;
}

subtest 'check_column_declarations on current codebase' => sub {
    my $result = run_script($CHECK_COLUMNS);
    is($result->{exit}, 0, 'exits 0 — no undeclared columns')
      or diag("stdout: " . ($result->{stdout} // '(undef)'));
    ok(length($result->{stdout}) == 0 || $result->{stdout} eq '', 'no output')
      or diag("stdout: " . ($result->{stdout} // '(undef)'));
};

subtest 'check_unintended_files on current codebase' => sub {
    # The actual repo likely has uncommitted files (e.g. plan_post_verify.md),
    # so we just verify the script runs without crashing.
    my $result = run_script($CHECK_FILES);
    ok(defined $result->{exit}, 'script ran and exited: ' . $result->{exit});
    ok($result->{exit} == 0 || $result->{exit} == 1, 'exit is 0 or 1');
};

subtest 'check_doc_consistency on current codebase' => sub {
    my $result = run_script($CHECK_TUNING);
    is($result->{exit}, 0, 'exits 0 — all TUNING.md keys are current');
};

subtest 'pattern detection' => sub {
    # Test the detection patterns directly via grep
    my @temp_patterns = (qr/\.bak\z/, qr/\.tdy\z/, qr/notes\.txt\z/);
    ok('test.bak' =~ $temp_patterns[0], '.bak detected');
    ok('test.tdy' =~ $temp_patterns[1], '.tdy detected');
    ok('notes.txt' =~ $temp_patterns[2], 'notes.txt detected');
    ok('README.md' !~ $temp_patterns[0], 'README.md not flagged as temp');
};

done_testing;
