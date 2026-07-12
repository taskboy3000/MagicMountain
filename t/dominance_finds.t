use Modern::Perl;
use Test::More;
use FindBin;
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/lib");
use TestEnv;

use MagicMountain::Service::Dominance;

sub _dom {
    return MagicMountain::Service::Dominance->new(app => bless({}, 'UNIVERSAL'));
}

subtest 'threshold — insignificant changes omitted' => sub {
    my $dom = _dom;
    my $bias = { thermal => 1.05, storage => 0.97 };
    my $text = $dom->_finds_summary($bias, 0);
    is($text, 'No meaningful climate effect on prospecting today.',
        'all traits below 0.15 threshold produce neutral fallback');
};

subtest 'strong boost band — labels correctly' => sub {
    my $dom = _dom;
    my $bias = { thermal => 2.6, storage => 1.05 };
    my $text = $dom->_finds_summary($bias, 0);
    like($text, qr/Strong boost: thermal/, 'trait above 0.30 gets strong label');
    unlike($text, qr/storage/, 'trait below 0.15 threshold is omitted');
};

subtest 'moderate boost band' => sub {
    my $dom = _dom;
    my $bias = { food_processing => 1.2 };
    my $text = $dom->_finds_summary($bias, 0);
    like($text, qr/Moderate boost: food_processing/,
        'single moderate trait (deviation 0.20) gets moderate label');
};

subtest 'suppressed traits — values below 1 stay suppressed after scaling' => sub {
    my $dom = _dom;
    my $bias = { force => 0.5, revelation => 0.6 };
    my $text = $dom->_finds_summary($bias, 0);
    like($text, qr/Suppressed: (force|revelation)/,
        'traits below 1.0 appear as suppressed');
};

subtest 'both boost and suppress' => sub {
    my $dom = _dom;
    my $bias = { thermal => 2.6, force => 0.5 };
    my $text = $dom->_finds_summary($bias, 0);
    like($text, qr/Strong boost: thermal/, 'boost appears');
    like($text, qr/Suppressed: force/, 'suppress appears');
};

subtest 'positive instability' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({}, 2);
    like($text, qr/More unstable than usual/,
        'positive instability mod adds sentence');
};

subtest 'negative instability' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({}, -2);
    like($text, qr/More stable than usual/,
        'negative instability mod adds sentence');
};

subtest 'zero instability omitted' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({ thermal => 2.6 }, 0);
    unlike($text, qr/unstable/, 'zero instability omits sentence');
    like($text, qr/Strong boost: thermal/, 'traits still shown');
};

subtest 'boost only — no suppressed line' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({ thermal => 2.6 }, 0);
    unlike($text, qr/Suppressed/, 'no suppressed line when only boosts');
};

subtest 'suppressed only — no boost line' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({ force => 0.5 }, 0);
    unlike($text, qr/boost/i, 'no boost line when only suppressed');
};

subtest 'deterministic ordering — magnitude desc then alpha' => sub {
    my $dom = _dom;
    my $bias = { z => 2.1, a => 2.6, m => 2.1 };
    my $text = $dom->_finds_summary($bias, 0);
    like($text, qr/Strong boost: a, m, z/,
        'ordered by magnitude desc (2.6, 2.1, 2.1) then alpha (m before z)');
};

subtest 'full syndicate-dominant example' => sub {
    my $dom = _dom;
    my $bias = {
        thermal => 2.6, storage => 2.4,
        food_processing => 2.2, power => 2.2,
        force => 1.5, instability => 1.6, revelation => 1.6,
        water => 1.2,  # moderate band (deviation 0.20)
    };
    my $text = $dom->_finds_summary($bias, 2);
    like($text, qr/Strong boost: thermal, storage/, 'strong boost band');
    like($text, qr/Moderate boost: water/, 'moderate boost band');
    like($text, qr/More unstable than usual/, 'instability sentence');
};

subtest 'contested tier — neutral fallback' => sub {
    my $dom = _dom;
    my $text = $dom->_finds_summary({}, 0);
    is($text, 'No meaningful climate effect on prospecting today.',
        'empty biases and zero instability returns neutral fallback');
};

done_testing;
