package MagicMountain::Bot::SkillPolicy;
use Mojo::Base '-base', '-signatures';

my %DECIDE = (
    immediate  => sub ($char, $params, $skills, $app) {
        my $reserve = $params->{reserve} // 30;
        my $scrap   = $char->getCol('scrap') // 0;

        my @affordable;
        for my $s (@$skills) {
            my $col = 'skill_' . $s->{id};
            my $cur = $char->getCol($col) // 0;
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

    specialize => sub ($char, $params, $skills, $app) {
        my $reserve  = $params->{reserve} // 30;
        my $priority = $params->{priority} // [];
        my $scrap    = $char->getCol('scrap') // 0;

        for my $skill_id (@$priority) {
            my ($s) = grep { $_->{id} eq $skill_id } @$skills;
            next unless $s;

            my $col = 'skill_' . $skill_id;
            my $cur = $char->getCol($col) // 0;
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

    never      => sub ($char, $params, $skills, $app) { return },
);

sub decide ($char, $policy_params, $skills, $app) {
    my $name = $policy_params->{name} // 'never';
    my $handler = $DECIDE{$name} || $DECIDE{never};
    return $handler->($char, $policy_params->{params} // {}, $skills, $app);
}

1;
