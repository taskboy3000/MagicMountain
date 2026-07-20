package MagicMountain::Bot::SkillPolicy;
use Mojo::Base '-base', '-signatures';

my %DECIDE = (
    immediate  => sub ($state, $params, $skills) {
        my $reserve = $params->{reserve} // 30;
        my $scrap   = $state->{scrap} // 0;

        my @affordable;
        for my $s (@$skills) {
            my $cur = $s->{current_level} // 0;
            next if $cur >= $s->{max_level};

            my $cost = $s->{levels}[$cur]{cost};
            next if $scrap < $cost + $reserve;

            push @affordable, {
                skill_id => $s->{id},
                level    => $cur + 1,
                cost     => $cost,
            };
        }

        return unless @affordable;
        @affordable = sort { $a->{cost} <=> $b->{cost} } @affordable;
        return $affordable[0];
    },

    specialize => sub ($state, $params, $skills) {
        my $reserve  = $params->{reserve} // 30;
        my $priority = $params->{priority} // [];
        my $scrap    = $state->{scrap} // 0;

        for my $skill_id (@$priority) {
            my ($s) = grep { $_->{id} eq $skill_id } @$skills;
            next unless $s;

            my $cur = $s->{current_level} // 0;
            next if $cur >= $s->{max_level};

            my $cost = $s->{levels}[$cur]{cost};
            next if $scrap < $cost + $reserve;

            return {
                skill_id => $skill_id,
                level    => $cur + 1,
                cost     => $cost,
            };
        }

        return;
    },

    never      => sub ($state, $params, $skills) { return },
);

sub decide ($state, $policy_params, $skills) {
    my $name = $policy_params->{name} // 'never';
    my $handler = $DECIDE{$name} || $DECIDE{never};
    return $handler->($state, $policy_params->{params} // {}, $skills);
}

1;
