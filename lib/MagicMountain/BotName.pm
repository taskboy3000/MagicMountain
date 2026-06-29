package MagicMountain::BotName;
use Modern::Perl;
use Exporter 'import';
our @EXPORT_OK = qw(random_bot_name);

my @FIRST = qw(
  Zarn  Xylos  Threx  Korvax  Jexxa  Vorn  Myrrik  Selth  Draven
  Nyss  Orlan  Phaedra  Torvin  Bryn  Lyra  Zephyr  Kael  Renn
  Sycor  Aethon  Mordan  Cyllene  Vorlag  Jaxtar  Kalden  Seris
  Thane  Rylok  Ophira  Zeth  Malcor  Tyran  Astra  Vex  Soril
  Drekk  Yvaine  Kestrel  Halden  Mirek  Penth  Cindar  Valcor
  Zephon  Orax  Lysander  Thalia  Nerex  Quillon  Selene  Varek
);

my @LAST = qw(
  Stormrider  Ironvein  Darkmere  Voidseeker  Skarn  Frostburn
  Coldwrought  Deepdelver  Gravethorn  Sunder  Morningshade
  Nightrender  Stillwater  Coil  Ashwalker  Strangemark
  Redhand  Hollowpoint  Spireborn  Glassmere  Wraithe
  Corr  Nullthread  Carapace  Pall  Flicker  Cinderborn
  Wrack  Loam  Driftmark  Rustveil  Obsidian  Glimmer  Tomb
);

sub random_bot_name {
    my $first = $FIRST[rand @FIRST];
    my $last  = $LAST[rand @LAST];
    return "$first $last";
}

1;
