# Model::Account — Module Boundary Rules

> See `Model.pm.md` for base-class rules. Account adds authentication
> helpers but must NOT reference game concepts.

## Additional Constraints
- NEVER reference characters, seasons, activities, or factions.
- NEVER set game defaults of any kind (scrap, score, AP, skills).

## Allowed Methods
- `find_by_id($player_id)` — returns account model instance or undef
- `find_by_username($name)` — returns account model instance or undef
- `create($name)` — creates account with UUID, returns it
- `save()` — persists to JSON file (inherited from Model)
